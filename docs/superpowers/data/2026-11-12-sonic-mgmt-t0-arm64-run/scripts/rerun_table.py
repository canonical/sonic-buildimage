"""Per-case outcomes for the rerun files: amd64 baseline, arm64 main run, rerun A (platform alias), rerun B (unchanged).
usage: python3 -I rerun_table.py <arm results dir> <amd64 main dir> <shard dir>"""
import sys, glob
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "2026-11-11-sonic-mgmt-t0-run" / "scripts"))
from analyze import load  # noqa: E402

arm, amd, shards = sys.argv[1:4]
files = sorted({l.strip() for f in glob.glob(shards + "/shard-evalA-*") for l in open(f) if l.strip()})
def merged(root, pattern):
    r = {}
    for d in sorted(Path(root).glob(pattern)):
        r.update(load(d))
    return r
runs = {"amd64": merged(amd, "t0-df-*"), "arm64": merged(arm + "/main", "t0-arm-[0-9]*"),
        "A-alias": merged(arm + "/main", "t0-arm-evalA-*"), "B-plain": merged(arm + "/main", "t0-arm-x*")}
runs["arm64"].update(runs.pop("B-plain"))
runs["B-plain"] = merged(arm + "/main", "t0-arm-evalB-*")
mods = {f[:-3].replace("/", ".") for f in files}
keys = sorted(k for k in set().union(*runs.values()) if any(k.startswith("tests." + m + "::") or k.startswith("tests." + m + ".") for m in mods))
short = {"passed": "pass", "skipped": "skip", "failed": "FAIL", "setup-error": "SETUP", "absent": "-"}
print("{:96} {:6} {:6} {:7} {:7}".format("case", "amd64", "arm64", "A-alias", "B-plain"))
for k in keys:
    o = [runs[n].get(k, ("absent", "", "", set())) for n in ("amd64", "arm64", "A-alias", "B-plain")]
    calls = [short.get(x[0], x[0]) for x in o]
    tds = ["" if x[1] in ("ok", "la-noise", "") else "+" + x[1] for x in o]
    if len(set(calls)) == 1 and not any(tds):
        continue
    print("{:96} {:6} {:6} {:7} {:7}".format(k[6:102], *[c + t[:3] for c, t in zip(calls, tds)]))
    for n, x in zip(("amd64", "arm64", "A-alias", "B-plain"), o):
        if x[0] in ("failed", "setup-error") or x[1] in ("la", "teardown-error"):
            print("      {:8} {}".format(n, (x[2] or ";".join(sorted(x[3]))[:150])[:150]))
