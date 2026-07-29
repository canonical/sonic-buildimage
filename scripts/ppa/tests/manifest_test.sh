#!/bin/bash
# Self-test for manifest.sh: covers a defect found in review -- an
# invalid package name used to let query.mk's non-zero exit code get
# ignored by set -e inside a process substitution, and since declare
# only assigns and never clears, the previous package's Q_* data would
# get reprinted as-is into an unnamed "ghost row", with the whole run
# still exiting 0 (if the invalid package name came first, it instead
# triggered a set -u unbound-variable crash -- a blunter failure, but
# still not the correct behavior of "error on the bad package name and
# keep processing the rest").
#
# Drives manifest.sh with the repo's three real candidate packages
# (isc-dhcp/libteam/lm-sensors) plus a package name guaranteed not to
# exist, without mocking query.mk.
#
# This test is itself self-contained (the *_test.sh suffix, see the
# note in run-tests.sh), unlike test-build-source.sh, which needs a
# package name argument passed in.
set -euo pipefail

cd "$(dirname "$0")/../../.."

# Hermetic against whatever the developer running this actually has in
# rules/config.user: query.mk's `-include $(CONFIG_USER_PATH)` uses a plain
# `=` inside that file, which beats both `?=` defaults and any SONIC_PPA_*
# value we set via the environment below (e.g. a real config.user setting
# SONIC_PPA_PACKAGES would silently change which packages test 5 below sees
# in ppa mode). Point it at /dev/null so this test only ever sees what it
# itself sets.
export CONFIG_USER_PATH=/dev/null

BOGUS="nonexistent-pkg-$$"
fail=0

# Run a command, storing its combined stdout+stderr into the variable
# named by $1 and its exit code into the variable named by $2, without
# letting the inner command's non-zero exit trigger this test script's
# own set -e.
run() {
    local __outvar="$1" __rcvar="$2"; shift 2
    local __out __rc=0
    __out=$("$@" 2>&1) || __rc=$?
    printf -v "$__outvar" '%s' "$__out"
    printf -v "$__rcvar" '%s' "$__rc"
}

expect_eq() {
    local name="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name: want [$want] got [$got]"
        fail=1
    fi
}

expect_nonzero() {
    local name="$1" got="$2"
    if [ "$got" -ne 0 ]; then
        echo "ok   $name (rc=$got)"
    else
        echo "FAIL $name: want non-zero exit, got 0"
        fail=1
    fi
}

expect_contains() {
    local name="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) echo "ok   $name" ;;
        *) echo "FAIL $name: expected output to contain [$needle]"; fail=1 ;;
    esac
}

expect_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    case "$haystack" in
        *"$needle"*) echo "FAIL $name: did not expect output to contain [$needle]"; fail=1 ;;
        *) echo "ok   $name" ;;
    esac
}

# --- 1. No args: should list exactly the three real candidate packages, exit 0 ---
run out rc ./scripts/ppa/manifest.sh
expect_eq "no-args exits 0" "$rc" "0"
# grep -c exits 1 when the count is legitimately zero (e.g. a body-line
# regression that drops every row); guard it the same way as build-source.sh
# and test-build-source.sh do, so that case prints a FAIL instead of killing
# this test script outright under set -e.
body_rc=0
body_lines=$(printf '%s\n' "$out" | tail -n +2 | grep -c .) || body_rc=$?
[ "$body_rc" -le 1 ] || { echo "FAIL no-args: could not count body lines (grep exit $body_rc)"; fail=1; }
expect_eq "no-args: exactly 3 body lines" "$body_lines" "3"
for want in isc-dhcp libteam lm-sensors; do
    row=$(printf '%s\n' "$out" | awk -v w="$want" '$1==w')
    expect_eq "no-args: exactly one row for $want" "$(printf '%s\n' "$out" | awk -v w="$want" '$1==w' | wc -l)" "1"
    [ -n "$row" ] && echo "ok   no-args: $want row present" || { echo "FAIL no-args: $want row present"; fail=1; }
done

# --- 2. Valid package + invalid package, valid first: invalid produces no row, libteam's row isn't duplicated, exit non-zero ---
run out rc ./scripts/ppa/manifest.sh libteam "$BOGUS"
expect_nonzero "valid+invalid (valid first) exits non-zero" "$rc"
expect_eq "valid+invalid (valid first): libteam row appears exactly once" \
    "$(printf '%s\n' "$out" | awk '$1=="libteam"' | wc -l)" "1"
expect_eq "valid+invalid (valid first): no row for the invalid package" \
    "$(printf '%s\n' "$out" | awk -v w="$BOGUS" '$1==w' | wc -l)" "0"
expect_contains "valid+invalid (valid first): error names the bad package" "$out" "$BOGUS"

