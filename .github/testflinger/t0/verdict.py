#!/usr/bin/env python3
"""Judge a resolute t0 run against known-failures.yaml.

  verdict.py rerun-files --chunk-dir DIR --known FILE
  verdict.py report --results DIR --known FILE --out-json F --out-md F --out-durations F [--meta F] [--infra REASON]

Result layout: DIR/<testbed>/<NNN[.retry][.rerun]>/<test file path>.xml, plus DIR/<testbed>/<NNN[.retry]>.time.
"""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

import yaml

SKIP_XML = {"pretest.xml", "posttest.xml"}
CHUNK_DIR = re.compile(r"^(\d{3})(\.retry)?(\.rerun)?$")
SYSLOG_LINE = re.compile(r"\d{4} \w{3} +\d+ [\d:.]+ (\S+ [A-Z]+ [^\\\n'\"]*)")
BAD = ("failed", "error")
LA_ERROR = re.compile(r"LogAnalyzerError: match: (\d+)")
LA_LINE = re.compile(r"^E\s+\d{4} \w{3} +\d+ [\d:.]+ (\S+ [A-Z]+ .*)$", re.M)


@dataclass
class Case:
    outcome: str
    message: str = ""


def id_pattern(text):
    return re.compile("^" + ".*".join(re.escape(part) for part in text.split("*")) + "$")


class Known:
    def __init__(self, path):
        data = yaml.safe_load(Path(path).read_text()) or {}
        self.entries = []
        for entry in data.get("known") or []:
            if entry.get("kind") not in ("fail", "error", "flaky") or not entry.get("id") or not entry.get("reason"):
                raise ValueError("bad known-failures entry: %r" % (entry,))
            self.entries.append(dict(entry, _re=id_pattern(entry["id"]),
                                     _file=id_pattern(entry["id"].split("::")[0])))
        self.noise = [re.compile(n["pattern"]) for n in data.get("loganalyzer_noise") or []]

    def covers(self, cid, case):
        want = "fail" if case.outcome == "failed" else "error"
        return any(e["kind"] in (want, "flaky") and e["_re"].match(cid) for e in self.entries)


def first_line(text):
    return (text.strip().splitlines() or [""])[0][:200]


def case_id(rel_xml, classname, name):
    module = rel_xml[:-len(".xml")]
    prefix = "tests." + module.replace("/", ".")
    rest = classname[len(prefix):] if classname == prefix or classname.startswith(prefix + ".") else classname
    return "::".join([module + ".py"] + [p for p in rest.split(".") if p] + [name])


def own_loganalyzer_noise(text, noise):
    m = LA_ERROR.search(text)
    if not m or "expected_missing_match: 0" not in text:
        return False
    lines = LA_LINE.findall(text)
    return len(lines) == int(m.group(1)) > 0 and all(any(n.search(line) for n in noise) for line in lines)


def parse_xml(path, rel_xml, noise):
    grouped = {}
    for tc in ET.parse(path).iter("testcase"):
        grouped.setdefault(case_id(rel_xml, tc.get("classname", ""), tc.get("name", "")), []).append(tc)
    cases = {}
    for cid, elements in grouped.items():
        call, teardown, message = "passed", "ok", ""
        for tc in elements:
            for el in tc:
                msg = el.get("message") or ""
                text = msg + "\n" + (el.text or "")
                if el.tag in ("failure", "error") and own_loganalyzer_noise(text, noise):
                    continue
                if el.tag == "error" and "on teardown" in msg:
                    lines = [m.strip() for m in SYSLOG_LINE.findall(text)] if "matched syslog" in text else []
                    residual = [line for line in lines if not any(n.search(line) for n in noise)]
                    if residual or not lines:
                        teardown = "error"
                        message = message or first_line(residual[0] if residual else (msg or text))
                elif el.tag == "error":
                    call, message = "error", first_line(msg or text)
                elif el.tag == "failure" and call != "error":
                    call, message = "failed", first_line(msg or text)
                elif el.tag == "skipped" and call == "passed":
                    call = "skipped"
        outcome = call if call in BAD else ("error" if teardown == "error" else call)
        cases[cid] = Case(outcome, message if outcome in BAD else "")
    return cases


def chunk_dirs(results):
    root = Path(results)
    if not root.is_dir():
        return
    for tb in sorted(p for p in root.iterdir() if p.is_dir()):
        for d in sorted(p for p in tb.iterdir() if p.is_dir()):
            m = CHUNK_DIR.match(d.name)
            if m:
                yield (m.group(1), bool(m.group(2)), bool(m.group(3))), d


