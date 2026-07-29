#!/bin/bash
# Produce unsigned Debian source packages for one or more packages, for
# upload to a Launchpad PPA.
#
# Run inside the slave-resolute container (needs dget / dch /
# dpkg-source; the container already has devscripts). Deliberately does
# not sign or upload: GPG and dput are handled by
# scripts/ppa/sign-upload.sh on the host.
#
# Usage: scripts/ppa/build-source.sh <pkg>...
#   e.g.: scripts/ppa/build-source.sh libteam isc-dhcp lm-sensors
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <pkg>..." >&2; exit 2; }

# This script is meant to run inside the slave-resolute container (see the
# header comment above); on a bare host missing devscripts/dpkg-dev/
# debhelper it would otherwise fail well into the first package's
# dget/dpkg-source/dch/curl sequence instead of up front, and -- worse --
# fail on the SECOND package after already leaving the first package's
# $WORK download in place. `dh` specifically is not invoked by this script
# directly, but `dpkg-buildpackage -S` below runs `debian/rules clean`
# first, and every package wired up here uses debhelper's dh in that
# target -- confirmed on this host: dpkg-buildpackage -S fails with
# "make: dh: No such file or directory" when debhelper isn't installed.
missing=""
for tool in dget dpkg-source dpkg-buildpackage dpkg-parsechangelog dch curl patch dh; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] || { echo "$0: missing required tool(s):$missing -- run this inside the slave-resolute container (devscripts + dpkg-dev + debhelper)" >&2; exit 1; }

# dch (invoked per-package below) falls back to $LOGNAME@<container hostname>
# when DEBEMAIL/DEBFULLNAME are unset, so the changelog author in the
# generated .dsc/.changes would depend on whichever machine happened to run
# this -- not reproducible across developers, and not an identity fit for a
# package destined for a public PPA. Require both explicitly rather than
# defaulting to one: make sonic-slave-run passes the environment through
# (set DEBEMAIL/DEBFULLNAME in SONIC_RUN_CMDS, or export them before calling
# this script directly), so there is no need to hardcode anything here. The
# GPG signing identity is a separate concern, set independently via
# sign-upload.sh --key.
[ -n "${DEBEMAIL:-}" ] && [ -n "${DEBFULLNAME:-}" ] || { echo "$0: DEBEMAIL and DEBFULLNAME must both be set -- dch needs a reproducible changelog author, not whatever \$LOGNAME@hostname this container happens to have; make sonic-slave-run passes the environment through, so set them in SONIC_RUN_CMDS (this is separate from the GPG signing identity, which sign-upload.sh --key sets independently)" >&2; exit 1; }

cd "$(dirname "$0")/../.."
REPO=$PWD
# patch_class(): determines whether a patch touches debian/*, touches
# outside debian/*, or touches both. test-build-source.sh needs the
# same logic, so it's factored into a shared file instead of duplicated.
source "$REPO/scripts/ppa/patch-class.sh"
# query_pkg(): queries one package's PPA-related facts and loads them into
# the current shell as Q_* variables; manifest.sh and test-build-source.sh
# share this same implementation.
source "$REPO/scripts/ppa/query-pkg.sh"