# --- 3. Invalid package + valid package, invalid first: same as above, and must not be the raw unbound-variable crash ---
run out rc ./scripts/ppa/manifest.sh "$BOGUS" libteam
expect_nonzero "invalid+valid (invalid first) exits non-zero" "$rc"
expect_eq "invalid+valid (invalid first): libteam row appears exactly once" \
    "$(printf '%s\n' "$out" | awk '$1=="libteam"' | wc -l)" "1"
expect_eq "invalid+valid (invalid first): no row for the invalid package" \
    "$(printf '%s\n' "$out" | awk -v w="$BOGUS" '$1==w' | wc -l)" "0"
expect_not_contains "invalid+valid (invalid first): not a raw unbound-variable crash" "$out" "unbound variable"
expect_contains "invalid+valid (invalid first): error names the bad package" "$out" "$BOGUS"

# --- 4. Only an invalid package: exit non-zero, the error names the package, and there is no fabricated data row ---
run out rc ./scripts/ppa/manifest.sh "$BOGUS"
expect_nonzero "invalid alone exits non-zero" "$rc"
expect_contains "invalid alone: error names the package" "$out" "$BOGUS"
# A genuine data row always has "local" or "ppa" as its second column;
# a fabricated row (reprinting the previous successful package's Q_*
# as-is) would have the same shape, whereas query.mk/make's error
# lines would not.
expect_eq "invalid alone: no fabricated data row" \
    "$(printf '%s\n' "$out" | tail -n +2 | awk '$2=="local"||$2=="ppa"' | wc -l)" "0"

# --- 5. SONIC_PPA_PACKAGES=libteam: only libteam's mode becomes ppa ---
run out rc env SONIC_PPA_PACKAGES=libteam ./scripts/ppa/manifest.sh
expect_eq "SONIC_PPA_PACKAGES exits 0" "$rc" "0"
libteam_mode=$(printf '%s\n' "$out" | awk '$1=="libteam"{print $2}')
isc_mode=$(printf '%s\n' "$out" | awk '$1=="isc-dhcp"{print $2}')
lms_mode=$(printf '%s\n' "$out" | awk '$1=="lm-sensors"{print $2}')
expect_eq "SONIC_PPA_PACKAGES: libteam mode is ppa"     "$libteam_mode" "ppa"
expect_eq "SONIC_PPA_PACKAGES: isc-dhcp mode is local"  "$isc_mode"     "local"
expect_eq "SONIC_PPA_PACKAGES: lm-sensors mode is local" "$lms_mode"    "local"

# --- 6. A stray non-k=v line in query.mk's output stream (e.g. a future
# $(warning ...) somewhere in the include chain, or make's own "overriding
# recipe" warning) must not abort manifest.sh under set -e: query-pkg.sh's
# query_pkg() captures query.mk's stdout+stderr together, so that line lands
# in the same stream it parses as KEY=value pairs. Before query_pkg's parser
# skipped non-KEY=value lines instead of handing them straight to `declare`,
# a line like this made `declare -g "Q_<line>="` fail with "not a valid
# identifier" -- uncaught by any `if`/`||`, so under set -e it exited
# manifest.sh's shell from inside query_pkg entirely, not just that one
# package. QUERY_MK_TEST_WARNING is query.mk's own test-only hook for
# injecting exactly this.
WARNING_LINE="Makefile:12: warning: overriding recipe for target"
run out rc env QUERY_MK_TEST_WARNING="$WARNING_LINE" ./scripts/ppa/manifest.sh libteam isc-dhcp lm-sensors
expect_eq "stray warning line: all three packages still resolve, exits 0" "$rc" "0"
for want in isc-dhcp libteam lm-sensors; do
    expect_eq "stray warning line: exactly one row for $want" \
        "$(printf '%s\n' "$out" | awk -v w="$want" '$1==w' | wc -l)" "1"
done
libteam_mode=$(printf '%s\n' "$out" | awk '$1=="libteam"{print $2}')
expect_eq "stray warning line: libteam's row is not corrupted by the injected line" "$libteam_mode" "local"

# Same injection, but paired with a genuinely invalid package: the warning
# must not be what fails the run, and must not swallow the real failure
# either -- exit non-zero only because of the invalid package, same as
# test 2 above without the injected warning.
run out rc env QUERY_MK_TEST_WARNING="$WARNING_LINE" ./scripts/ppa/manifest.sh libteam "$BOGUS"
expect_nonzero "stray warning line + invalid package: exits non-zero (from the invalid package, not the warning)" "$rc"
expect_eq "stray warning line + invalid package: libteam row appears exactly once" \
    "$(printf '%s\n' "$out" | awk '$1=="libteam"' | wc -l)" "1"
expect_contains "stray warning line + invalid package: error still names the bad package" "$out" "$BOGUS"

if [ "$fail" -ne 0 ]; then
    echo "manifest_test: FAILED"
    exit 1
fi
echo "manifest_test: all assertions passed"
