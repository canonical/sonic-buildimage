#!/bin/bash
# Sign (and optionally upload) source packages produced by
# build-source.sh, on the host.
#
# Deliberately not done inside the container: mounting the GPG agent
# socket into the DinD container is costly and fragile.
# Requires the host to have devscripts (debsign) and dput installed.
#
# Usage:
#   scripts/ppa/sign-upload.sh --key <KEYID> [<pkg>...]            sign only
#   scripts/ppa/sign-upload.sh --key <KEYID> --upload ppa:o/n ...  sign and upload
#   scripts/ppa/sign-upload.sh --dry-run [<pkg>...]                just list what would happen
set -euo pipefail
cd "$(dirname "$0")/../.."

KEY=""; PPA=""; DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --key)     [ $# -ge 2 ] || { echo "usage: scripts/ppa/sign-upload.sh --key <KEYID> [--upload ppa:o/n] [--dry-run] [<pkg>...]" >&2; exit 2; }; KEY="$2"; shift 2 ;;
        --upload)  [ $# -ge 2 ] || { echo "usage: scripts/ppa/sign-upload.sh --key <KEYID> --upload ppa:o/n [<pkg>...]" >&2; exit 2; }; PPA="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *)         break ;;
    esac
done

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
    mapfile -t pkgs < <(find target/source -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
fi
[ ${#pkgs[@]} -gt 0 ] || { echo "nothing in target/source/; run build-source.sh first" >&2; exit 1; }

for p in "${pkgs[@]}"; do
    changes=$(ls "target/source/$p"/*_source.changes 2>/dev/null | head -1) || true
    [ -n "$changes" ] || { echo "$p: no _source.changes; run build-source.sh first" >&2; exit 1; }

    if [ "$DRY" = 1 ]; then
        echo "would debsign${KEY:+ -k $KEY} $changes"
        [ -n "$PPA" ] && echo "would dput $PPA $changes"
        continue
    fi

    [ -n "$KEY" ] || { echo "--key is required unless --dry-run" >&2; exit 2; }
    debsign -k "$KEY" "$changes"
    echo "signed $changes"

    if [ -n "$PPA" ]; then
        dput "$PPA" "$changes"
        echo "uploaded $changes -> $PPA"
    fi
done
