#!/bin/bash
# Build an already-generated source package inside a one-shot
# ubuntu:resolute container, to simulate the Launchpad builder.
# Acceptance criterion #1.
#
# Deliberately not using the slave image: the slave image has a large
# set of build-deps preinstalled and carries the Dh_Lib.pm patch, so
# using it would fail to catch issues like a missing out-of-tree action,
# and would not verify .ddeb behavior.
# Deliberately not using sbuild/pbuilder: that would require sudo to
# install things on the host and create a persistent chroot.
#
# Usage: scripts/ppa/build-clean.sh <pkg>
set -euo pipefail

PKG="${1:?usage: $0 <pkg>}"

# This whole script is built around `docker run`; fail immediately with a
# clear message instead of a bare "docker: command not found" once the
# apt-get/dpkg-buildpackage sequence below is already midway through.
command -v docker >/dev/null 2>&1 || { echo "$0: docker is required (this script builds inside a one-shot ubuntu:resolute container) but was not found on PATH" >&2; exit 1; }

cd "$(dirname "$0")/../.."
REPO=$PWD
SRCDIR="$REPO/target/source/$PKG"

ls "$SRCDIR"/*.dsc >/dev/null 2>&1 || { echo "$PKG: no .dsc in $SRCDIR; run build-source.sh first" >&2; exit 1; }

rm -rf "$SRCDIR/build"

# apt-get build-dep ./ reads the unpacked debian/control, so it doesn't
# need deb-src sources -- the ubuntu:resolute image's default sources
# are enough.
docker run --rm \
    -v "$SRCDIR:/src" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    ubuntu:resolute bash -euc '
        apt-get -qq update
        apt-get -qq install -y --no-install-recommends build-essential devscripts
        mkdir /build && cd /build
        dpkg-source -x /src/*.dsc pkg
        cd pkg
        apt-get -qq build-dep -y --no-install-recommends ./
        dpkg-buildpackage -b -us -uc
        mkdir -p /src/build
        # Each package's set of artifacts differs (some have no dbgsym,
        # some have an _all.deb), so each glob is allowed to fail to
        # match on its own; but at least one artifact must exist,
        # otherwise it's a real failure and must not be swallowed by
        # || true.
        cp -a /build/*.deb  /src/build/ 2>/dev/null || true
        cp -a /build/*.ddeb /src/build/ 2>/dev/null || true
        # chown must happen before the artifact-count check below: if
        # the check fails it will exit 1 and end the container early,
        # and even with zero artifacts /src/build still needs to be
        # handed back to the host user, otherwise the next run's
        # host-side rm -rf of this directory will lack permission
        # because it's owned by root.
        chown -R "$HOST_UID:$HOST_GID" /src/build
        n=$(ls -1 /src/build | wc -l)
        [ "$n" -gt 0 ] || { echo "build produced no .deb/.ddeb artifacts" >&2; exit 1; }
        echo "collected $n artifact(s)"
    '

echo "== $PKG built in a clean ubuntu:resolute container:"
ls -1 "$SRCDIR/build"
