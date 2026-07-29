# Determine whether a patch's touched paths are entirely under
# debian/, entirely outside debian/, or a mix of both.
#
# In dpkg-source's "3.0 (quilt)" format, debian/patches/* is only
# applied to the upstream code; the debian/ directory itself is
# packaged with the final content in debian.tar. When dpkg-source -b
# rebuilds the verification tree, it reapplies every patch listed in
# series from scratch and compares the result against the current
# working tree -- if a patch is both listed in series and actually
# touches files under debian/, that change is already in its final
# state in the working tree, so reapplying it amounts to applying it a
# second time, and dpkg-source reports "Reversed (or previously
# applied) patch detected!".
#
# Handle patches differently based on the paths they touch:
#   - only touches debian/* -> bake directly into the extracted tree,
#     don't add to series
#   - only touches outside debian/* -> add to series as usual, leave
#     it for the builder to apply at build time
#   - touches both -> neither rule above applies; error out and leave
#     the split to a human, don't guess
#
# Usage (source this file, don't execute it directly):
#   source scripts/ppa/patch-class.sh
#   patch_class <patch file>   # prints debian / upstream / mixed / invalid to stdout
#
# Basis for the decision: whether the path left after stripping the
# first path component (the a/, b/ prefix produced by quilt refresh -p
# ab) from each "--- " and "+++ " header starts with debian/. Both
# headers must be checked, not just "+++ ": for a hunk that deletes a
# file, the real path is on the "--- " line, and the "+++ " line is
# just the literal /dev/null -- checking only "+++ " would misjudge a
# patch that deletes a file under debian/ as upstream, and along with
# it let through a mixed case (deleting a debian/ file + touching an
# upstream file) that should have been caught. /dev/null itself (from
# whichever side is a create or delete) doesn't represent any real
# path and must be skipped, not stripped of its component and treated
# as "dev/null" in the decision.
#
# invalid: a 4th outcome callers must reject, distinct from the debian/
# upstream/mixed classification above -- this function used to fail open,
# silently falling into the upstream branch (and from there getting
# appended to debian/patches/series as if it were a normal patch) for any
# input it could not actually parse. Two cases now report invalid instead:
#   - the file has no "--- "/"+++ " header pair at all (e.g. an empty file,
#     or one that is not a diff at all)
#   - a header's path does not have the a/-, b/- or /dev/null shape this
#     function assumes (e.g. a -p0-style diff whose header is
#     "--- debian/rules" with no a/ prefix at all): blindly stripping "the
#     first path component" from that, as if it were a quilt a/-prefix,
#     strips "debian/" itself and misfiles the patch as upstream instead of
#     debian.
patch_class() {
    local patch="$1"
    local has_debian=0 has_upstream=0 saw_header=0
    local line path comp
    while IFS= read -r line; do
        saw_header=1
        path="${line#[-+][-+][-+] }"
        path="${path%%$'\t'*}"   # some diffs carry a tab + timestamp after the path
        [ "$path" = "/dev/null" ] && continue   # the create/delete side, no real path
        comp="${path%%/*}"       # first path component, validate its shape before stripping
        case "$comp" in
            a|b) ;;
            *)
                echo invalid
                return 0
                ;;
        esac
        path="${path#*/}"        # strip the first path component (a/ or b/)
        case "$path" in
            debian/*) has_debian=1 ;;
            *)        has_upstream=1 ;;
        esac
    done < <(grep -E '^(---|\+\+\+) ' "$patch")

    if [ "$saw_header" -eq 0 ]; then
        echo invalid
    elif [ "$has_debian" -eq 1 ] && [ "$has_upstream" -eq 1 ]; then
        echo mixed
    elif [ "$has_debian" -eq 1 ]; then
        echo debian
    else
        echo upstream
    fi
}
