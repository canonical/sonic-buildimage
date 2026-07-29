# Fetch one package's PPA-related facts from scripts/ppa/query.mk and load them
# into the caller's shell as the ten Q_* variables.
#
# scripts/ppa/build-source.sh, scripts/ppa/tests/test-build-source.sh and
# scripts/ppa/manifest.sh each used to inline this read loop separately, and
# only one of the three copies got the fix below -- so it lives here once
# instead, the same way patch_class() lives in scripts/ppa/patch-class.sh.
#
# Usage (source this file, do not execute it):
#   source scripts/ppa/query-pkg.sh
#   query_pkg <pkg> || exit 1                    # abort the whole script
#   query_pkg <pkg> || { fail=1; continue; }      # report-and-skip, keep going
#
# On success: sets Q_PKG, Q_MODE, Q_STOCK_VERSION, Q_DSC_URL, Q_SUFFIX,
# Q_PATCH_DIR, Q_MAIN_DEB, Q_DERIVED_DEBS, Q_SOURCE and Q_PPA_POOL_URL in the
# caller's scope and returns 0.
#
# On failure -- query.mk exiting non-zero, or exiting zero but not reporting
# all ten keys -- prints a diagnostic naming the package to stderr, unsets all
# ten Q_* variables so no stale value from a previous call survives, and
# returns 1. query_pkg never calls exit itself: a caller that must keep going
# after one package fails (report-and-skip, not abort) relies on that.
#
# The bug this replaces: `while IFS='=' read -r k v; do declare "Q_$k=$v";
# done < <(make ...)` runs the read loop against a process substitution, so a
# non-zero make exit status there is invisible to the caller's `set -e`; and
# `declare` only ever *sets* a variable, it never clears one a previous
# iteration set. Given two packages in one invocation, the second one failing
# would silently leave the first package's Q_* values in place instead of
# erroring -- and a caller that then uses $OUT from the *new* package's name
# with $Q_* data from the *old* package can, e.g., stage the wrong package's
# source tree under the new package's directory.
#
# A second, narrower bug the line-parsing loop below guards against: `out` is
# captured with `2>&1`, so any stderr line make (or a future $(warning ...) in
# some rules/*.mk) emits on an otherwise-successful run lands in the same
# stream that gets parsed as KEY=value pairs. A line like "Makefile:12:
# warning: overriding recipe for target" has no valid KEY before its first
# '=' (it may have no '=' at all) -- `declare -g "Q_$k=$v"` on that would fail
# with "not a valid identifier", and that failure is not behind any `if`/`||`,
# so under the caller's `set -e` it would exit the caller's shell right there
# -- exactly the failure mode query_pkg exists to prevent. Every parsed line
# is checked against the ten keys' actual shape (`^[A-Z][A-Z0-9_]*$`) before
# it is ever handed to `declare`; anything else is reported and skipped, never
# declared.
query_pkg() {
    local pkg="$1"
    local out rc=0

    unset -v Q_PKG Q_MODE Q_STOCK_VERSION Q_DSC_URL Q_SUFFIX Q_PATCH_DIR \
        Q_MAIN_DEB Q_DERIVED_DEBS Q_SOURCE Q_PPA_POOL_URL

    # Capture the make status via a plain command substitution, not a process
    # substitution: `x=$(cmd)` propagates cmd's exit status to the assignment
    # itself, so the `|| rc=$?` below actually sees it.
    out=$(make -s -f scripts/ppa/query.mk PKG="$pkg" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "$pkg: query.mk failed:" >&2
        printf '%s\n' "$out" | sed 's/^/    /' >&2
        return 1
    fi

    # declare -g: this runs inside a function, and plain `declare` there would
    # make each Q_* local to query_pkg instead of visible to the caller.
    #
    # Only lines whose key matches query.mk's actual key shape are declared;
    # anything else (a stray stderr line merged in by the 2>&1 above) is
    # reported and skipped instead of being passed to `declare`, which would
    # otherwise abort the caller's shell on an invalid identifier -- see the
    # header comment's second bug.
    local line k v
    while IFS= read -r line; do
        k="${line%%=*}"
        v="${line#*=}"
        if [[ "$line" == *=* && "$k" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            declare -g "Q_$k=$v"
        else
            echo "$pkg: query.mk: ignoring unexpected output line: $line" >&2
        fi
    done <<< "$out"

    local missing="" req var
    for req in PKG MODE STOCK_VERSION DSC_URL SUFFIX PATCH_DIR MAIN_DEB DERIVED_DEBS SOURCE PPA_POOL_URL; do
        var="Q_$req"
        [ -n "${!var+x}" ] || missing="$missing $req"
    done
    if [ -n "$missing" ]; then
        echo "$pkg: query.mk did not report:$missing" >&2
        unset -v Q_PKG Q_MODE Q_STOCK_VERSION Q_DSC_URL Q_SUFFIX Q_PATCH_DIR \
            Q_MAIN_DEB Q_DERIVED_DEBS Q_SOURCE Q_PPA_POOL_URL
        return 1
    fi

    return 0
}
