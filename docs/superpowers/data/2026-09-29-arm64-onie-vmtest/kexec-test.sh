#!/bin/bash
# Drives the ONIE-installed SONiC VM (ssh on 127.0.0.1:3043) through kexec tests.
set -u
S="sshpass -p YourPaSsWoRd ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p 3043 admin@127.0.0.1"
SCP="sshpass -p YourPaSsWoRd scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 3043"
ts() { date -u +%T; }
bootid() { $S cat /proc/sys/kernel/random/boot_id 2>/dev/null; }
wait_new_boot() { old=$1; for i in $(seq 1 180); do sleep 5; b=$(bootid); [ -n "$b" ] && [ "$b" != "$old" ] && { echo "[$(ts)] back up after ~$((i*5))s, boot_id $b"; return 0; }; done; echo "[$(ts)] DID NOT COME BACK"; return 1; }

echo "######## phase 1: load-only matrix ($(ts))"
$SCP ~/vmtest/grubk/kx/boot/vmlinuz-7.0.0-1002-sonic admin@127.0.0.1:/tmp/zboot
$SCP ~/vmtest/grubk/Image admin@127.0.0.1:/tmp/raw
$S 'bash -s' <<'IN'
I=$(ls /host/image-*/boot/initrd.img-*); G=$(ls /host/image-*/boot/vmlinuz-*)
printf 'kernel files: gzip=%s (%s) zboot=%s raw=%s\n' "$G" "$(head -c2 $G | od -An -tx1 | tr -d ' ')" "$(head -c8 /tmp/zboot | tail -c4)" "$(dd if=/tmp/raw bs=1 skip=56 count=4 status=none)"
for k in "gzip:$G" "zboot:/tmp/zboot" "raw:/tmp/raw"; do n=${k%%:*}; f=${k#*:}
  for m in "-a:auto(SONiC fast/warm)" "-s:file_load(SONiC secure)" "-c:kexec_load"; do fl=${m%%:*}
    sudo kexec -u -a >/dev/null 2>&1
    out=$(sudo kexec -l "$f" --initrd="$I" --append="$(cat /proc/cmdline)" $fl 2>&1); rc=$?
    printf '%-6s %-28s rc=%s loaded=%s %s\n' $n "${m#*:}" $rc "$(cat /sys/kernel/kexec_loaded)" "$(echo "$out" | tr '\n' ' ' | cut -c1-110)"
  done; done
sudo kexec -u -a >/dev/null 2>&1
IN

echo "######## phase 2: real kexec jump with the shipped gzip kernel, the way fast-reboot loads it ($(ts))"
B0=$(bootid)
$S 'I=$(ls /host/image-*/boot/initrd.img-*); G=$(ls /host/image-*/boot/vmlinuz-*); sudo kexec -l "$G" --initrd="$I" --append="$(cat /proc/cmdline) SONIC_BOOT_TYPE=kexec-test" -a && echo loaded=$(cat /sys/kernel/kexec_loaded) && sudo sync && (sleep 2; sudo kexec -e) >/dev/null 2>&1 &' ; sleep 5
wait_new_boot "$B0" && $S 'uptime; grep -o "SONIC_BOOT_TYPE=[^ ]*" /proc/cmdline; uname -r; journalctl -b -1 -n 3 --no-pager 2>/dev/null | tail -2 | cut -c1-120'

echo "######## phase 3: kdump ($(ts))"
$S 'sudo config kdump enable 2>&1 | tail -2; sudo config save -y >/dev/null 2>&1; show kdump config 2>&1 | head -8; sudo grep -o "crashkernel=[^ ]*" /host/grub/grub.cfg | head -2'
B1=$(bootid); $S 'sudo sync; (sleep 2; sudo reboot) >/dev/null 2>&1 &'; sleep 5
wait_new_boot "$B1" || exit 1
sleep 90
$S 'grep -o "crashkernel=[^ ]*" /proc/cmdline; cat /sys/kernel/kexec_crash_loaded; sudo kdump-config status 2>&1 | tail -2; sudo kdump-config show 2>&1 | grep -E "kexec command|current state" -A2 | cut -c1-200; ls /var/crash 2>&1'
echo "[$(ts)] triggering a crash"
B2=$(bootid); $S 'sudo sync; (sleep 2; echo c | sudo tee /proc/sysrq-trigger) >/dev/null 2>&1 &'; sleep 5
wait_new_boot "$B2" || exit 1
sleep 60
$S 'ls -la /var/crash/ 2>&1; ls -la /var/crash/*/ 2>&1 | head -12; show reboot-cause 2>&1 | head -3'
echo "######## done ($(ts))"
