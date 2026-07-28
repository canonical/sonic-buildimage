#!/bin/bash
# 跑 PPA 脚手架的全部 make 层单测。必须从仓库根目录运行。
set -euo pipefail

cd "$(dirname "$0")/../../.."

rc=0
for t in scripts/ppa/tests/*_test.mk; do
    echo "== $t"
    make -s -f "$t" || rc=1
done

if [ "$rc" -ne 0 ]; then
    echo "PPA make-layer tests FAILED"
    exit 1
fi
echo "PPA make-layer tests passed"
