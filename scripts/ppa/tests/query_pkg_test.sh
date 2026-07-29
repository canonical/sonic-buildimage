#!/bin/bash
# Self-test for scripts/ppa/query-pkg.sh's query_pkg(): a stray non-KEY=value
# line in query.mk's captured output (merged in by query_pkg's own `2>&1`)
# must never abort the calling shell, regardless of how query_pkg is called.
#
# manifest.sh, build-source.sh and test-build-source.sh all call query_pkg
# guarded by `||` (`query_pkg ... || ...`), and bash's `set -e` is suspended
# for every command executed inside a function that sits on the left-hand
# side of `||` -- so driving this defect only through those three scripts
# would not actually exercise it: a `declare -g` failure inside a
# `||`-guarded query_pkg call is silently absorbed by that same suspension,
# not by any robustness in query_pkg itself (confirmed empirically: the old,
# unfixed read loop passes manifest_test.sh's equivalent scenario unchanged,
# specifically because of this). This test instead calls query_pkg as a
# bare, unguarded statement -- the exact shape query_pkg's own header-comment
# contract promises to survive ("query_pkg never calls exit itself... must
# never exit the caller's shell"), and the shape a future caller could
# reasonably write, trusting that contract instead of remembering to add
# `||` every time.
#
# Usage: bash scripts/ppa/tests/query_pkg_test.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."

# Hermetic against a real rules/config.user, same reasoning as
# manifest_test.sh.
export CONFIG_USER_PATH=/dev/null
# query.mk's test-only hook (see query.mk): injects one line into the
# captured make output that is not a KEY=value pair, standing in for a
# future $(warning ...) in the include chain, or an "overriding recipe"
# warning from an older/newer GNU Make.
export QUERY_MK_TEST_WARNING="Makefile:12: warning: overriding recipe for target"

source scripts/ppa/query-pkg.sh

# Deliberately unguarded: no `||`, no `if`. Before the fix, the injected
# stray stderr line reached `declare -g "Q_<line>="` with an invalid
# identifier; unguarded like this, that failure is a plain simple command
# failing under `set -e`, which exits this whole script right there --
# "reached: after query_pkg" below would never print.
query_pkg libteam
echo "reached: after query_pkg call (query_pkg did not abort this shell)"

[ "${Q_PKG:-}" = libteam ] || { echo "FAIL: Q_PKG is '${Q_PKG:-}', want libteam"; exit 1; }
echo "ok   Q_PKG is libteam despite the injected stray line"
[ "${Q_MODE:-}" = local ] || { echo "FAIL: Q_MODE is '${Q_MODE:-}', want local"; exit 1; }
echo "ok   Q_MODE is local despite the injected stray line"

echo "query_pkg_test: all assertions passed"
