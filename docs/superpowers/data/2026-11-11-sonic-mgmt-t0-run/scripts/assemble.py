"""Build main/<label> and verify/<label> symlink trees from raw/tbN/logs/<label>, dropping stolen placeholders.

usage: python3 -I assemble.py <tf dir>
"""
import json
import re
import shutil
import sys
from pathlib import Path

T = Path(sys.argv[1])
state = json.loads((T / "raw" / "state.json").read_text())
# handoffs recorded by the balancer, plus the manual rerun of rock-x4 that pretest had aborted
stolen = {}
for h in state.get("handoffs", []):
    stolen.setdefault(h["from_label"], set()).update(h["files"])
stolen.setdefault("rock-3", set()).add("platform_tests/test_link_down.py")  # collection error, rerun in rock-x4b
dropped_labels = {"rock-x4"}  # pretest aborted, files rerun in rock-x4b

for kind in ("main", "verify"):
    shutil.rmtree(T / kind, ignore_errors=True)
    (T / kind).mkdir()
dropped = 0
for vm in sorted((T / "raw").glob("tb*/logs")):
    for d in sorted(p for p in vm.iterdir() if p.is_dir() and re.fullmatch(r"(rock|df)-(\d+|x\d+b?|[vw]\d+)", p.name)):
        if d.name in dropped_labels:
            continue
        kind = "verify" if re.fullmatch(r"(rock|df)-[vw]\d+", d.name) else "main"
        target = T / kind / d.name
        shutil.copytree(d, target)
        for f in stolen.get(d.name, ()):
            for suffix in (".xml", ".log"):
                p = target / (f[:-3] + suffix)
                if p.exists():
                    p.unlink()
                    dropped += suffix == ".xml"
print("main:", sorted(p.name for p in (T / "main").iterdir()))
print("verify:", sorted(p.name for p in (T / "verify").iterdir()))
print("stolen placeholders dropped:", dropped)
