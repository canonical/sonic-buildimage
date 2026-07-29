#!/bin/bash
# 在一次性 ubuntu:resolute 容器里构建一个已生成的源码包,用来模拟 Launchpad
# builder。验收标准第 1 项。
#
# 刻意不用 slave 镜像:slave 预装了大量 build-dep 并打了 Dh_Lib.pm 补丁,用它
# 就验不出「树外动作丢失」这类问题,也验不出 .ddeb 行为。
# 刻意不用 sbuild/pbuilder:那需要 sudo 往宿主机装东西并建持久 chroot。
#
# 用法: scripts/ppa/build-clean.sh <pkg>
set -euo pipefail

PKG="${1:?usage: $0 <pkg>}"

# This whole script is built around `docker run`; fail immediately with a
# clear message instead of a bare "docker: command not found" once the
# apt-get/dpkg-buildpackage sequence below is already midway through.
command -v docker >/dev/null 2>&1 || { echo "$0: docker is required (this script builds inside a one-shot ubuntu:resolute container) but was not found on PATH" >&2; exit 1; }

cd "$(dirname "$0")/../.."
REPO=$PWD
SRCDIR="$REPO/target/source/$PKG"

ls "$SRCDIR"/*.dsc >/dev/null 2>&1 || { echo "$PKG: no .dsc in $SRCDIR; run build-source.sh first" >&2; exit 1; }

rm -rf "$SRCDIR/build"

# apt-get build-dep ./ 读的是解包后的 debian/control,不需要 deb-src 源,
# 所以 ubuntu:resolute 镜像默认的 sources 就够。
docker run --rm \
    -v "$SRCDIR:/src" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    ubuntu:resolute bash -euc '
        apt-get -qq update
        apt-get -qq install -y --no-install-recommends build-essential devscripts
        mkdir /build && cd /build
        dpkg-source -x /src/*.dsc pkg
        cd pkg
        apt-get -qq build-dep -y --no-install-recommends ./
        dpkg-buildpackage -b -us -uc
        mkdir -p /src/build
        # 每个包的产物组合不同(有的无 dbgsym、有的有 _all.deb),所以两条 glob
        # 各自允许失配;但至少要有一个产物,否则是真失败,不能被 || true 吞掉。
        cp -a /build/*.deb  /src/build/ 2>/dev/null || true
        cp -a /build/*.ddeb /src/build/ 2>/dev/null || true
        # chown 必须在下面的产物数量检查之前:检查失败会 exit 1 提前退出容器,
        # 零产物的情况下 /src/build 仍要归还宿主机用户,否则下一次运行在宿主机
        # 侧 rm -rf 这个目录会因为它 root 属主而权限不够。
        chown -R "$HOST_UID:$HOST_GID" /src/build
        n=$(ls -1 /src/build | wc -l)
        [ "$n" -gt 0 ] || { echo "build produced no .deb/.ddeb artifacts" >&2; exit 1; }
        echo "collected $n artifact(s)"
    '

echo "== $PKG built in a clean ubuntu:resolute container:"
ls -1 "$SRCDIR/build"
