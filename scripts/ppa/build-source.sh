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
# patch_class()：判断一个补丁改的是 debian/* 还是 debian/* 之外，还是两者
# 都有。test-build-source.sh 也要用同一套判断，抽成公共文件，不抄两份。
source "$REPO/scripts/ppa/patch-class.sh"
# query_pkg(): queries one package's PPA-related facts and loads them into
# the current shell as Q_* variables; manifest.sh and test-build-source.sh
# share this same implementation.
source "$REPO/scripts/ppa/query-pkg.sh"

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
    query_pkg "$PKG" || exit 1

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

    # dpkg-source 的 "3.0 (quilt)" 格式里 debian/patches/* 只应用给上游代码；
    # debian/ 目录本身随 debian.tar 打成最终态。一个补丁如果既在 series 里、
    # 又真的改了 debian/ 下的文件，dpkg-source -b 重建校验树时会把这处改动
    # 当成"应用了两次"而拒绝（"Reversed (or previously applied) patch
    # detected!"）。按 patch_class() 的判断分两队：只改 debian/* 的直接焙进
    # 解包出的树，其余的照常进 series；两者都碰的没法自动决定，报错交给人工拆。
    DEBIAN_PATCHES=()
    UPSTREAM_PATCHES=()
    for p in "${ACTIVE_PATCHES[@]}"; do
        case "$(patch_class "$REPO/$Q_PATCH_DIR/$p")" in
            debian)   DEBIAN_PATCHES+=("$p") ;;
            upstream) UPSTREAM_PATCHES+=("$p") ;;
            mixed)
                echo "$PKG: $p touches both debian/ and non-debian/ paths; dpkg-source's quilt format can't take it either way automatically — split it by hand into a debian/-only patch and an upstream-only patch" >&2
                exit 1
                ;;
        esac
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

    # 有些 stock 包（如 lm-sensors）的 debian/changelog 顶部条目带 dpkg epoch
    # （如 "1:3.6.2-2build1"），即便归档文件名/URL 从不带 epoch。下面
    # dch --newversion 如果漏掉 epoch，新条目会被当成隐式 epoch 0——比官方
    # 归档版本"更旧"，任何已装官方包的机器永远不会 apt upgrade 到我们的 PPA
    # 构建。此处趁 changelog 还是 pristine 状态读出 epoch 并原样带上；顺带
    # 校验 rules/<pkg>.mk 里手写的 <PREFIX>_VERSION_STOCK 是否与 changelog
    # 记的（去掉 epoch 后）一致，防止手写版本号打错字。
    STOCK_CHANGELOG_VERSION=$(dpkg-parsechangelog --show-field Version)
    EPOCH=""
    case "$STOCK_CHANGELOG_VERSION" in
        *:*) EPOCH="${STOCK_CHANGELOG_VERSION%%:*}:" ;;
    esac
    if [ "${STOCK_CHANGELOG_VERSION#*:}" != "$Q_STOCK_VERSION" ]; then
        echo "$PKG: debian/changelog's stock version is '$STOCK_CHANGELOG_VERSION' but rules/$PKG.mk's <PREFIX>_VERSION_STOCK is '$Q_STOCK_VERSION' -- they must agree (ignoring any epoch)" >&2
        exit 1
    fi

    # 只改 debian/* 的补丁直接焙进解包出的树（成为 debian tarball 本体的一部
    # 分），不进 series——它们不是"builder 构建时要应用的上游补丁"。
    for p in "${DEBIAN_PATCHES[@]}"; do
        if ! patch -p1 -N -f -s -F0 < "$REPO/$Q_PATCH_DIR/$p"; then
            echo "$PKG: debian/-only patch $p did not apply cleanly to the extracted tree" >&2
            exit 1
        fi
    done

    # 其余（只改 debian/* 之外）的补丁按同一顺序追加进 series；补丁本身保持
    # 未应用，留给 builder 在构建时应用。
    mkdir -p debian/patches
    [ -f debian/patches/series ] || : > debian/patches/series
    for p in "${UPSTREAM_PATCHES[@]}"; do
        cp "$REPO/$Q_PATCH_DIR/$p" debian/patches/
        echo "$p" >> debian/patches/series
    done

    # 不再需要 rm -rf .pc：--skip-patches 从不应用任何补丁，也就从不创建 .pc。

    dch --newversion "${EPOCH}${Q_STOCK_VERSION}${Q_SUFFIX}" \
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
