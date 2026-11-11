"""Before/after for the verify files: main-run rock vs rock-v*, and df main vs df-v* when present.

usage: python3 -I verify_compare.py <tf dir> <image>
"""
import importlib.util
import sys
from collections import Counter
from pathlib import Path

T = Path(sys.argv[1]); image = sys.argv[2]
spec = importlib.util.spec_from_file_location("analyze", T / "analyze.py")
an = importlib.util.module_from_spec(spec); spec.loader.exec_module(an)
files = set((T / "verify-files.txt").read_text().split()) | {"syslog/test_syslog_rate_limit.py"} | set(sum((p.read_text().split() for p in (T / "vshards").glob("verify2-*")), []))


def in_scope(key):
    module = key.split("::")[0][len("tests."):].split(".")
    for n in range(len(module), 0, -1):
        if "/".join(module[:n]) + ".py" in files:
            return True
    return False


before = {k: v for k, v in an.merged(T / "main", image).items() if in_scope(k)}
after = {}
for d in sorted([*(T / "verify").glob(image + "-v*"), *(T / "verify").glob(image + "-w*")]):
    after.update(an.load(d))
print("before:", dict(Counter(v[0] for v in before.values())), "| after:", dict(Counter(v[0] for v in after.values())))
print("teardown before:", dict(Counter(v[1] for v in before.values())), "| after:", dict(Counter(v[1] for v in after.values())))
print("\n== still failing after the fixes")
for k in sorted(after):
    if after[k][0] in ("failed", "setup-error"):
        print("{} {}: {}  (before: {})".format(k, after[k][0], after[k][2][:150], before.get(k, ("absent",))[0]))
print("\n== fixed (failed/setup-error before, passed/skipped after)")
fixed = Counter(k.split("::")[0] for k in after if before.get(k, ("",))[0] in ("failed", "setup-error")
                and after[k][0] in ("passed", "skipped"))
for m, n in sorted(fixed.items()):
    print(n, m)
print("\n== loganalyzer lines beyond noise after the fixes")
for k, v in sorted(after.items()):
    for line in sorted(v[3]):
        print(k, "|", line[:160])
