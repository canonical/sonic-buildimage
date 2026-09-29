#!/usr/bin/env python3
"""Re-emit a tar stream with every repeated regular-file content turned into a hardlink to its first copy. Usage: ... | dedup_tar.py | pigz -c | wc -c"""
import hashlib, io, sys, tarfile

src = tarfile.open(fileobj=sys.stdin.buffer, mode="r|")
dst = tarfile.open(fileobj=sys.stdout.buffer, mode="w|", format=tarfile.GNU_FORMAT)
seen, saved = {}, 0
for m in src:
    if m.isreg():
        data = src.extractfile(m).read()
        h = hashlib.sha256(data).hexdigest()
        if h in seen and m.size > 0:
            saved += m.size
            m.type, m.linkname, m.size = tarfile.LNKTYPE, seen[h], 0
            dst.addfile(m)
            continue
        seen.setdefault(h, m.name)
        dst.addfile(m, io.BytesIO(data))
    else:
        dst.addfile(m)
dst.close()
print(f"replaced {saved/1e6:.1f} MB of duplicate content with hardlinks", file=sys.stderr)
