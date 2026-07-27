#!/bin/bash
#
# Audit this repository's submodule gitlinks against an upstream reference.
#
# Canonical's fork carries resolute-specific commits in several submodules. The
# healthy state for such a submodule is a strict fast-forward from upstream: the
# commit upstream records is an ancestor of ours, with our commits replayed on
# top. When a submodule branch diverges from upstream instead, a rebase of this
# repository has to keep our gitlink to preserve those commits, which silently
# drops upstream changes from the build. Sync a diverged submodule by rebasing
# its branch onto the upstream commit, then bump the gitlink here.
#
# The audit also reports two failure modes that break a fresh clone or a build:
# a gitlink that exists on no remote at all, and a .gitmodules URL that is not
# https.
#
# Usage:
#   scripts/submodule-ff-audit.sh [upstream-ref]     # default: sonic-net/202605
#
# Set SUBMODULE_FF_AUDIT_FETCH=1 to refresh submodule remotes first; otherwise
# reachability is judged from the remote-tracking refs already on disk.
#
# Exit status: 0 when every submodule is identical to upstream or a strict
# fast-forward from it, 1 when any submodule has diverged, is behind, carries a
# gitlink that is on no remote, or has a non-https URL.

set -u

UPSTREAM_REF="${1:-sonic-net/202605}"
FETCH="${SUBMODULE_FF_AUDIT_FETCH:-0}"

cd "$(git rev-parse --show-toplevel)" || exit 1

if ! git rev-parse --verify --quiet "$UPSTREAM_REF^{commit}" >/dev/null; then
    echo "error: upstream ref '$UPSTREAM_REF' not found; fetch it first" >&2
    exit 1
fi

gitlinks() { git ls-tree -r --full-tree "$1" | awk '$2 == "commit" { print $4, $3 }' | sort; }

OURS_LIST=$(gitlinks HEAD)
UP_LIST=$(gitlinks "$UPSTREAM_REF")

n_same=0 n_ff=0 n_diverged=0 n_behind=0 n_skipped=0
diverged_paths="" problem_paths=""

printf '%-46s %-10s %-10s %s\n' 'SUBMODULE' 'OURS' 'UPSTREAM' 'VERDICT'
printf '%.0s-' $(seq 1 118); printf '\n'

while read -r path ours; do
    up=$(printf '%s\n' "$UP_LIST" | awk -v p="$path" '$1 == p { print $2 }')
    [ -n "$up" ] || continue    # not a submodule upstream knows about

    if [ "$ours" = "$up" ]; then
        n_same=$((n_same + 1))
        continue                # identical to upstream: nothing to report
    fi

    if [ ! -e "$path/.git" ]; then
        printf '%-46s %-10s %-10s %s\n' "$path" "${ours:0:9}" "${up:0:9}" \
               'SKIPPED  not initialised (git submodule update --init)'
        n_skipped=$((n_skipped + 1))
        continue
    fi

    if [ "$FETCH" = "1" ]; then
        git -C "$path" fetch --quiet --all --no-tags 2>/dev/null
    fi

    missing=""
    for obj in "$ours" "$up"; do
        git -C "$path" cat-file -e "$obj^{commit}" 2>/dev/null || missing="$missing $obj"
    done
    if [ -n "$missing" ]; then
        printf '%-46s %-10s %-10s %s\n' "$path" "${ours:0:9}" "${up:0:9}" \
               "SKIPPED  commit not present locally:$missing (retry with SUBMODULE_FF_AUDIT_FETCH=1)"
        n_skipped=$((n_skipped + 1))
        problem_paths="$problem_paths $path"
        continue
    fi

    if git -C "$path" merge-base --is-ancestor "$up" "$ours"; then
        n_ff=$((n_ff + 1))
        verdict="OK       strict ff: upstream is an ancestor, $(git -C "$path" rev-list --count "$up..$ours") commit(s) of ours on top"
    elif git -C "$path" merge-base --is-ancestor "$ours" "$up"; then
        n_behind=$((n_behind + 1))
        diverged_paths="$diverged_paths $path"
        verdict="BEHIND   $(git -C "$path" rev-list --count "$ours..$up") upstream commit(s) missing, none of ours on top: bump the gitlink"
    else
        n_diverged=$((n_diverged + 1))
        diverged_paths="$diverged_paths $path"
        verdict="DIVERGED missing $(git -C "$path" rev-list --count "$ours..$up") upstream / $(git -C "$path" rev-list --count "$up..$ours") ours: rebase the submodule branch"
    fi

    # A gitlink on no remote leaves a fresh clone unable to initialise the
    # submodule, so report it whatever the ancestry says.
    if [ -z "$(git -C "$path" branch -r --contains "$ours" 2>/dev/null)" ]; then
        verdict="$verdict; gitlink is on NO REMOTE (push it before committing the bump)"
        problem_paths="$problem_paths $path"
    fi

    # A worktree checked out elsewhere is only informational: the gitlink, not
    # the checkout, is what the build graph pins.
    head=$(git -C "$path" rev-parse HEAD 2>/dev/null)
    if [ "$head" != "$ours" ]; then
        verdict="$verdict; worktree at ${head:0:9}"
    fi

    printf '%-46s %-10s %-10s %s\n' "$path" "${ours:0:9}" "${up:0:9}" "$verdict"
done <<EOF
$OURS_LIST
EOF

non_https=$(git config --file .gitmodules --get-regexp '\.url$' | awk '$2 !~ /^https:\/\// { print $1, $2 }')
if [ -n "$non_https" ]; then
    printf '\nnon-https .gitmodules URLs (anonymous and CI clones will fail):\n%s\n' "$non_https"
fi

printf '\nupstream: %s (%s)\n' "$UPSTREAM_REF" "$(git rev-parse --short "$UPSTREAM_REF")"
printf 'identical to upstream: %d   strict ff: %d   diverged: %d   behind: %d   skipped: %d\n' \
       "$n_same" "$n_ff" "$n_diverged" "$n_behind" "$n_skipped"

if [ -n "$diverged_paths" ] || [ -n "$problem_paths" ] || [ -n "$non_https" ]; then
    [ -n "$diverged_paths" ] && printf 'needs a submodule rebase or gitlink bump:%s\n' "$diverged_paths"
    [ -n "$problem_paths" ] && printf 'needs a push or a fetch:%s\n' "$problem_paths"
    exit 1
fi

printf 'every submodule is identical to upstream or a strict fast-forward from it\n'
