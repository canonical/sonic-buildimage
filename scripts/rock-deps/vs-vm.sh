#!/bin/bash
# Start/stop the local sonic-vs VM from the CI image, and print ssh/scp prefixes for collect.sh / run-paths.sh.
# Usage: vs-vm.sh start|stop|status|ssh <cmd...>|ssh-prefix|scp-prefix
#        env: ROCKDEPS_VS_ZIP (default ~/Downloads/sonic-vs-img.zip), ROCKDEPS_WORK (default ~/.cache/rockdeps/vs)
# Needs: qemu-system-x86_64, /dev/kvm access (no sudo), unzip, gunzip, sshpass. Same VM settings as CI test-vs.
set -euo pipefail

zip=${ROCKDEPS_VS_ZIP:-$HOME/Downloads/sonic-vs-img.zip}
work=${ROCKDEPS_WORK:-$HOME/.cache/rockdeps/vs}
img=$work/sonic-vs.img pid=$work/qemu.pid cfg=$work/ssh_config
pass=YourPaSsWoRd   # default SONiC VS admin password, not a secret
mkdir -p "$work"
cat > "$cfg" <<EOF
Host sonic-vs
  HostName 127.0.0.1
  Port 2200
  User admin
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  ConnectTimeout 15
  ServerAliveInterval 30
EOF

running() { [ -f "$pid" ] && kill -0 "$(cat "$pid")" 2>/dev/null; }
vssh() { sshpass -p "$pass" ssh -F "$cfg" sonic-vs "$@"; }

case ${1:-} in
start)
    if ! running; then
        [ -f "$img" ] || unzip -p "$zip" sonic-vs.img.gz | gunzip > "$img"
        qemu-system-x86_64 -enable-kvm -cpu host -m 8192 -smp 4 -boot order=c -name sonic \
            -drive file="$img",media=disk,if=virtio \
            -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2200-:22 -device virtio-net-pci,netdev=net0 \
            -display none -daemonize -pidfile "$pid" -serial file:"$work/serial.log"
    fi
    for _ in $(seq 120); do vssh true </dev/null 2>/dev/null && { echo "sonic-vs up"; exit 0; }; sleep 10; done
    echo "sonic-vs not reachable after 20 min; see $work/serial.log" >&2; exit 1 ;;
stop)
    if running; then kill "$(cat "$pid")"; fi
    rm -f "$pid" ;;
status) running && echo running || echo stopped ;;
ssh) shift; vssh "$@" ;;
ssh-prefix) echo "sshpass -p $pass ssh -F $cfg sonic-vs" ;;
scp-prefix) echo "sshpass -p $pass scp -q -F $cfg" ;;
*) echo "usage: $0 start|stop|status|ssh <cmd>|ssh-prefix|scp-prefix" >&2; exit 2 ;;
esac
