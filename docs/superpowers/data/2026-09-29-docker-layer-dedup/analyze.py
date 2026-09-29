#!/usr/bin/env python3
"""Duplicate-content analysis of a scan_tar.py or scan_fs.py pickle; also writes X.pkl.graph for mtime_report.py. Usage: analyze.py X.pkl"""
import json, pickle, sys, zlib
from collections import defaultdict

d = pickle.load(open(sys.argv[1], "rb"))
files, meta = d["files"], d["meta"]
MB = 1 / 1e6

# --- layer graph: chainid -> cache-id / parent; image -> ordered chainids
L = "image/overlay2/layerdb/sha256/"
chain_cache, chain_parent = {}, {}
for p, v in meta.items():
    if p.startswith(L):
        parts = p[len(L):].split("/")
        if len(parts) != 2:
            continue
        chain, key = parts
        if key == "cache-id":
            chain_cache[chain] = v.decode().strip()
        elif key == "parent":
            chain_parent[chain] = v.decode().strip().split(":")[1]
cache_chain = {c: ch for ch, c in chain_cache.items()}

repos = json.loads(meta["image/overlay2/repositories.json"])["Repositories"]
img_names = defaultdict(set)
for repo, tags in repos.items():
    for tag, iid in tags.items():
        img_names[iid.split(":")[1]].add(repo)

def chain_of(top):
    out = []
    while top:
        out.append(top)
        top = chain_parent.get(top)
    return out[::-1]

import hashlib
images = {}
for iid, names in img_names.items():
    cfg = json.loads(meta[f"image/overlay2/imagedb/content/sha256/{iid}"])
    diffs = [x.split(":")[1] for x in cfg["rootfs"]["diff_ids"]]
    # chainid(n) = sha256(chainid(n-1) + " " + diffid(n))
    chains, prev = [], None
    for di in diffs:
        prev = di if prev is None else hashlib.sha256(f"sha256:{prev} sha256:{di}".encode()).hexdigest()
        chains.append(prev)
    images[iid] = (sorted(names)[0], [chain_cache[c] for c in chains])

# layer -> which images use it
layer_users = defaultdict(list)
for iid, (name, layers) in images.items():
    for i, c in enumerate(layers):
        layer_users[c].append(name)

# friendly layer name: the image for which it is the top layer (else first user + depth)
layer_name = {}
for iid, (name, layers) in sorted(images.items(), key=lambda x: len(x[1][1])):
    for i, c in enumerate(layers):
        layer_name.setdefault(c, f"{name}[L{i}]")
    layer_name[layers[-1]] = f"{name}[L{len(layers)-1}]"

regs = [f for f in files if f[2] == "reg"]
total = sum(f[3] for f in regs)
by_hash = defaultdict(list)
for f in regs:
    by_hash[f[4]].append(f)
unique = sum(v[0][3] for v in by_hash.values())

print(f"images: {len(images)}   layers (overlay2 dirs with diff): {len({f[0] for f in files})}")
print(f"regular files: {len(regs)}   total bytes: {total*MB:.1f} MB   unique-content bytes: {unique*MB:.1f} MB")
print(f"duplicate bytes: {(total-unique)*MB:.1f} MB ({(total-unique)/total*100:.1f}% of layer content)")
print(f"hardlinks in layers: {sum(1 for f in files if f[2]=='hardlink')}   whiteouts: {sum(1 for f in files if f[2]=='whiteout')}")
other = sum(s for p, s in d["other"])
print(f"non-diff metadata files (layerdb/imagedb/tar-split...): {other*MB:.1f} MB")

print("\n== copies histogram (by content hash) ==")
hist = defaultdict(lambda: [0, 0, 0])
for h, v in by_hash.items():
    n = len(v)
    hist[n][0] += 1; hist[n][1] += v[0][3]; hist[n][2] += v[0][3] * (n - 1)
