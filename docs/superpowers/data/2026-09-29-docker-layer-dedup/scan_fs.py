#!/usr/bin/env python3
"""Walk an on-disk overlay2 /var/lib/docker and dump records in scan_tar.py's format. Usage: scan_fs.py DOCKER_DIR X.pkl"""
import hashlib, os, pickle, stat, sys
from collections import Counter

root, out = sys.argv[1], sys.argv[2]
files, meta, other = [], {}, []
pycflags, seen = Counter(), set()

ov = os.path.join(root, "overlay2")
for cid in os.listdir(ov):
    diff = os.path.join(ov, cid, "diff")
    if not os.path.isdir(diff):
        continue
    for dp, dns, fns in os.walk(diff):
        for n in dns + fns:
            p = os.path.join(dp, n)
            rel = "/" + os.path.relpath(p, diff)
            st = os.lstat(p)
            if stat.S_ISREG(st.st_mode):
                key = (st.st_dev, st.st_ino)
                if key in seen:
                    files.append((cid, rel, "hardlink", 0, None, None, st.st_mtime, st.st_mode, st.st_uid, st.st_gid))
                    continue
                seen.add(key)
                h = hashlib.sha256()
                with open(p, "rb") as f:
                    first = f.read(16)
                    h.update(first)
                    if rel.endswith(".pyc") and len(first) >= 8:
                        pycflags[int.from_bytes(first[4:8], "little")] += st.st_size
                    for b in iter(lambda: f.read(1 << 20), b""):
                        h.update(b)
                files.append((cid, rel, "reg", st.st_size, h.hexdigest(), None, int(st.st_mtime), st.st_mode, st.st_uid, st.st_gid))
            elif stat.S_ISLNK(st.st_mode):
                files.append((cid, rel, "sym", 0, None, os.readlink(p)))
            elif stat.S_ISCHR(st.st_mode) and st.st_rdev == 0:
                files.append((cid, rel, "whiteout", 0, None, None))
            elif stat.S_ISDIR(st.st_mode):
                files.append((cid, rel, "dir", 0, None, None))
            else:
                files.append((cid, rel, "other", st.st_size, None, None))

for dp, dns, fns in os.walk(root):
    if dp.startswith(ov):
        continue
    for n in fns:
        p = os.path.join(dp, n)
        if not os.path.isfile(p) or os.path.islink(p):
            continue
        rel = os.path.relpath(p, root)
        sz = os.path.getsize(p)
        other.append((rel, sz))
        if rel.startswith("image/") and sz < 4 << 20 and not rel.endswith(".gz"):
            meta[rel] = open(p, "rb").read()

pickle.dump({"files": files, "meta": meta, "other": other, "pycflags": dict(pycflags)}, open(out, "wb"))
print(f"{len(files)} diff entries, {len(other)} other files, pyc={dict(pycflags)}", file=sys.stderr)