# One $WORK per package; under set -e, any package failing partway
# through makes the script exit immediately, skipping the cleanup at
# the end of that package's loop body. Track every $WORK created so
# far in an array and clean them all up in one EXIT trap -- cleaning
# only the last one isn't enough, since the $WORK dirs of
# already-succeeded packages won't disappear on their own.
WORK_DIRS=()
cleanup_work_dirs() {
    local d
    for d in "${WORK_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup_work_dirs EXIT

for PKG in "$@"; do
    echo "=== $PKG"
    query_pkg "$PKG" || exit 1

    [ -n "${Q_DSC_URL:-}" ] || { echo "$PKG: <PREFIX>_DSC_URL is not set in rules/$PKG.mk" >&2; exit 1; }
    [ -n "${Q_STOCK_VERSION:-}" ] || { echo "$PKG: <PREFIX>_VERSION_STOCK is not set in rules/$PKG.mk" >&2; exit 1; }

    # Only consider patches currently active in series: a commented-out
    # patch file that will never be applied shouldn't hold up this
    # build just because it happens to contain a binary diff; the
    # later loop that appends patches also reuses this list, so series
    # doesn't need to be grepped again.
    #
    # grep exiting 1 here (no active-patch lines matched) is a legitimate
    # exit status to handle explicitly, not a real error; exiting >=2 (e.g.
    # the series file itself is unreadable) is a real error, checked
    # separately below. The resulting state -- zero active patches -- is a
    # different problem, checked once ACTIVE_PATCHES is actually built (see
    # below): a source package built from it would be a real error even
    # though nothing here failed. Read via command substitution rather than
    # `mapfile < <(...)`: process substitution decouples grep's exit status
    # from this command entirely -- the same defect class fixed in
    # query_pkg() (see query-pkg.sh) -- so a missing/unreadable series file
    # would otherwise silently look identical to "zero active patches"
    # instead of erroring.
    rc=0
    active_patches_raw=$(grep -vE '^\s*(#|$)' "$REPO/$Q_PATCH_DIR/series") || rc=$?
    [ "$rc" -le 1 ] || { echo "$PKG: could not read patch series at $Q_PATCH_DIR/series (grep exit $rc)" >&2; exit 1; }
    # mapfile against an empty herestring produces a one-element array holding
    # an empty string, not zero elements -- guard explicitly so a series with
    # zero active patches ends up with a genuinely empty array.
    ACTIVE_PATCHES=()
    if [ -n "$active_patches_raw" ]; then
        mapfile -t ACTIVE_PATCHES <<< "$active_patches_raw"
    fi
    # A source package built from zero active patches would be stock content
    # under a +suffix version -- identical to the stock package it claims to
    # differ from. That is never a legitimate output of this tool (the whole
    # point of the suffix is that SONiC changed something), whether series is
    # completely empty or every line in it is commented out; both reach here
    # with the same empty ACTIVE_PATCHES.
    [ "${#ACTIVE_PATCHES[@]}" -gt 0 ] || { echo "$PKG: $Q_PATCH_DIR/series has zero active patches -- refusing to build a +suffix source package with no SONiC changes" >&2; exit 1; }
    for p in "${ACTIVE_PATCHES[@]}"; do
        # A patch containing a binary file needs
        # debian/source/include-binaries; none of this batch needs it,
        # but this must error out explicitly instead of silently
        # producing a package that dpkg-source will reject.
        if grep -q $'^GIT binary patch' "$REPO/$Q_PATCH_DIR/$p" 2>/dev/null; then
            echo "$PKG: $p contains a binary diff; needs debian/source/include-binaries" >&2
            exit 1
        fi
    done

    # In dpkg-source's "3.0 (quilt)" format, debian/patches/* is only
    # applied to the upstream code; the debian/ directory itself is
    # baked into its final state via debian.tar. If a patch is both
    # listed in series and actually touches files under debian/,
    # dpkg-source -b will treat that change as "applied twice" when it
    # rebuilds the verification tree and reject it ("Reversed (or
    # previously applied) patch detected!"). Split by patch_class()'s
    # verdict into two groups: patches that only touch debian/* are
    # baked directly into the extracted tree, everything else goes into
    # series as usual; a patch that touches both can't be decided
    # automatically, so error out and leave the split to a human.
    DEBIAN_PATCHES=()
    UPSTREAM_PATCHES=()
    for p in "${ACTIVE_PATCHES[@]}"; do
        case "$(patch_class "$REPO/$Q_PATCH_DIR/$p")" in
            debian)   DEBIAN_PATCHES+=("$p") ;;
            upstream) UPSTREAM_PATCHES+=("$p") ;;
            mixed)
                echo "$PKG: $p touches both debian/ and non-debian/ paths; dpkg-source's quilt format can't take it either way automatically — split it by hand into a debian/-only patch and an upstream-only patch" >&2
                exit 1
                ;;
            invalid)
                echo "$PKG: $p has no recognized a/-, b/- or /dev/null-shaped diff header (e.g. empty file, or a -p0-style diff); cannot classify it as debian/ or upstream" >&2
                exit 1
                ;;
            *)
                echo "$PKG: $p: patch_class printed an unrecognized value; refusing to guess" >&2
                exit 1
                ;;
        esac
    done

    WORK=$(mktemp -d)
    WORK_DIRS+=("$WORK")
    OUT="$REPO/target/source/$PKG"
    mkdir -p "$OUT"

    pushd "$WORK" >/dev/null
    # -u is structurally required: on the Ubuntu slave, the .dsc
    # uploader's personal key isn't in any usable keyring, and
    # installing debian-keyring still can't verify it.
    #
    # -d: download only, don't unpack. A plain `dget -u` would
    # automatically run `dpkg-source -x`, applying all of upstream's
    # debian/patches to the working tree and leaving only .pc to record
    # that those upstream patches are applied. We then append the
    # SONiC patch names to that same series, but their content is not
    # applied (that's left for the builder to apply at build time) --
    # which would leave series partly applied (the upstream part) and
    # partly unapplied (the SONiC part), so the working tree and series
    # would no longer agree. For a package with 10 upstream patches
    # (e.g. isc-dhcp), in that state `dpkg-source -b` fails with
    # "aborting due to unexpected upstream changes": it re-expands a
    # reference tree from the full series and, comparing it against the
    # current working tree, finds every file touched by a SONiC patch
    # disagrees.
    dget -d -u "$Q_DSC_URL"

    DSC=$(find . -maxdepth 1 -type f -name '*.dsc' | head -1)
    [ -n "$DSC" ] || { echo "$PKG: dget -d did not leave a .dsc in $WORK" >&2; exit 1; }
    # --skip-patches: unpack but apply zero patches (not even
    # upstream's), keeping the working tree pristine. series therefore
    # stays entirely "unapplied" from start to finish, matching how we
    # later append SONiC patch names -- so the half-applied state
    # described above never happens.
    dpkg-source --skip-patches -x "$DSC"

    SRCDIR=$(find . -maxdepth 1 -type d -name "$Q_SOURCE-*" | head -1)
    [ -n "$SRCDIR" ] || { echo "$PKG: cannot find extracted source dir for $Q_SOURCE" >&2; exit 1; }
    pushd "$SRCDIR" >/dev/null

    # Some stock packages (e.g. lm-sensors) have a dpkg epoch in the
    # top debian/changelog entry (e.g. "1:3.6.2-2build1"), even though
    # the archive filename/URL never carries the epoch. If the dch
    # --newversion below omitted the epoch, the new entry would be
    # treated as implicit epoch 0 -- "older" than the official archive
    # version, so any machine that already has the official package
    # would never apt upgrade to our PPA build. Read the epoch here
    # while the changelog is still pristine and carry it forward
    # unchanged; while at it, verify that the hand-written
    # <PREFIX>_VERSION_STOCK in rules/<pkg>.mk agrees with what
    # changelog records (with the epoch stripped), to catch a typo in
    # the hand-written version.
    STOCK_CHANGELOG_VERSION=$(dpkg-parsechangelog --show-field Version)
    EPOCH=""
    case "$STOCK_CHANGELOG_VERSION" in
        *:*) EPOCH="${STOCK_CHANGELOG_VERSION%%:*}:" ;;
    esac
    if [ "${STOCK_CHANGELOG_VERSION#*:}" != "$Q_STOCK_VERSION" ]; then
        echo "$PKG: debian/changelog's stock version is '$STOCK_CHANGELOG_VERSION' but rules/$PKG.mk's <PREFIX>_VERSION_STOCK is '$Q_STOCK_VERSION' -- they must agree (ignoring any epoch)" >&2
        exit 1
    fi

    # Patches that only touch debian/* are baked directly into the
    # extracted tree (becoming part of the debian tarball itself), not
    # added to series -- they are not "upstream patches the builder
    # applies at build time".
    for p in "${DEBIAN_PATCHES[@]}"; do
        if ! patch -p1 -N -f -s -F0 < "$REPO/$Q_PATCH_DIR/$p"; then
            echo "$PKG: debian/-only patch $p did not apply cleanly to the extracted tree" >&2
            exit 1
        fi
    done

    # The rest (patches touching only outside debian/*) are appended to
    # series in the same order; the patches themselves stay unapplied,
    # left for the builder to apply at build time.
    mkdir -p debian/patches
    [ -f debian/patches/series ] || : > debian/patches/series
    for p in "${UPSTREAM_PATCHES[@]}"; do
        cp "$REPO/$Q_PATCH_DIR/$p" debian/patches/
        echo "$p" >> debian/patches/series
    done

    # rm -rf .pc is no longer needed: --skip-patches never applies any
    # patch, so .pc is never created.

    dch --newversion "${EPOCH}${Q_STOCK_VERSION}${Q_SUFFIX}" \
        --distribution resolute --force-distribution \
        "SONiC packaging for Ubuntu resolute: apply the $PKG patch series from sonic-buildimage."

    # The first upload of a given upstream version needs the orig
    # (-sa); every later upload must use -sd, or Launchpad will reject
    # it over an orig checksum conflict. Decide based on whether the
    # orig is already present in the PPA pool; when that can't be
    # determined, default conservatively to -sa -- re-uploading an
    # orig unnecessarily is usually harmless, but a first upload
    # missing the orig is rejected by Launchpad outright, so between
    # the two risks this is the lesser one.
    # The pool URL comes from query.mk (see Q_PPA_POOL_URL); it is not
    # re-derived here with sed from the ppa_pool_dir logic -- that
    # would leave the same rule with two implementations.
    SA_FLAG=-sd
    if [ -n "${Q_PPA_POOL_URL:-}" ]; then
        # -F on the $Q_SOURCE half: it is interpolated from rules/*.mk, and
        # BRE metacharacters in it (e.g. a literal '.') would otherwise be
        # read as regex syntax instead of matched literally.
        if ! curl -sfL "$Q_PPA_POOL_URL/" | grep -F -- "${Q_SOURCE}_" | grep -q '\.orig\.'; then
            SA_FLAG=-sa
        fi
    else
        echo "  note: SONIC_PPA_URL unset, cannot tell if the orig is already uploaded; using -sa for the first local run" >&2
        SA_FLAG=-sa
    fi

    dpkg-buildpackage -S "$SA_FLAG" -us -uc -d
    popd >/dev/null

    # $WORK also still holds dget's original stock download (same basenames
    # minus our suffix): a blanket */*.dsc glob would carry that stock .dsc
    # into $OUT too, and a consumer that expects exactly one .dsc there (e.g.
    # build-clean.sh) would break. Scope the move to the version we just built.
    #
    # The orig tarball is collected independently of $SA_FLAG: -sd only tells
    # dpkg-buildpackage not to *reference* the orig in *.changes, it does not
    # delete the physical .orig.tar.* that dget already placed in $WORK. So the
    # orig must always be picked up when present, or build-clean.sh's
    # `dpkg-source -x` (which needs the orig alongside the .dsc) breaks on
    # every -sd run — i.e. every build after a package's first upload.
    # Only clear the regular files directly in $OUT, not the directory itself:
    # build-clean.sh creates $OUT/build/ in this same tree, and a bare `rm -f
    # "$OUT"/*` fails under set -e as soon as that subdirectory exists ("Is a
    # directory"), aborting before any new .dsc/.changes/orig is moved in. A
    # previous clean-container result is worth keeping until deliberately
    # replaced, so this deletes files only and leaves build/ (or any other
    # subdirectory) untouched; it is not `rm -rf "$OUT"`.
    find "$OUT" -maxdepth 1 -type f -delete
    mv ./"${Q_SOURCE}_${Q_STOCK_VERSION}${Q_SUFFIX}"* "$OUT"/
    # Single-component orig only (<src>_<ver>.orig.tar.*): a multi-component
    # orig would be named <src>_<ver>.orig-<component>.tar.*, which this glob
    # does not match. No package wired up here needs one; add matching support
    # if/when one does.
    shopt -s nullglob
    orig=(./*.orig.tar.*)
    shopt -u nullglob
    [ "${#orig[@]}" -eq 0 ] || mv "${orig[@]}" "$OUT"/
    popd >/dev/null

    echo "  -> $OUT"
    ls -1 "$OUT"
done
