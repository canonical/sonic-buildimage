"""Compare two t0 runs case by case, using analyze.py's outcome model.

usage: python3 -I analyze2.py <name A> <dir A> <glob A> <name B> <dir B> <glob B>
e.g.   python3 -I analyze2.py amd64 tf/t0rerun/1112-0845/main 't0-df-*' arm64 arm/results/main 't0-arm-*'
"""
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "2026-11-11-sonic-mgmt-t0-run" / "scripts"))
from analyze import load  # noqa: E402


def merged(root, pattern):
    result = {}
    for shard in sorted(Path(root).glob(pattern)):
        if shard.is_dir():
            result.update(load(shard))
    return result


def main():
    na, da, ga, nb, db, gb = sys.argv[1:7]
    a, b = merged(da, ga), merged(db, gb)
    for name, run in ((na, a), (nb, b)):
        print("{}: {} cases, call {} | teardown {}".format(name, len(run), dict(Counter(v[0] for v in run.values())),
                                                          dict(Counter(v[1] for v in run.values()))))
    print("\n== call outcome differs ({} -> {})".format(na, nb))
    for key in sorted(set(a) | set(b)):
        x, y = a.get(key, ("absent", "", "", set())), b.get(key, ("absent", "", "", set()))
        if x[0] != y[0]:
            print("{}\n    {:6} {}: {}\n    {:6} {}: {}".format(key, na, x[0], x[2], nb, y[0], y[2]))
    print("\n== teardown differs ({} -> {}), ignoring la-noise vs ok".format(na, nb))
    for key in sorted(set(a) & set(b)):
        x, y = a[key][1], b[key][1]
        if {x, y} != {"ok", "la-noise"} and x != y:
            print("{}: {} {} -> {} {}".format(key, na, x, nb, y))
    print("\n== loganalyzer lines beyond known noise")
    for name, run, other in ((na, a, b), (nb, b, a)):
        counts = Counter(re.sub(r"\d+", "N", line)[:200] for v in run.values() for line in v[3])
        theirs = Counter(re.sub(r"\d+", "N", line)[:200] for v in other.values() for line in v[3])
        for line, n in counts.most_common():
            print("{:5} {} {}{}".format(n, name, line, "" if theirs.get(line) else "   [only " + name + "]"))
    print("\n== failures common to both")
    for key in sorted(set(a) & set(b)):
        if a[key][0] in ("failed", "setup-error") and b[key][0] == a[key][0]:
            print("{} {}: {}".format(key, a[key][0], a[key][2]))


if __name__ == "__main__":
    main()