def parse_dir(d, noise):
    files = {}
    for xml in sorted(Path(d).rglob("*.xml")):
        rel = xml.relative_to(d).as_posix()
        if rel in SKIP_XML:
            continue
        test_file = rel[:-len(".xml")] + ".py"
        try:
            files[test_file] = parse_xml(xml, rel, noise)
        except ET.ParseError as exc:
            files[test_file] = {test_file + "::<junit>": Case("error", "unreadable JUnit file: %s" % exc)}
    return files


def load_results(results, noise):
    attempts = {}
    for key, d in chunk_dirs(results):
        for test_file, cases in parse_dir(d, noise).items():
            attempts.setdefault(test_file, []).append((key, cases))
    first, final = {}, {}
    for runs in attempts.values():
        runs.sort(key=lambda run: run[0])
        for _, cases in runs:
            final.update(cases)
        for _, cases in reversed(runs):
            first.update(cases)
    return first, final, set(attempts)


STATE = {"regressions": "failure", "incomplete": "error", "infrastructure": "error", "pass": "success"}
TITLE = {"regressions": "Regressions", "incomplete": "Incomplete", "infrastructure": "Infrastructure", "pass": "Pass"}
MAX_ROWS = 100


def classify(final, known, ran):
    new, covered = [], []
    for cid in sorted(final):
        case = final[cid]
        if case.outcome in BAD:
            (covered if known.covers(cid, case) else new).append(cid)
    now_passing, stale = [], []
    for entry in known.entries:
        hits = [cid for cid in final if entry["_re"].match(cid)]
        if not hits:
            if any(entry["_file"].match(f) for f in ran):
                stale.append(entry)
        elif entry["kind"] != "flaky" and all(final[c].outcome == "passed" for c in hits):
            now_passing.append(entry)
    return new, covered, now_passing, stale


def decide(new, not_run, infra):
    if infra:
        return "infrastructure"
    if new:
        return "regressions"
    if not_run:
        return "incomplete"
    return "pass"


def durations(results):
    out = {}
    for key, d in chunk_dirs(results):
        if key[2]:
            continue
        per = {}
        for xml in d.rglob("*.xml"):
            rel = xml.relative_to(d).as_posix()
            if rel in SKIP_XML:
                continue
            try:
                per[rel[:-len(".xml")] + ".py"] = sum(float(s.get("time", 0)) for s in ET.parse(xml).iter("testsuite"))
            except ET.ParseError:
                continue
        extra = 0.0
        timing = d.parent / (d.name + ".time")
        if per and timing.exists():
            start, end = (float(x) for x in timing.read_text().split()[:2])
            extra = max(0.0, (end - start) - sum(per.values())) / len(per)
        for test_file, seconds in per.items():
            out[test_file] = round(seconds + extra, 1)
    return out


def esc(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def table(rows, header):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(esc(c) for c in row) + " |" for row in rows[:MAX_ROWS]]
    if len(rows) > MAX_ROWS:
        lines += ["", "…and %d more in summary.json" % (len(rows) - MAX_ROWS)]
    return "\n".join(lines)


def bullets(items):
    lines = ["- " + item for item in items[:MAX_ROWS]]
    if len(items) > MAX_ROWS:
        lines.append("- …and %d more in summary.json" % (len(items) - MAX_ROWS))
    return lines


