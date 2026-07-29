#!/bin/bash
# 为一个或多个包产出未签名的 Debian 源码包，供上传到 Launchpad PPA。
#
# 在 slave-resolute 容器内运行（需要 dget / dch / dpkg-source，容器已含
# devscripts）。刻意不签名、不上传：GPG 与 dput 由宿主机上的
# scripts/ppa/sign-upload.sh 负责。
#
# 用法: scripts/ppa/build-source.sh <pkg>...
#   例: scripts/ppa/build-source.sh libteam isc-dhcp lm-sensors
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <pkg>..." >&2; exit 2; }
cd "$(dirname "$0")/../.."
REPO=$PWD

# 每个包一个 $WORK；set -e 下任何一个包中途失败都会让脚本立即退出，跳过
# 该包循环体末尾原本的清理。用一个数组记录所有已创建的 $WORK，EXIT trap
# 统一清理——只清最后一个是不够的，前面已成功的包的 $WORK 目录不会自己消失。
WORK_DIRS=()
cleanup_work_dirs() {
    local d
    for d in "${WORK_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup_work_dirs EXIT

for PKG in "$@"; do
    echo "=== $PKG"
    # 用 read 而非 eval：DERIVED_DEBS 的值含空格，eval 会把它按词拆开去执行
while IFS='=' read -r k v; do declare "Q_$k=$v"; done \
    < <(make -s -f scripts/ppa/query.mk PKG="$PKG")

    [ -n "${Q_DSC_URL:-}" ] || { echo "$PKG: <PREFIX>_DSC_URL is not set in rules/$PKG.mk" >&2; exit 1; }
    [ -n "${Q_STOCK_VERSION:-}" ] || { echo "$PKG: <PREFIX>_VERSION_STOCK is not set in rules/$PKG.mk" >&2; exit 1; }

    # 只看 series 里当前生效的补丁：一个被注释掉、从不会被应用的补丁文件如果
    # 恰好含二进制 diff，不该拖累这次构建；后面追加补丁的循环也复用这份列表，
    # 不必对 series 再 grep 一遍。
    mapfile -t ACTIVE_PATCHES < <(grep -vE '^\s*(#|$)' "$REPO/$Q_PATCH_DIR/series")
    for p in "${ACTIVE_PATCHES[@]}"; do
        # 补丁里含二进制文件需要 debian/source/include-binaries；本批次没有，
        # 但要显式报错而不是静默产出一个 dpkg-source 会拒绝的包。
        if grep -q $'^GIT binary patch' "$REPO/$Q_PATCH_DIR/$p" 2>/dev/null; then
            echo "$PKG: $p contains a binary diff; needs debian/source/include-binaries" >&2
            exit 1
        fi
    done

    WORK=$(mktemp -d)
    WORK_DIRS+=("$WORK")
    OUT="$REPO/target/source/$PKG"
    mkdir -p "$OUT"

    pushd "$WORK" >/dev/null
    # -u 是结构性必需：Ubuntu slave 上 .dsc 上传者的个人 key 不在任何可用
    # keyring 里，装 debian-keyring 也验不了。
    #
    # -d：只下载，不解包。普通 `dget -u` 会自动 `dpkg-source -x`，把上游
    # debian/patches 全部应用到工作树，只留 .pc 记录「上游那些补丁已应用」。
    # 我们随后把 SONiC 的补丁名追加进同一个 series，但补丁内容本身不应用
    # （留给 builder 在构建时应用）——这样一来 series 里一部分（上游的）已
    # 应用、另一部分（SONiC 的）未应用，工作树和 series 互相对不上。带 10
    # 个上游补丁的包（如 isc-dhcp）在这种状态下 `dpkg-source -b` 会报
    # "aborting due to unexpected upstream changes"：它按完整 series 重新
    # 展开一份参照树，与当前工作树一比，SONiC 补丁改到的文件全部不一致。
    dget -d -u "$Q_DSC_URL"

    DSC=$(find . -maxdepth 1 -type f -name '*.dsc' | head -1)
    [ -n "$DSC" ] || { echo "$PKG: dget -d did not leave a .dsc in $WORK" >&2; exit 1; }
    # --skip-patches：解包但一个补丁都不应用（连上游的都不应用），工作树
    # 保持 pristine。series 因此从头到尾都是「未应用」，与我们后面追加
    # SONiC 补丁名的做法一致，不会出现上面那种半应用状态。
    dpkg-source --skip-patches -x "$DSC"

    SRCDIR=$(find . -maxdepth 1 -type d -name "$Q_SOURCE-*" | head -1)
    [ -n "$SRCDIR" ] || { echo "$PKG: cannot find extracted source dir for $Q_SOURCE" >&2; exit 1; }
    pushd "$SRCDIR" >/dev/null

    # 把 SONiC 补丁按同一顺序追加进 series；补丁本身保持未应用。
    mkdir -p debian/patches
    [ -f debian/patches/series ] || : > debian/patches/series
    for p in "${ACTIVE_PATCHES[@]}"; do
        cp "$REPO/$Q_PATCH_DIR/$p" debian/patches/
        echo "$p" >> debian/patches/series
    done

    # 不再需要 rm -rf .pc：--skip-patches 从不应用任何补丁，也就从不创建 .pc。

    dch --newversion "${Q_STOCK_VERSION}${Q_SUFFIX}" \
        --distribution resolute --force-distribution \
        "SONiC packaging for Ubuntu resolute: apply the $PKG patch series from sonic-buildimage."

    # 该 upstream 版本首次上传要带 orig（-sa）；后续必须 -sd，否则 Launchpad
    # 会因 orig 校验和冲突 reject。以 PPA pool 里是否已有该 orig 为准；
    # 无法判定时保守用 -sa —— 多余重传一次 orig 通常无害，但首次上传缺 orig
    # 会被 Launchpad 直接拒绝，两害相权取其轻。
    # pool URL 由 query.mk 给出(见 Q_PPA_POOL_URL),不在这里用 sed 重推一遍
    # ppa_pool_dir 的逻辑 —— 那会让同一规则存在两份实现。
    SA_FLAG=-sd
    if [ -n "${Q_PPA_POOL_URL:-}" ]; then
        # -F on the $Q_SOURCE half: it is interpolated from rules/*.mk, and
        # BRE metacharacters in it (e.g. a literal '.') would otherwise be
        # read as regex syntax instead of matched literally.
        if ! curl -sfL "$Q_PPA_POOL_URL/" | grep -F -- "${Q_SOURCE}_" | grep -q '\.orig\.'; then
            SA_FLAG=-sa
        fi
    else
        echo "  note: SONIC_PPA_URL unset, cannot tell if the orig is already uploaded; using -sa for the first local run" >&2
        SA_FLAG=-sa
    fi

    dpkg-buildpackage -S "$SA_FLAG" -us -uc -d
    popd >/dev/null

    # $WORK also still holds dget's original stock download (same basenames
    # minus our suffix): a blanket */*.dsc glob would carry that stock .dsc
    # into $OUT too, and a consumer that expects exactly one .dsc there (e.g.
    # build-clean.sh) would break. Scope the move to the version we just built.
    #
    # The orig tarball is collected independently of $SA_FLAG: -sd only tells
    # dpkg-buildpackage not to *reference* the orig in *.changes, it does not
    # delete the physical .orig.tar.* that dget already placed in $WORK. So the
    # orig must always be picked up when present, or build-clean.sh's
    # `dpkg-source -x` (which needs the orig alongside the .dsc) breaks on
    # every -sd run — i.e. every build after a package's first upload.
    # Only clear the regular files directly in $OUT, not the directory itself:
    # build-clean.sh creates $OUT/build/ in this same tree, and a bare `rm -f
    # "$OUT"/*` fails under set -e as soon as that subdirectory exists ("Is a
    # directory"), aborting before any new .dsc/.changes/orig is moved in. A
    # previous clean-container result is worth keeping until deliberately
    # replaced, so this deletes files only and leaves build/ (or any other
    # subdirectory) untouched; it is not `rm -rf "$OUT"`.
    find "$OUT" -maxdepth 1 -type f -delete
    mv ./"${Q_SOURCE}_${Q_STOCK_VERSION}${Q_SUFFIX}"* "$OUT"/
    # Single-component orig only (<src>_<ver>.orig.tar.*): a multi-component
    # orig would be named <src>_<ver>.orig-<component>.tar.*, which this glob
    # does not match. No package wired up here needs one; add matching support
    # if/when one does.
    shopt -s nullglob
    orig=(./*.orig.tar.*)
    shopt -u nullglob
    [ "${#orig[@]}" -eq 0 ] || mv "${orig[@]}" "$OUT"/
    popd >/dev/null

    echo "  -> $OUT"
    ls -1 "$OUT"
done
