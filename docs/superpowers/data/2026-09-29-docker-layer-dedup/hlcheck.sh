#!/bin/bash
# One-shot in-guest health check: wait for the container set to settle, run checks, write /host/hlcheck.txt, power off.
OUT=/host/hlcheck.txt
F=/usr/share/misc/pci.ids
t0=$(date +%s)
sec() { echo; echo "### $1"; }
exec > $OUT 2>&1

last=""; stable=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 1500 ]; do
    cur=$(docker ps --format '{{.Names}}' | sort | tr '\n' ' ')
    if [ "$cur" != "$last" ]; then last=$cur; stable=$(date +%s)
    elif [ $(( $(date +%s) - stable )) -gt 180 ]; then break; fi
    sleep 15
done

sec "settled after (s) / uptime";   echo $(( $(date +%s) - t0 )); uptime
sec "image version";                sonic-cfggen -y /etc/sonic/sonic_version.yml -v build_version
sec "running containers";           docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | sort | sed -E 's/Up [^\t]*/Up/'
sec "feature state";                show feature status
sec "failed units";                 systemctl list-units --failed --no-legend --plain | grep -v hlcheck
sec "ports / routes in ASIC_DB";    redis-cli -n 1 keys 'ASIC_STATE:SAI_OBJECT_TYPE_PORT:*' | wc -l; redis-cli -n 1 keys 'ASIC_STATE:SAI_OBJECT_TYPE_ROUTE_ENTRY:*' | wc -l
sec "PORT_TABLE / PortInitDone";    redis-cli -n 0 keys 'PORT_TABLE:Ethernet*' | wc -l; redis-cli -n 0 hgetall PORT_TABLE:PortInitDone
sec "interfaces (head)";            show interfaces status | head -5
sec "bgp summary (tail)";           show ip bgp summary | tail -4
sec "hardlinked files in layers";   find /var/lib/docker/overlay2 -type f -links +1 | wc -l
sec "docker du (MB)";               du -s --block-size=1M /var/lib/docker | cut -f1

sec "copy-up: shared pci.ids before"
for c in swss bgp lldp pmon snmp; do echo "$c $(docker exec $c md5sum $F | cut -c1-12)"; done
stat -c '%i %h' /var/lib/docker/overlay2/*/diff$F | sort | uniq -c
sec "copy-up: append in swss only"
docker exec swss sh -c "echo MUTATED >> $F"
for c in swss bgp lldp pmon snmp; do echo "$c $(docker exec $c tail -c 8 $F | tr -d '\n')"; done
for x in /var/lib/docker/overlay2/*/diff$F; do tail -c 8 $x | tr -d '\n'; echo; done | sort | uniq -c

sec "docker save integrity"
for i in docker-orchagent docker-syncd-vs docker-fpm-frr; do
    rm -rf /tmp/s && mkdir /tmp/s && docker save $i:latest | tar x -C /tmp/s
    python3 - $i <<'EOF'
import hashlib, json, sys
m = json.load(open('/tmp/s/manifest.json'))[0]
c = json.load(open('/tmp/s/' + m['Config']))
d = ['sha256:' + hashlib.sha256(open('/tmp/s/' + l, 'rb').read()).hexdigest() for l in m['Layers']]
print(sys.argv[1], 'layers', len(d), 'match' if d == c['rootfs']['diff_ids'] else 'MISMATCH')
EOF
done
rm -rf /tmp/s

sec "rmi docker-gbsyncd-vs (shares inodes with syncd-vs)"
docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep gbsyncd-vs) | tail -1
docker exec syncd md5sum /usr/lib/x86_64-linux-gnu/libLLVM.so.21.1 /usr/bin/syncd | cut -c1-12

sec "restart swss (also restarts syncd)"
systemctl restart swss; sleep 150
docker ps --format '{{.Names}}' | sort | tr '\n' ' '; echo
redis-cli -n 1 keys 'ASIC_STATE:SAI_OBJECT_TYPE_PORT:*' | wc -l

sec "config reload"
config reload -y >/dev/null 2>&1; echo "reload rc=$?"; sleep 200
docker ps --format '{{.Names}}' | sort | tr '\n' ' '; echo
redis-cli -n 1 keys 'ASIC_STATE:SAI_OBJECT_TYPE_PORT:*' | wc -l
systemctl list-units --failed --no-legend --plain | grep -v hlcheck

sec "syslog ERR lines (normalised)"
grep ' ERR ' /var/log/syslog | sed -E 's/^.{0,40}(sonic|vlab-01) //; s/\[[0-9]+\]//g; s/[0-9a-f]{12,}/<id>/g' | sort | uniq -c | sort -rn | head -40

sec "DONE"
sync
systemctl poweroff
