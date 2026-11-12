#!/bin/bash
# On papat: native arm64 Dockerfile-mode vs build of 7a081af43c + the 9 arm64 commits (local rebase of PR #18)
set -eux
export PATH=$HOME/.local/bin:$PATH
B=~/sbi
if [ ! -d $B ]; then
    git clone -q --branch 202605_resolute https://github.com/canonical/sonic-buildimage.git $B
    git -C $B fetch -q /srv/share/arm64-t0.bundle test/arm64-vs-on-7a081af43c:test/arm64-vs-on-7a081af43c
    git -C $B switch -q test/arm64-vs-on-7a081af43c
    git -C $B submodule update -q --init --recursive --jobs 16
fi
git -C $B log --oneline -1
cp /srv/share/config.user $B/rules/config.user
cd $B
export SONIC_BUILD_JOBS=${SONIC_BUILD_JOBS:-16} SONIC_BUILD_RETRY_COUNT=3
echo "configure start $(date -Is)"
rm -f .arch .platform
make configure PLATFORM=vs PLATFORM_ARCH=arm64 > ~/build-configure.log 2>&1; echo "configure rc=$? $(date -Is)"
grep -E '"CONFIGURED_(ARCH|PLATFORM)"' ~/build-configure.log
make target/sonic-vs.bin > ~/build-bin.log 2>&1; echo "build rc=$? $(date -Is)"
ls -la target/sonic-vs.bin
