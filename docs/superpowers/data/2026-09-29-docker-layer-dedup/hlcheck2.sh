#!/bin/bash
# Follow-up: remove images of disabled features (their layers share inodes with running images) and verify nothing else changed.
OUT=/host/hlcheck2.txt
exec > $OUT 2>&1
sec() { echo; echo "### $1"; }
sleep 240

snap() {
    python3 - "$1" <<'EOF'
import glob, hashlib, os, pickle, stat, sys
out = {}
for d in glob.glob('/var/lib/docker/overlay2/*/diff'):
    for dp, dns, fns in os.walk(d):
        for n in fns:
            p = os.path.join(dp, n); st = os.lstat(p)
            if stat.S_ISREG(st.st_mode):
                with open(p, 'rb') as f:
                    out[p] = (hashlib.sha256(f.read()).hexdigest(), st.st_ino, st.st_nlink)
pickle.dump(out, open(sys.argv[1], 'wb'))
EOF
}

sec "running containers before"; docker ps --format '{{.Names}}' | sort | tr '\n' ' '; echo
snap /tmp/before.pkl
imgs="docker-dhcp-relay docker-macsec docker-nat docker-sflow docker-mux docker-sonic-otel"
sec "rmi $imgs"
for i in $imgs; do docker rmi $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "^$i:") 2>&1 | grep -c Deleted | sed "s/^/$i deleted-layers: /"; done
snap /tmp/after.pkl

sec "remaining layer files vs before"
python3 - <<'EOF'
import pickle
b = pickle.load(open('/tmp/before.pkl', 'rb')); a = pickle.load(open('/tmp/after.pkl', 'rb'))
removed = set(b) - set(a)
shared_removed = [p for p in removed if b[p][2] > 1]
changed = [p for p in a if a[p][0] != b[p][0]]
new = set(a) - set(b)
survivors = {b[p][1] for p in shared_removed}
kept_with_same_inode = [p for p in a if a[p][1] in survivors]
print(f"files before {len(b)} after {len(a)} removed {len(removed)} (of which hardlinked {len(shared_removed)})")
print(f"remaining files whose content changed: {len(changed)}; new files: {len(new)}")
print(f"remaining files that shared an inode with a removed file: {len(kept_with_same_inode)}, all intact: {all(a[p][0] == b[p][0] for p in kept_with_same_inode)}")
EOF

sec "config reload after rmi"
config reload -y >/dev/null 2>&1; echo "reload rc=$?"; sleep 200
docker ps --format '{{.Names}}' | sort | tr '\n' ' '; echo
redis-cli -n 1 keys 'ASIC_STATE:SAI_OBJECT_TYPE_PORT:*' | wc -l
redis-cli -n 1 keys 'ASIC_STATE:SAI_OBJECT_TYPE_ROUTE_ENTRY:*' | wc -l
show ip bgp summary | tail -1
systemctl list-units --failed --no-legend --plain | grep -v hlcheck
sec "DONE"
sync
systemctl poweroff
