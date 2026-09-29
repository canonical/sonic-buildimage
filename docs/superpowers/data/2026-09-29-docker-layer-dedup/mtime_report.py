#!/usr/bin/env python3
"""Shadowed bytes + hardlink-under-mtime simulation. Usage: mtime_report.py X.pkl SDE (run analyze.py X.pkl first)"""
import collections, pickle, sys

d = pickle.load(open(sys.argv[1], "rb"))
g = pickle.load(open(sys.argv[1] + ".graph", "rb"))
SDE = int(sys.argv[2])
files = d["files"]

by = collections.defaultdict(list)
for r in files:
    if r[2] == "reg" and r[3] > 0:
        by[r[4]].append(r)

def saved(key):
    s = 0
    for v in by.values():
        k = collections.Counter(key(r) for r in v)
        s += v[0][3] * sum(c - 1 for c in k.values())
    return s

print(f"hardlink: ignore mtime {saved(lambda r: r[7:10])/1e6:.1f} MB; "
      f"respect mtime {saved(lambda r: r[6:10])/1e6:.1f} MB; "
      f"after clamp {saved(lambda r: (min(r[6], SDE),) + r[7:10])/1e6:.1f} MB")

bylayer = collections.defaultdict(dict)
for f in files:
    bylayer[f[0]][f[1]] = f
bylayer = dict(bylayer)
users = collections.defaultdict(list)
for iid, (n, ls) in g["images"].items():
    for i, c in enumerate(ls):
        users[c].append(ls[i + 1:])
sh, ex = 0, collections.Counter()
for c, ents in bylayer.items():
    for p, f in ents.items():
        if f[2] != "reg" or not users[c]:
            continue
        if all(any(bylayer.get(u, {}).get(p) for u in up) for up in users[c]):
            sh += f[3]
            ex[p] += f[3]
print(f"shadowed: {sh/1e6:.1f} MB", [(p, round(b / 1e6, 2)) for p, b in ex.most_common(4)])
