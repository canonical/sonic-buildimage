cd ~/vmtest; mkdir -p sweep; cd sweep
C11=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
C26=$(ls ~/vmtest/fw/u2026.05-2ubuntu2/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd)
MODELS=$(qemu-system-aarch64 -machine virt -cpu help 2>/dev/null | awk 'NR>1{print $1}' | grep -vE '^(host|pxa|sa1|ti925|arm|cortex-m|cortex-r|cortex-a[0-9]$|cortex-a1[0-9]$)' )
echo "models: $MODELS"
one() { fwn=$1; code=$2; m=$3; n=$fwn-$m; cp /usr/share/AAVMF/AAVMF_VARS.fd v-$n.fd; rm -f $n.log
  timeout 240 qemu-system-aarch64 -machine virt,gic-version=3 -accel tcg,thread=multi -cpu $m -smp 2 -m 2048 -net none \
    -drive if=pflash,format=raw,readonly=on,file=$code -drive if=pflash,format=raw,file=v-$n.fd \
    -display none -monitor none -serial file:$n.log >/dev/null 2>$n.err &
  Q=$!; R=TIMEOUT; t=0
  for i in $(seq 1 230); do sleep 1; t=$i
    grep -aq 'Synchronous Exception' $n.log && { R="FAIL($(grep -ao 'Exception at 0x[0-9A-F]*' $n.log | head -1 | cut -d' ' -f3))"; break; }
    grep -aqE 'No bootable option|Boot Manager Menu|Shell>' $n.log && { R=PASS; break; }
    kill -0 $Q 2>/dev/null || { R="EXIT($(head -c 80 $n.err))"; break; }
  done; kill $Q 2>/dev/null; wait $Q 2>/dev/null
  printf '%-10s %-16s %-28s %ss\n' $fwn $m "$R" $t; }
for m in $MODELS; do one fw2511 $C11 $m & one fw2605 $C26 $m & done; wait