def render(summary):
    s, t, meta = summary, summary["totals"], summary["meta"]
    out = ["## resolute-t0: %s" % s["title"], ""]
    if s["infra"]:
        out += ["**Infrastructure problem:** %s" % s["infra"], ""]
    out += [table([[t["passed"], t["skipped"], t["failed"], t["error"], t["not_run_files"]]],
                  ["passed", "skipped", "failed", "errors", "files not run"]), ""]
    if s["new"]:
        out += ["### New failures (%d)" % len(s["new"]), "",
                table([["`%s`" % c["id"], c["outcome"], c["message"]] for c in s["new"]], ["case", "outcome", "message"]), ""]
    if s["rerun_passed"]:
        out += ["### Passed only on rerun (%d)" % len(s["rerun_passed"]), ""] + bullets(["`%s`" % c for c in s["rerun_passed"]]) + [""]
    if s["now_passing"]:
        out += ["### Known entries now passing (%d): remove them from known-failures.yaml" % len(s["now_passing"]), ""]
        out += bullets(["`%s` (%s): %s" % (e["id"], e["kind"], e["reason"]) for e in s["now_passing"]]) + [""]
    if s["stale"]:
        out += ["### Stale known entries (%d): they match no case in the files that ran" % len(s["stale"]), ""]
        out += bullets(["`%s` (%s): %s" % (e["id"], e["kind"], e["reason"]) for e in s["stale"]]) + [""]
    if s["not_run"]:
        out += ["### Files not run (%d)" % len(s["not_run"]), ""] + bullets(["`%s`" % f for f in s["not_run"]]) + [""]
    if s["covered"]:
        out += ["<details><summary>Known failures still failing (%d)</summary>" % len(s["covered"]), "",
                table([["`%s`" % c["id"], c["outcome"], c["message"]] for c in s["covered"]], ["case", "outcome", "message"]),
                "", "</details>", ""]
    phases = ", ".join("%s %dm" % (k, int(v) // 60) for k, v in (meta.get("phases") or {}).items())
    out += ["### Environment", "",
            table([[meta.get("machine", "?"), meta.get("testbeds", "?"), meta.get("scope", "?"),
                    "`%s`" % str(meta.get("image_sha256", "?"))[:12], "`%s`" % str(meta.get("sonic_mgmt", "?"))[:10], phases]],
                  ["machine", "testbeds", "scope", "image sha256", "sonic-mgmt", "phases"]), ""]
    return "\n".join(out)


def describe(outcome, new, not_run, infra, totals):
    if outcome == "infrastructure":
        return "Infrastructure: " + infra
    if outcome == "regressions":
        return "%d new failures" % len(new)
    if outcome == "incomplete":
        return "%d files not run; no new failures" % len(not_run)
    return "%d passed; no new failures" % totals["passed"]


def public(entry):
    return {k: entry[k] for k in ("id", "kind", "reason")}


def cmd_report(args):
    known = Known(args.known)
    meta = json.loads(Path(args.meta).read_text()) if args.meta and Path(args.meta).exists() else None
    infra = args.infra
    if not infra and meta is None:
        infra = "no run-meta.json came back"
    if not infra and meta.get("rc", 0) != 0:
        infra = "the harness exited with %s during %s" % (meta.get("rc"), meta.get("phase", "?"))
    first, final, ran = load_results(args.results, known.noise)
    new, covered, now_passing, stale = classify(final, known, ran)
    not_run = sorted(set(meta.get("files", [])) - ran) if meta else []
    outcome = decide(new, not_run, infra)
    totals = {k: sum(1 for c in final.values() if c.outcome == k) for k in ("passed", "skipped", "failed", "error")}
    totals["not_run_files"] = len(not_run)
    summary = {
        "outcome": outcome, "state": STATE[outcome], "title": TITLE[outcome],
        "description": describe(outcome, new, not_run, infra, totals), "infra": infra, "totals": totals,
        "new": [{"id": c, "outcome": final[c].outcome, "message": final[c].message} for c in new],
        "covered": [{"id": c, "outcome": final[c].outcome, "message": final[c].message} for c in covered],
        "now_passing": [public(e) for e in now_passing], "stale": [public(e) for e in stale],
        "rerun_passed": sorted(c for c in final if final[c].outcome == "passed" and first[c].outcome in BAD),
        "not_run": not_run, "meta": meta or {},
        "cases": {c: {"first": first[c].outcome, "final": final[c].outcome} for c in sorted(final)},
    }
    Path(args.out_json).write_text(json.dumps(summary, indent=1))
    Path(args.out_md).write_text(render(summary))
    Path(args.out_durations).write_text(json.dumps(durations(args.results), indent=1, sort_keys=True))


def cmd_rerun_files(args):
    known = Known(args.known)
    for test_file, cases in sorted(parse_dir(Path(args.chunk_dir), known.noise).items()):
        if any(c.outcome in BAD and not known.covers(cid, c) for cid, c in cases.items()):
            print(test_file)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    rerun = sub.add_parser("rerun-files")
    rerun.add_argument("--chunk-dir", required=True)
    rerun.add_argument("--known", required=True)
    rep = sub.add_parser("report")
    for opt in ("--results", "--known", "--out-json", "--out-md", "--out-durations"):
        rep.add_argument(opt, required=True)
    rep.add_argument("--meta")
    rep.add_argument("--infra", default="")
    args = parser.parse_args(argv)
    {"rerun-files": cmd_rerun_files, "report": cmd_report}[args.cmd](args)


if __name__ == "__main__":
    main()
