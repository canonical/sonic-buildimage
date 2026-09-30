#!/bin/bash
set -u
S="sshpass -p YourPaSsWoRd ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -p 3043 admin@127.0.0.1"
ts() { date -u +%T; }
bootid() { timeout 20 $S cat /proc/sys/kernel/random/boot_id 2>/dev/null; }
detach() { timeout 20 $S "sudo setsid sh -c 'sleep 3; $1' </dev/null >/dev/null 2>&1 &"; }
wait_new_boot() { old=$1; for i in $(seq 1 240); do sleep 5; b=$(bootid); [ -n "$b" ] && [ "$b" != "$old" ] && { echo "[$(ts)] back up after ~$((i*5))s, boot_id $b"; return 0; }; done; echo "[$(ts)] DID NOT COME BACK"; return 1; }
echo "######## phase 3: kdump ($(ts))"
timeout 120 $S 'sudo config kdump enable 2>&1 | tail -3; sudo config save -y >/dev/null 2>&1; show kdump config 2>&1 | head -8; sudo grep -o "crashkernel=[^ ]*" /host/grub/grub.cfg | head -2'
B1=$(bootid); detach "reboot"; wait_new_boot "$B1" || exit 1
sleep 120
timeout 120 $S 'grep -o "crashkernel=[^ ]*" /proc/cmdline; echo kexec_crash_loaded=$(cat /sys/kernel/kexec_crash_loaded); sudo kdump-config status 2>&1 | tail -2; sudo kdump-config show 2>&1 | grep -A3 -E "kexec command" | cut -c1-240; show kdump config 2>&1 | head -4'
echo "[$(ts)] triggering a crash via sysrq"
B2=$(bootid); timeout 20 $S "sudo sh -c 'echo 1 > /proc/sys/kernel/sysrq'"; detach "echo c > /proc/sysrq-trigger"; wait_new_boot "$B2" || exit 1
sleep 90
timeout 120 $S 'ls -la /var/crash/ 2>&1; for d in /var/crash/2*; do echo "== $d"; ls -la $d; done 2>&1 | head -20; show reboot-cause 2>&1 | head -3; sudo journalctl -b -1 -n 5 --no-pager 2>&1 | cut -c1-140'
echo "######## done ($(ts))"
