#!/bin/bash
# Apply upstream's build-optimize-fs-size.py (what BUILD_REDUCE_IMAGE_SIZE=y runs) to the dockerfs of a .bin and report sizes and metadata changes.
# Usage: upstream-opt.sh IN.bin SCRIPT (path to scripts/build-optimize-fs-size.py)
set -euo pipefail
IN=$(realpath "$1"); OPT=$(realpath "$2")
W=$(mktemp -d -p "$(dirname "$IN")" upopt.XXXXXX)
trap 'sudo rm -rf "$W"' EXIT
cd "$W"
MB() { echo "scale=1; $1 / 1000000" | bc; }

sed -e '1,/^exit_marker$/d' "$IN" | tar xf - installer/fs.zip
mkdir -p root/var/lib/docker
unzip -p installer/fs.zip dockerfs.tar.gz | sudo tar xz --numeric-owner -C root/var/lib/docker
rm -rf installer

snap() {
    sudo python3 - "$W/root/var/lib/docker/overlay2" "$1" <<'EOF'
import glob, os, pickle, stat, sys
out = {}
for d in glob.glob(sys.argv[1] + '/*/diff'):
    for dp, dns, fns in os.walk(d):
        for n in fns:
            p = os.path.join(dp, n); st = os.lstat(p)
            if stat.S_ISREG(st.st_mode):
                out[p] = (st.st_mode, st.st_uid, st.st_gid, int(st.st_mtime), st.st_ino)
pickle.dump(out, open(sys.argv[2], 'wb'))
EOF
}
sizes() {
    local du gz zs
    du=$(sudo du -s --block-size=1M root/var/lib/docker | cut -f1)
    gz=$(sudo tar -I pigz -cf - -C root/var/lib/docker . | wc -c)
    zs=$(sudo tar -I pzstd -cf - -C root/var/lib/docker . | wc -c)
    echo "$1: docker dir $du MB | pigz tar $(MB "$gz") MB | pzstd tar $(MB "$zs") MB"
}
diffmeta() {
    sudo python3 - "$W/before.pkl" "$W/after.pkl" "$1" <<'EOF'
import pickle, sys, collections
b = pickle.load(open(sys.argv[1], 'rb')); a = pickle.load(open(sys.argv[2], 'rb'))
kept = [p for p in b if p in a]
mode = [p for p in kept if b[p][0] != a[p][0]]
own = [p for p in kept if b[p][1:3] != a[p][1:3]]
mt = [p for p in kept if b[p][3] != a[p][3]]
lost = [p for p in kept if b[p][0] & 0o6000 and not a[p][0] & 0o6000]
gained = [p for p in kept if a[p][0] & 0o6000 and not b[p][0] & 0o6000]
xbit = [p for p in kept if (b[p][0] ^ a[p][0]) & 0o111]
print(f"{sys.argv[3]}: layer files {len(b)} -> {len(a)}; mode changed {len(mode)} (exec bits {len(xbit)}), owner changed {len(own)}, mtime changed {len(mt)}")
print(f"  setuid/setgid lost {len(lost)}, gained {len(gained)}")
names = collections.Counter(p.rsplit('/', 1)[1] for p in lost)
print("  lost by name:", sorted(names.items()))
for p in xbit[:5]: print(f"  exec-bit change: {p.split('/diff', 1)[1]} {oct(b[p][0] & 0o7777)} -> {oct(a[p][0] & 0o7777)}")
EOF
}

sizes "original"
snap before.pkl
sudo python3 "$OPT" "$W/root" --hardlinks var/lib/docker > opt-a.log
snap after.pkl
sizes "A: upstream hardlinks only"
diffmeta "A"
sudo python3 "$OPT" "$W/root" --hardlinks var/lib/docker --remove-docs --remove-mans --remove-licenses > opt-b.log
snap after.pkl
sizes "B: + remove docs/mans/licenses"
diffmeta "B"