print(f"{'copies':>6} {'distinct files':>14} {'size of one copy MB':>20} {'wasted MB':>10}")
for n in sorted(hist):
    a, b, c = hist[n]
    print(f"{n:>6} {a:>14} {b*MB:>20.1f} {c*MB:>10.1f}")

# classify each extra copy: same path within one image's own chain (rsync re-copy of unchanged content),
# same path in sibling layers, or different path
def ancestors(c):
    for iid, (name, layers) in images.items():
        if c in layers:
            return set(layers[:layers.index(c)])
    return set()
anc = {c: ancestors(c) for c in layer_users}

cls = defaultdict(int)
per_layer_waste = defaultdict(int)
for h, v in by_hash.items():
    if len(v) < 2:
        continue
    v = sorted(v, key=lambda f: len(anc.get(f[0], ())))  # shallowest layer first = "original"
    for f in v[1:]:
        same_path = [g for g in v if g is not f and g[1] == f[1]]
        if any(g[0] in anc.get(f[0], ()) for g in same_path):
            k = "same path, already in an ancestor layer of the same image (re-copied)"
        elif same_path:
            k = "same path, in a sibling/unrelated layer"
        else:
            k = "different path"
        cls[k] += f[3]
        per_layer_waste[f[0]] += f[3]
print("\n== what the extra copies are ==")
for k, b in sorted(cls.items(), key=lambda x: -x[1]):
    print(f"{b*MB:10.1f} MB  {k}")

print("\n== per layer: content / extra copies it carries ==")
lb = defaultdict(int)
for f in regs:
    lb[f[0]] += f[3]
for c in sorted(lb, key=lambda c: -lb[c]):
    print(f"{lb[c]*MB:9.1f} MB  dup {per_layer_waste[c]*MB:7.1f} MB  users={len(layer_users[c]):2d}  {layer_name.get(c, c[:12])}")

print("\n== top duplicated contents by wasted bytes ==")
rows = sorted(by_hash.values(), key=lambda v: -v[0][3] * (len(v) - 1))[:40]
for v in rows:
    paths = sorted({f[1] for f in v})
    print(f"{v[0][3]*(len(v)-1)*MB:8.1f} MB  x{len(v)}  {v[0][3]*MB:6.2f} MB each  {paths[0]}" + (f"  (+{len(paths)-1} other paths)" if len(paths) > 1 else ""))

print("\n== wasted bytes by top-level directory (2 levels) ==")
dd = defaultdict(int)
for h, v in by_hash.items():
    for f in v[1:]:
        dd["/".join(f[1].split("/")[:4])] += f[3]
for k, b in sorted(dd.items(), key=lambda x: -x[1])[:25]:
    print(f"{b*MB:8.1f} MB  {k}")

# hypothetical: every image flattened to a single self-contained layer
def merged(layers):
    view = {}
    for c in layers:
        for f in bylayer[c]:
            name = f[1]
            base = name.rsplit("/", 1)
            if f[2] == "whiteout":
                view.pop(name, None)
                pre = name + "/"
                for k in [k for k in view if k.startswith(pre)]:
                    del view[k]
            elif f[2] == "reg":
                view[name] = f
    return view
bylayer = defaultdict(list)
for f in files:
    bylayer[f[0]].append(f)
flat_total, flat_hashes = 0, {}
for iid, (name, layers) in images.items():
    v = merged(layers)
    flat_total += sum(f[3] for f in v.values())
    for f in v.values():
        flat_hashes[f[4]] = f[3]
print(f"\n== if every image were truly flattened to ONE self-contained layer ==")
print(f"sum of merged image sizes: {flat_total*MB:.1f} MB (vs {total*MB:.1f} MB stored now); unique content still {sum(flat_hashes.values())*MB:.1f} MB")

pickle.dump({"images": images, "layer_name": layer_name, "by_hash": dict(by_hash)}, open(sys.argv[1] + ".graph", "wb"))
