"""Compare sonic-mgmt junit results of two run_tests.sh log directories.

usage: python3 -I compare.py <run A dir> <run B dir> [--all]
Prints a per-run summary, then every test case whose outcome differs, then failures common to both.
"""
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


def outcomes(directory):
    result = {}
    for xml in sorted(Path(directory).rglob("*.xml")):
        for case in ET.parse(xml).iter("testcase"):
            key = "{}::{}".format(case.get("classname", ""), case.get("name", ""))
            outcome, message = "passed", ""
            for tag in ("error", "failure", "skipped"):
                element = case.find(tag)
                if element is not None:
                    outcome = {"error": "error", "failure": "failed", "skipped": "skipped"}[tag]
                    message = ((element.get("message") or element.text or "").strip().splitlines() or [""])[0]
                    break
            # a teardown error is reported as a second testcase entry with the same name
            if key in result and result[key][0] != "passed" and outcome == "passed":
                continue
            result[key] = (outcome, message[:160])
    return result


def main():
    a_dir, b_dir = sys.argv[1], sys.argv[2]
    a, b = outcomes(a_dir), outcomes(b_dir)
    for name, run in ((a_dir, a), (b_dir, b)):
        print("{}: {}".format(name, dict(Counter(o for o, _ in run.values()))))
    print("\n== outcome differs ({} vs {})".format(Path(a_dir).name, Path(b_dir).name))
    for key in sorted(set(a) | set(b)):
        oa, ob = a.get(key, ("absent", "")), b.get(key, ("absent", ""))
        if oa[0] != ob[0]:
            print("{}\n    A {}: {}\n    B {}: {}".format(key, oa[0], oa[1], ob[0], ob[1]))
    print("\n== failed or error in both")
    for key in sorted(set(a) & set(b)):
        if a[key][0] in ("failed", "error") and b[key][0] in ("failed", "error"):
            print("{}\n    A {}: {}\n    B {}: {}".format(key, a[key][0], a[key][1], b[key][0], b[key][1]))
    if "--all" in sys.argv:
        print("\n== all")
        for key in sorted(set(a) | set(b)):
            print("{:8} {:8} {}".format(a.get(key, ("absent",))[0], b.get(key, ("absent",))[0], key))


if __name__ == "__main__":
    main()
