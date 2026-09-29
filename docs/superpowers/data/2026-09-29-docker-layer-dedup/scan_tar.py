#!/usr/bin/env python3
"""Stream a dockerfs tar (overlay2 /var/lib/docker) from stdin and dump per-file records, mtime/mode/owner and .pyc flags. Usage: ... | scan_tar.py X.pkl"""
import hashlib, json, pickle, sys, tarfile

files = []      # (cache_id, relpath, kind, size, sha256, linkname)
meta = {}       # path -> bytes, for small image/ metadata files
other = []      # (path, size) of regular files outside overlay2/*/diff
pyc, pycflags = [], __import__("collections").Counter()

tf = tarfile.open(fileobj=sys.stdin.buffer, mode="r|")
for m in tf:
    p = m.name[2:] if m.name.startswith("./") else m.name
    parts = p.split("/")
    in_diff = len(parts) >= 4 and parts[0] == "overlay2" and parts[2] == "diff"
    if in_diff:
        cid, rel = parts[1], "/" + "/".join(parts[3:])
        if m.isreg():
            h = hashlib.sha256()
            f = tf.extractfile(m)
            first = f.read(16)
            h.update(first)
            if rel.endswith(".pyc") and len(first) >= 8:
                pycflags[int.from_bytes(first[4:8], "little")] += m.size
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                h.update(b)
            files.append((cid, rel, "reg", m.size, h.hexdigest(), None, m.mtime, m.mode, m.uid, m.gid))
            if rel.endswith(".pyc"):
                pyc.append((cid, rel, m.size))
        elif m.islnk():
            files.append((cid, rel, "hardlink", 0, None, m.linkname))
        elif m.issym():
            files.append((cid, rel, "sym", 0, None, m.linkname))
        elif m.ischr() and m.devmajor == 0 and m.devminor == 0:
            files.append((cid, rel, "whiteout", 0, None, None))
        elif m.isdir():
            files.append((cid, rel, "dir", 0, None, None))
        else:
            files.append((cid, rel, "other", m.size, None, None))
    elif m.isreg():
        other.append((p, m.size))
        if p.startswith("image/") and m.size < 4 << 20 and not p.endswith(".gz"):
            meta[p] = tf.extractfile(m).read()

pickle.dump({"files": files, "meta": meta, "other": other, "pycflags": dict(pycflags)}, open(sys.argv[1], "wb"))
print(f"{len(files)} diff entries, {len(other)} other files", file=sys.stderr)
