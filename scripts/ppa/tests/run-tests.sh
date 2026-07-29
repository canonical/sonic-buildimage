#!/bin/bash
# 跑 PPA 脚手架的全部 make 层单测。必须从仓库根目录运行。
set -euo pipefail

cd "$(dirname "$0")/../../.."

rc=0
for t in scripts/ppa/tests/*_test.mk; do
    echo "== $t"
    make -s -f "$t" || rc=1
done

# 自包含的 shell 测试套件用 *_test.sh 后缀,不带参数就能直接跑,这里一并
# 拉起来跑;跟 test-build-source.sh 这种要传包名的参数化测试(test-* 前缀)
# 是两回事,不能被这个 glob 捡到,所以两者的命名规则故意反过来区分开。
for t in scripts/ppa/tests/*_test.sh; do
    echo "== $t"
    bash "$t" || rc=1
done

if [ "$rc" -ne 0 ]; then
    echo "PPA make-layer tests FAILED"
    exit 1
fi
echo "PPA make-layer tests passed"
