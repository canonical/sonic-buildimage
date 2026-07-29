#!/bin/bash
# manifest.sh 自测：覆盖 review 发现的缺陷——无效包名此前会让 query.mk
# 的非零退出码在 process substitution 里被 set -e 忽略,且 declare 只会
# 赋值不会清空,于是上一个包的 Q_* 数据被原样重印成一行没有名字的"幽灵行",
# 整体仍 exit 0（若无效包名排第一个,则是 set -u 触发 unbound variable
# 崩溃,报错更粗暴但同样不是「按包名报错、继续处理其余包」的正确行为）。
#
# 用真实仓库里的三个候选包(isc-dhcp/libteam/lm-sensors)加一个必然不
# 存在的包名驱动 manifest.sh,不 mock query.mk。
#
# 这份测试本身是自包含的（*_test.sh 后缀，见 run-tests.sh 里的说明），
# 跟 test-build-source.sh 那种要传包名参数的测试不是一回事。
set -euo pipefail

cd "$(dirname "$0")/../../.."

BOGUS="nonexistent-pkg-$$"
fail=0

# 跑一条命令，把合并后的 stdout+stderr 存进 $1 指名的变量、退出码存进
# $2 指名的变量，不让内层命令的非零退出码触发本测试脚本自己的 set -e。
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

# --- 1. 不带参数：应恰好列出三个真实候选包，exit 0 ---
run out rc ./scripts/ppa/manifest.sh
expect_eq "no-args exits 0" "$rc" "0"
body_lines=$(printf '%s\n' "$out" | tail -n +2 | grep -c .)
expect_eq "no-args: exactly 3 body lines" "$body_lines" "3"
for want in isc-dhcp libteam lm-sensors; do
    row=$(printf '%s\n' "$out" | awk -v w="$want" '$1==w')
    expect_eq "no-args: exactly one row for $want" "$(printf '%s\n' "$out" | awk -v w="$want" '$1==w' | wc -l)" "1"
    [ -n "$row" ] && echo "ok   no-args: $want row present" || { echo "FAIL no-args: $want row present"; fail=1; }
done

# --- 2. 有效包 + 无效包，有效包在前：无效包不产生行，libteam 的行不重复，exit 非0 ---
run out rc ./scripts/ppa/manifest.sh libteam "$BOGUS"
expect_nonzero "valid+invalid (valid first) exits non-zero" "$rc"
expect_eq "valid+invalid (valid first): libteam row appears exactly once" \
    "$(printf '%s\n' "$out" | awk '$1=="libteam"' | wc -l)" "1"
expect_eq "valid+invalid (valid first): no row for the invalid package" \
    "$(printf '%s\n' "$out" | awk -v w="$BOGUS" '$1==w' | wc -l)" "0"
expect_contains "valid+invalid (valid first): error names the bad package" "$out" "$BOGUS"

# --- 3. 无效包 + 有效包，无效包在前：同上，且不能是原始的 unbound variable 崩溃 ---
run out rc ./scripts/ppa/manifest.sh "$BOGUS" libteam
expect_nonzero "invalid+valid (invalid first) exits non-zero" "$rc"
expect_eq "invalid+valid (invalid first): libteam row appears exactly once" \
    "$(printf '%s\n' "$out" | awk '$1=="libteam"' | wc -l)" "1"
expect_eq "invalid+valid (invalid first): no row for the invalid package" \
    "$(printf '%s\n' "$out" | awk -v w="$BOGUS" '$1==w' | wc -l)" "0"
expect_not_contains "invalid+valid (invalid first): not a raw unbound-variable crash" "$out" "unbound variable"
expect_contains "invalid+valid (invalid first): error names the bad package" "$out" "$BOGUS"

# --- 4. 只给无效包：exit 非0，报错里点名该包，且没有一行伪造的数据行 ---
run out rc ./scripts/ppa/manifest.sh "$BOGUS"
expect_nonzero "invalid alone exits non-zero" "$rc"
expect_contains "invalid alone: error names the package" "$out" "$BOGUS"
# 一行真正的数据行第二列固定是 "local" 或 "ppa"；伪造行(把上一次成功包
# 的 Q_* 原样重印)会具备同样的形状，而 query.mk/make 的报错行不会。
expect_eq "invalid alone: no fabricated data row" \
    "$(printf '%s\n' "$out" | tail -n +2 | awk '$2=="local"||$2=="ppa"' | wc -l)" "0"

# --- 5. SONIC_PPA_PACKAGES=libteam：只有 libteam 的 mode 变成 ppa ---
run out rc env SONIC_PPA_PACKAGES=libteam ./scripts/ppa/manifest.sh
expect_eq "SONIC_PPA_PACKAGES exits 0" "$rc" "0"
libteam_mode=$(printf '%s\n' "$out" | awk '$1=="libteam"{print $2}')
isc_mode=$(printf '%s\n' "$out" | awk '$1=="isc-dhcp"{print $2}')
lms_mode=$(printf '%s\n' "$out" | awk '$1=="lm-sensors"{print $2}')
expect_eq "SONIC_PPA_PACKAGES: libteam mode is ppa"     "$libteam_mode" "ppa"
expect_eq "SONIC_PPA_PACKAGES: isc-dhcp mode is local"  "$isc_mode"     "local"
expect_eq "SONIC_PPA_PACKAGES: lm-sensors mode is local" "$lms_mode"    "local"

if [ "$fail" -ne 0 ]; then
    echo "manifest_test: FAILED"
    exit 1
fi
echo "manifest_test: all assertions passed"
