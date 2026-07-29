#!/bin/bash
# Run all make-level unit tests for the PPA scaffolding. Must be run
# from the repo root.
set -euo pipefail

cd "$(dirname "$0")/../../.."

rc=0
for t in scripts/ppa/tests/*_test.mk; do
    echo "== $t"
    make -s -f "$t" || rc=1
done

# Self-contained shell test suites use the *_test.sh suffix and can be
# run directly with no arguments; they are picked up and run here too.
# This is distinct from parameterized tests like test-build-source.sh,
# which need a package name (test-* prefix) and must not be caught by
# this glob -- hence the two naming conventions are deliberately
# reversed from each other to keep them apart.
for t in scripts/ppa/tests/*_test.sh; do
    echo "== $t"
    bash "$t" || rc=1
done

if [ "$rc" -ne 0 ]; then
    echo "PPA make-layer tests FAILED"
    exit 1
fi
echo "PPA make-layer tests passed"
