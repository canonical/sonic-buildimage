"""Compare the rock and Dockerfile shard results of the jasperoid t0 run.

usage: python3 -I analyze.py <results dir> [--lines]
Each test case gets a call outcome (setup-error / failed / skipped / passed) and, separately, its teardown result:
a loganalyzer failure whose matched lines are all known noise is 'la-noise', one with other lines is 'la', any
other teardown error is 'teardown-error'.
"""
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path

NOISE = [re.compile(r"nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)")]
SYSLOG_LINE = re.compile(r"\d{4} \w{3} +\d+ [\d:.]+ vlab-01 [A-Z]+ [^\\\n'\"]*")


def first_line(element):
    return ((element.get("message") or element.text or "").strip().splitlines() or [""])[0][:160]


def load(directory):
    entries = defaultdict(list)
    for xml in sorted(Path(directory).rglob("*.xml")):
        if xml.name == "pretest.xml" or "posttest" in xml.name:
            continue
        for case in ET.parse(xml).iter("testcase"):
            entries["{}::{}".format(case.get("classname", ""), case.get("name", ""))].append(case)
    result = {}
    for key, cases in entries.items():
        call, teardown, message, lines = "passed", "ok", "", set()
        for case in cases:
            for element in case:
                text = (element.get("message") or "") + "\n" + (element.text or "")
                if element.tag == "error" and "on teardown" in (element.get("message") or ""):
                    if "matched syslog" in text:
                        matched = {re.sub(r"^\d{4} \w{3} +\d+ [\d:.]+ ", "", m).strip() for m in SYSLOG_LINE.findall(text)}
                        residual = {m for m in matched if not any(n.search(m) for n in NOISE)}
                        lines |= residual
                        teardown = "la" if residual or teardown == "la" else "la-noise"
                    else:
                        teardown = "teardown-error"
                elif element.tag == "error":
                    call, message = "setup-error", first_line(element)
                elif element.tag == "failure" and call != "setup-error":
                    call, message = "failed", first_line(element)
                elif element.tag == "skipped" and call == "passed":
                    call, message = "skipped", first_line(element)
        result[key] = (call, teardown, message, lines)
    return result


def merged(root, image):
    result = {}
    for shard in sorted(Path(root).glob("{}-*".format(image))):
        if shard.is_dir():
            result.update(load(shard))
    return result


def main():
    root = sys.argv[1]
    rock, df = merged(root, "rock"), merged(root, "df")
    for name, run in (("df", df), ("rock", rock)):
        print("{}: call {} | teardown {}".format(name, dict(Counter(v[0] for v in run.values())),
                                                 dict(Counter(v[1] for v in run.values()))))
    print("\n== call outcome differs (df -> rock)")
    for key in sorted(set(df) | set(rock)):
        a, b = df.get(key, ("absent", "", "", set())), rock.get(key, ("absent", "", "", set()))
        if a[0] != b[0]:
            print("{}\n    df   {}: {}\n    rock {}: {}".format(key, a[0], a[2], b[0], b[2]))
    print("\n== teardown differs (df -> rock), ignoring la-noise vs ok")
    for key in sorted(set(df) & set(rock)):
        a, b = df[key][1], rock[key][1]
        if {a, b} != {"ok", "la-noise"} and a != b:
            print("{}: df {} -> rock {}".format(key, a, b))
    print("\n== loganalyzer lines beyond known noise")
    for name, run in (("df", df), ("rock", rock)):
        other = df if name == "rock" else rock
        counts = Counter(re.sub(r"\d+", "N", line)[:200] for v in run.values() for line in v[3])
        theirs = Counter(re.sub(r"\d+", "N", line)[:200] for v in other.values() for line in v[3])
        for line, n in counts.most_common():
            print("{:5} {} {}{}".format(n, name, line, "" if theirs.get(line) else "   [only " + name + "]"))
    print("\n== failures common to both")
    for key in sorted(set(df) & set(rock)):
        if df[key][0] in ("failed", "setup-error") and rock[key][0] == df[key][0]:
            print("{} {}: {}".format(key, df[key][0], df[key][2]))


if __name__ == "__main__":
    main()
