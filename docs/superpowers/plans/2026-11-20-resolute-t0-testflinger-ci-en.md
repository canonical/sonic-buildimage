# Automated sonic-mgmt t0 runs on Testflinger — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A GitHub Actions workflow in `canonical/sonic-buildimage` that runs the upstream sonic-mgmt t0 checker list against the `resolute-build` vs image on one Testflinger machine, judges the results against a known-failures list in the repository, and reports them nightly, after push/tag builds and on a `/test-t0` PR comment.

**Architecture:** One workflow (`resolute-t0.yml`) with a short `resolve` job on `ubuntu-latest` and a long `t0` job on the small self-hosted runner. The `t0` job publishes the image as a release asset, submits a Testflinger job with the official submit action (`poll: true`, `retries: 2`) and judges the returned artifacts with `verdict.py`. On the Testflinger machine, `run-t0.sh` builds LXD VMs, each VM (`tb-run.sh`) builds a `vms-kvm-t0` testbed and takes chunks of test files from a shared queue, and the results come back compressed. Design: `docs/superpowers/specs/2026-11-20-resolute-t0-testflinger-ci-design-en.md` on `202605_resolute_doc`.

**Tech Stack:** GitHub Actions; Testflinger (`canonical/testflinger` submit action, `testflinger-cli`); bash; Python 3.12+ with only the standard library and PyYAML; pytest; LXD VMs on Ubuntu 26.04; sonic-mgmt `run_tests.sh` / `testbed-cli.sh`; docker; zstd.

## Global Constraints

- Work in the worktree `~/scratch/wt-t0` on branch `feat/resolute-t0-testflinger`, created from `canonical/202605_resolute`. Use `git -C <dir>` for every git command: the shell's working directory can silently reset to the docs repository.
- `202605_resolute` is a production branch: changes reach it only through a pull request. Never cancel a running GitHub Actions run without asking the user first (AGENTS.md).
- Commits are GPG-signed (`commit.gpgsign` is already `true`), use the `test:` prefix, and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Comments in code: only where the reason is not obvious, one line each. Root causes and numbers go into commit messages.
- Python must run on Python 3.12 (the runner) and 3.14 (Ubuntu 26.04), with the standard library plus PyYAML only.
- Every `reason` in `known-failures.yaml` is written in English.
- Never release or cancel a Testflinger reservation the user holds without their explicit word.
- Fixed names, used verbatim everywhere:
  - Testflinger queue `sonic-ci-large`; Testflinger secret path `sonic-buildimage/ghcr-read-token`
  - cEOS image `ghcr.io/canonical/sonic-ceos:4.32.5M-1`, retagged on the machine as `ceosimage:4.32.5M-1`
  - release tag `t0-images`; asset name `sonic-vs-<sha12>.img.gz` plus `.sha256`; newest 10 kept
  - commit status context `resolute-t0`; PR comment marker `<!-- resolute-t0 -->`
  - runner label `self-hosted-linux-amd64-noble-private-endpoint-small`; job `timeout-minutes: 1440`
  - submit action `canonical/testflinger/.github/actions/submit@257ef71c8042a41925d7185d46fc3171ea2112f5` (submit/v1.6.0)
  - schedule `cron: "0 15 * * *"`; job file `global_timeout: 43200`, `output_timeout: 7200`
  - sonic-mgmt pin `a88d1d5f9323833d8cf2e050c84904deb22ed3bc` (`canonical/sonic-mgmt`)
  - testbed `vms-kvm-t0`, DUT `vlab-01`, VM user `tb`; chunk target 3000 s, unknown file 480 s
  - sizing T = min(⌊(RAM GiB − 16) / 18⌋, ⌊threads / 8⌋, ⌊free pool GB / 40⌋), at most 2 for smoke; dispatch stops 37800 s after the harness starts, hard stop at 41400 s

---

## File Structure

All new files, in `canonical/sonic-buildimage`:

| File | Responsibility |
|---|---|
| `.github/workflows/resolute-t0.yml` | Triggers, build resolution, image publishing, Testflinger submission, verdict, reporting |
| `.github/testflinger/t0/make_chunks.py` | Packs test files into chunks by expected duration |
| `.github/testflinger/t0/verdict.py` | Parses JUnit, picks files to rerun, classifies cases against the known list, writes summary/report/durations |
| `.github/testflinger/t0/configure_sonic_mgmt.py` | Applies the KVM testbed settings to a sonic-mgmt tree |
| `.github/testflinger/t0/render_job.py` + `job.yaml.in` | Renders the Testflinger job file |
| `.github/testflinger/t0/agent.sh` | Agent side: copies the harness, starts it detached, relays progress, fetches artifacts |
| `.github/testflinger/t0/run-t0.sh` | Machine side entry: phases, VM launch, monitoring, time guard, packing, `run-meta.json` |
| `.github/testflinger/t0/host-setup.sh` | Host packages, LXD, storage pool, swap, firewall, shared images, sizing |
| `.github/testflinger/t0/tb-run.sh` | One testbed in one VM: tools, add-topo, deploy-mg, chunk loop, reruns |
| `.github/testflinger/t0/known-failures.yaml` | Reviewed known failures and loganalyzer noise rules |
| `.github/testflinger/t0/sonic-mgmt.ref` | Pinned sonic-mgmt commit |
| `.github/testflinger/t0/smoke.txt` | Smoke test list |
| `.github/testflinger/t0/tests/` | pytest tests: `conftest.py`, `test_make_chunks.py`, `test_verdict.py`, `test_configure_sonic_mgmt.py`, `test_render_job.py`, `test_shell_syntax.py` |

Test command, from the worktree root: `python3 -m pytest -q .github/testflinger/t0/tests`

---

### Task 1: Worktree and chunk packing

**Files:**
- Create: `.github/testflinger/t0/make_chunks.py`
- Create: `.github/testflinger/t0/tests/conftest.py`
- Test: `.github/testflinger/t0/tests/test_make_chunks.py`

**Interfaces:**
- Produces: `make_chunks.pack(files: list[str], durations: dict[str, float], target: float = 3000.0, default: float = 480.0) -> list[list[str]]`; CLI `make_chunks.py <file list> <durations.json> <out dir> [target] [default]` writing files `000`, `001`, … (one test file per line).

- [ ] **Step 1: Create the worktree**

```bash
R=/home/sheldon-qi/sonic-buildimage-resolute
git -C $R fetch -q canonical 202605_resolute
git -C $R worktree add -q --no-checkout -b feat/resolute-t0-testflinger ~/scratch/wt-t0 canonical/202605_resolute
git -C ~/scratch/wt-t0 sparse-checkout set --no-cone /.github/ /AGENTS.md
git -C ~/scratch/wt-t0 checkout -q
git -C ~/scratch/wt-t0 branch --show-current
```

Expected: `feat/resolute-t0-testflinger`.

- [ ] **Step 2: Write the failing tests**

`.github/testflinger/t0/tests/conftest.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

`.github/testflinger/t0/tests/test_make_chunks.py`:

```python
import json
import subprocess
import sys
from pathlib import Path

import make_chunks


def test_every_file_appears_once():
    chunks = make_chunks.pack(["a.py", "b.py", "c.py", "a.py"], {"a.py": 100, "b.py": 200}, target=300, default=50)
    assert sorted(f for chunk in chunks for f in chunk) == ["a.py", "b.py", "c.py"]


def test_chunks_stay_under_target_unless_one_file_is_longer():
    durations = {"long.py": 5000, "x.py": 1000, "y.py": 1500, "z.py": 900}
    chunks = make_chunks.pack(list(durations), durations, target=3000)
    for chunk in chunks:
        assert sum(durations[f] for f in chunk) <= 3000 or len(chunk) == 1
    assert ["long.py"] in chunks


def test_longest_chunk_first_and_default_for_unknown_files():
    chunks = make_chunks.pack(["new.py", "short.py"], {"short.py": 10}, target=100, default=480)
    assert chunks[0] == ["new.py"]


def test_target_one_puts_every_file_in_its_own_chunk():
    assert sorted(make_chunks.pack(["a.py", "b.py", "c.py"], {}, target=1)) == [["a.py"], ["b.py"], ["c.py"]]


def test_cli_writes_numbered_chunk_files(tmp_path):
    (tmp_path / "files.txt").write_text("a.py\nb.py\n")
    (tmp_path / "d.json").write_text(json.dumps({"a.py": 2000, "b.py": 2000}))
    subprocess.run([sys.executable, str(Path(make_chunks.__file__)), str(tmp_path / "files.txt"),
                    str(tmp_path / "d.json"), str(tmp_path / "out"), "3000"], check=True)
    names = sorted(p.name for p in (tmp_path / "out").iterdir())
    assert names == ["000", "001"]
    assert {(tmp_path / "out" / n).read_text().strip() for n in names} == {"a.py", "b.py"}


def test_cli_without_durations_file(tmp_path):
    (tmp_path / "files.txt").write_text("a.py\n")
    subprocess.run([sys.executable, str(Path(make_chunks.__file__)), str(tmp_path / "files.txt"),
                    str(tmp_path / "missing.json"), str(tmp_path / "out")], check=True)
    assert (tmp_path / "out" / "000").read_text() == "a.py\n"
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_make_chunks.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'make_chunks'`.

- [ ] **Step 4: Write `make_chunks.py`**

```python
#!/usr/bin/env python3
"""Pack test files into chunks of about TARGET seconds, longest first.

usage: make_chunks.py <file list> <durations.json> <out dir> [target seconds] [default seconds]
"""
import json
import os
import sys


def pack(files, durations, target=3000.0, default=480.0):
    est = {f: float(durations.get(f, default)) for f in files}
    chunks = []
    for f in sorted(dict.fromkeys(files), key=lambda f: (-est[f], f)):
        best = None
        for chunk in chunks:
            if chunk["t"] + est[f] <= target and (best is None or chunk["t"] > best["t"]):
                best = chunk
        if best is None:
            best = {"t": 0.0, "files": []}
            chunks.append(best)
        best["files"].append(f)
        best["t"] += est[f]
    chunks.sort(key=lambda c: -c["t"])
    return [c["files"] for c in chunks]


def main(argv):
    with open(argv[1]) as fh:
        files = [line.strip() for line in fh if line.strip()]
    durations = {}
    if os.path.exists(argv[2]):
        with open(argv[2]) as fh:
            durations = json.load(fh)
    target = float(argv[4]) if len(argv) > 4 else 3000.0
    default = float(argv[5]) if len(argv) > 5 else 480.0
    chunks = pack(files, durations, target, default)
    os.makedirs(argv[3], exist_ok=True)
    for i, chunk in enumerate(chunks):
        with open(os.path.join(argv[3], "%03d" % i), "w") as fh:
            fh.write("\n".join(chunk) + "\n")
    print("%d files -> %d chunks" % (len(set(files)), len(chunks)))


if __name__ == "__main__":
    main(sys.argv)
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_make_chunks.py`
Expected: `6 passed`.

- [ ] **Step 6: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/make_chunks.py .github/testflinger/t0/tests/conftest.py .github/testflinger/t0/tests/test_make_chunks.py
git -C $W commit -m "test: pack sonic-mgmt test files into chunks by expected duration

Longest file first into the fullest chunk that still fits, so testbeds
finish at about the same time; files with no recorded duration count
480 s, as in the 2026-11-19 farm run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Verdict — JUnit parsing and known-failures matching

**Files:**
- Create: `.github/testflinger/t0/verdict.py`
- Test: `.github/testflinger/t0/tests/test_verdict.py`

**Interfaces:**
- Produces: `Case(outcome: str, message: str = "")` with outcome in `passed|skipped|failed|error`; `id_pattern(text) -> re.Pattern`; `Known(path)` with `.entries` (dicts with `id`, `kind`, `reason`, `_re`, `_file`), `.noise` (compiled patterns), `.covers(cid, case) -> bool`; `case_id(rel_xml, classname, name) -> str`; `parse_xml(path, rel_xml, noise) -> dict[str, Case]`; `chunk_dirs(results) -> iterator of ((chunk, retry, rerun), Path)`; `parse_dir(d, noise) -> dict[test file, dict[str, Case]]`; `load_results(results, noise) -> (first: dict[str, Case], final: dict[str, Case], ran: set[str])`; constants `SKIP_XML`, `CHUNK_DIR`, `BAD`.

- [ ] **Step 1: Write the failing tests**

`.github/testflinger/t0/tests/test_verdict.py`:

```python
import json
import re
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import quoteattr

import pytest
import yaml

import verdict

NOISE = r"nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)"
LA = ('failed on teardown with "Failed: Got matched syslog in processes "analyze_logs--<MultiAsicSonicHost vlab-01>" '
      'exit code:"1"\nmatch: 1\n\nMatch Messages:\n2026 Nov 19 11:59:45.003096 vlab-01 ERR {}\n')
TACPLUS = LA.format("unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed")
OTHER = LA.format("orchagent: :- doTask: something broke")
SCRIPT = Path(verdict.__file__)


def fail(msg):
    return "<failure message=%s/>" % quoteattr(msg)


def err(msg):
    return "<error message=%s/>" % quoteattr(msg)


def skip(msg="skipped"):
    return "<skipped message=%s/>" % quoteattr(msg)


def junit(path, cases, suite_time=1.0):
    body = "".join('<testcase classname="%s" name="%s" time="1">%s</testcase>' % c for c in cases)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('<?xml version="1.0"?><testsuites name="pytest tests"><testsuite name="pytest" time="%s">%s'
                    '</testsuite></testsuites>' % (suite_time, body))


def known_file(tmp_path, entries=()):
    path = tmp_path / "known.yaml"
    path.write_text(yaml.safe_dump({"known": list(entries),
                                    "loganalyzer_noise": [{"pattern": NOISE, "reason": "noise"}]}))
    return path


def test_case_id_for_function_and_class():
    assert verdict.case_id("test_interfaces.xml", "tests.test_interfaces", "test_interfaces[vlab-01-None]") == \
        "test_interfaces.py::test_interfaces[vlab-01-None]"
    assert verdict.case_id("acl/test_acl.xml", "tests.acl.test_acl.TestBasicAcl", "test_rule[ipv4]") == \
        "acl/test_acl.py::TestBasicAcl::test_rule[ipv4]"


def test_id_pattern_star_and_brackets():
    exact = verdict.id_pattern("snmp/test_x.py::test_a[vlab-01]")
    assert exact.match("snmp/test_x.py::test_a[vlab-01]")
    assert not exact.match("snmp/test_x.py::test_a[vlab-02]")
    assert verdict.id_pattern("generic_hash/*").match("generic_hash/test_g.py::test_h[ipv4-1]")


def test_outcomes_and_first_message_line(tmp_path):
    xml = tmp_path / "snmp" / "test_x.xml"
    junit(xml, [("tests.snmp.test_x", "test_pass", ""),
                ("tests.snmp.test_x", "test_fail", fail("assert 1 == 2\nmore detail")),
                ("tests.snmp.test_x", "test_setup", err('failed on setup with "boom"')),
                ("tests.snmp.test_x", "test_skip", skip())])
    cases = verdict.parse_xml(xml, "snmp/test_x.xml", [])
    assert {cid: c.outcome for cid, c in cases.items()} == {
        "snmp/test_x.py::test_pass": "passed", "snmp/test_x.py::test_fail": "failed",
        "snmp/test_x.py::test_setup": "error", "snmp/test_x.py::test_skip": "skipped"}
    assert cases["snmp/test_x.py::test_fail"].message == "assert 1 == 2"


def test_loganalyzer_noise_only_is_ignored(tmp_path):
    xml = tmp_path / "t.xml"
    junit(xml, [("tests.t", "a", ""), ("tests.t", "a", err(TACPLUS)),
                ("tests.t", "b", ""), ("tests.t", "b", err(OTHER)),
                ("tests.t", "c", err('failed on teardown with "fixture exploded"'))])
    cases = verdict.parse_xml(xml, "t.xml", [re.compile(NOISE)])
    assert cases["t.py::a"].outcome == "passed"
    assert cases["t.py::b"].outcome == "error"
    assert "doTask" in cases["t.py::b"].message
    assert cases["t.py::c"].outcome == "error"


def test_known_rejects_entry_without_reason(tmp_path):
    with pytest.raises(ValueError):
        verdict.Known(known_file(tmp_path, [{"id": "a.py::x", "kind": "fail"}]))


def test_known_covers_by_kind(tmp_path):
    known = verdict.Known(known_file(tmp_path, [{"id": "a.py::x", "kind": "fail", "reason": "r"},
                                                {"id": "a.py::f*", "kind": "flaky", "reason": "r"}]))
    assert known.covers("a.py::x", verdict.Case("failed"))
    assert not known.covers("a.py::x", verdict.Case("error"))
    assert known.covers("a.py::flaky_one", verdict.Case("error"))


def test_load_results_prefers_the_last_attempt(tmp_path):
    junit(tmp_path / "r" / "tb1" / "000" / "a.xml", [("tests.a", "x", fail("first")), ("tests.a", "y", "")])
    junit(tmp_path / "r" / "tb1" / "000.rerun" / "a.xml", [("tests.a", "x", "")])
    junit(tmp_path / "r" / "tb2" / "001" / "b.xml", [("tests.b", "z", skip())])
    junit(tmp_path / "r" / "tb2" / "001" / "pretest.xml", [("tests.test_pretest", "p", fail("ignored"))])
    first, final, ran = verdict.load_results(tmp_path / "r", [])
    assert first["a.py::x"].outcome == "failed" and final["a.py::x"].outcome == "passed"
    assert final["a.py::y"].outcome == "passed"
    assert ran == {"a.py", "b.py"}


def test_unreadable_junit_is_an_error(tmp_path):
    bad = tmp_path / "d" / "a.xml"
    bad.parent.mkdir(parents=True)
    bad.write_text("<testsuites><testsuite>")
    files = verdict.parse_dir(tmp_path / "d", [])
    assert [c.outcome for c in files["a.py"].values()] == ["error"]
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'verdict'`.

- [ ] **Step 3: Write the first part of `verdict.py`**

```python
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
Expected: `8 passed`.

- [ ] **Step 5: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/verdict.py .github/testflinger/t0/tests/test_verdict.py
git -C $W commit -m "test: parse sonic-mgmt JUnit results into pytest node ids

run_tests.sh -m individual writes one JUnit file per test file, so the
file path gives the module and the classname the class. Loganalyzer
teardown errors whose matched syslog lines are all known noise are
dropped: until PR #30 merges, nss_tacplus lines hit dozens of cases per
run (36 on 2026-11-19), on different cases each time.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Verdict — classification, report and CLI

**Files:**
- Modify: `.github/testflinger/t0/verdict.py` (append)
- Test: `.github/testflinger/t0/tests/test_verdict.py` (append)

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: `classify(final, known, ran) -> (new: list[str], covered: list[str], now_passing: list[entry], stale: list[entry])`; `decide(new, not_run, infra) -> "infrastructure"|"regressions"|"incomplete"|"pass"`; `durations(results) -> dict[str, float]`; `render(summary) -> str`; CLI subcommands `rerun-files` (prints one test file per line) and `report` (writes `summary.json` with keys `outcome, state, title, description, infra, totals, new, covered, now_passing, stale, rerun_passed, not_run, meta, cases`, the markdown report and `durations.json`).

- [ ] **Step 1: Append the failing tests to `test_verdict.py`**

```python
def test_decide_priority():
    assert verdict.decide(["x"], ["f.py"], "boom") == "infrastructure"
    assert verdict.decide(["x"], ["f.py"], "") == "regressions"
    assert verdict.decide([], ["f.py"], "") == "incomplete"
    assert verdict.decide([], [], "") == "pass"


def build_run(tmp_path):
    r = tmp_path / "results"
    junit(r / "tb1" / "000" / "a.xml", [("tests.a", "new", fail("boom")), ("tests.a", "known", fail("old bug")),
                                        ("tests.a", "flip", fail("flaky"))], suite_time=100)
    junit(r / "tb1" / "000.rerun" / "a.xml", [("tests.a", "new", fail("boom")), ("tests.a", "known", fail("old bug")),
                                              ("tests.a", "flip", "")])
    junit(r / "tb1" / "000" / "b.xml", [("tests.b", "fixed", "")], suite_time=50)
    (r / "tb1" / "000.time").write_text("0 450\n")
    meta = tmp_path / "run-meta.json"
    meta.write_text(json.dumps({"files": ["a.py", "b.py", "c.py"], "rc": 0, "phase": "done", "machine": "m1",
                                "testbeds": 2, "scope": "full", "image_sha256": "f" * 64,
                                "sonic_mgmt": "a88d1d5f93", "phases": {"tests": 3600}}))
    known = known_file(tmp_path, [
        {"id": "a.py::known", "kind": "fail", "reason": "old bug"},
        {"id": "b.py::fixed", "kind": "fail", "reason": "was broken"},
        {"id": "b.py::gone", "kind": "fail", "reason": "renamed since"},
        {"id": "z.py::*", "kind": "flaky", "reason": "not in this run"}])
    return r, meta, known


def report(tmp_path, *extra):
    out = tmp_path / "out"
    out.mkdir(exist_ok=True)
    subprocess.run([sys.executable, str(SCRIPT), "report", "--out-json", str(out / "summary.json"),
                    "--out-md", str(out / "report.md"), "--out-durations", str(out / "durations.json"), *extra],
                   check=True)
    return (json.loads((out / "summary.json").read_text()), (out / "report.md").read_text(),
            json.loads((out / "durations.json").read_text()))


def test_report_classifies_every_group(tmp_path):
    r, meta, known = build_run(tmp_path)
    summary, md, _ = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta))
    assert summary["outcome"] == "regressions" and summary["state"] == "failure"
    assert [c["id"] for c in summary["new"]] == ["a.py::new"]
    assert [c["id"] for c in summary["covered"]] == ["a.py::known"]
    assert summary["rerun_passed"] == ["a.py::flip"]
    assert [e["id"] for e in summary["now_passing"]] == ["b.py::fixed"]
    assert [e["id"] for e in summary["stale"]] == ["b.py::gone"]
    assert summary["not_run"] == ["c.py"]
    assert summary["totals"] == {"passed": 2, "skipped": 0, "failed": 2, "error": 0, "not_run_files": 1}
    assert "## resolute-t0: Regressions" in md and "`a.py::new`" in md


def test_report_without_meta_is_infrastructure(tmp_path):
    summary, _, _ = report(tmp_path, "--results", str(tmp_path / "none"), "--known", str(known_file(tmp_path)))
    assert summary["outcome"] == "infrastructure" and summary["state"] == "error"
    assert "no run-meta.json" in summary["description"]


def test_report_harness_failure_is_infrastructure(tmp_path):
    r, meta, known = build_run(tmp_path)
    data = json.loads(meta.read_text())
    data.update(rc=1, phase="payload")
    meta.write_text(json.dumps(data))
    summary, _, _ = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta))
    assert summary["outcome"] == "infrastructure" and "payload" in summary["infra"]


def test_report_infra_flag_wins(tmp_path):
    r, meta, known = build_run(tmp_path)
    summary, _, _ = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta),
                           "--infra", "provisioning failed after the retries")
    assert summary["outcome"] == "infrastructure"
    assert summary["description"] == "Infrastructure: provisioning failed after the retries"


def test_durations_share_the_chunk_wall_time(tmp_path):
    r, meta, known = build_run(tmp_path)
    _, _, durations = report(tmp_path, "--results", str(r), "--known", str(known), "--meta", str(meta))
    assert durations == {"a.py": 250.0, "b.py": 200.0}


def test_rerun_files_lists_only_uncovered_failures(tmp_path):
    d = tmp_path / "000"
    junit(d / "a.xml", [("tests.a", "x", fail("new"))])
    junit(d / "b.xml", [("tests.b", "y", fail("known"))])
    junit(d / "c.xml", [("tests.c", "z", ""), ("tests.c", "z", err(TACPLUS))])
    junit(d / "pretest.xml", [("tests.test_pretest", "p", fail("ignored"))])
    known = known_file(tmp_path, [{"id": "b.py::y", "kind": "fail", "reason": "known"}])
    out = subprocess.run([sys.executable, str(SCRIPT), "rerun-files", "--chunk-dir", str(d), "--known", str(known)],
                         check=True, capture_output=True, text=True).stdout
    assert out.split() == ["a.py"]
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
Expected: FAIL: `AttributeError: module 'verdict' has no attribute 'decide'`, and the CLI tests fail with a non-zero exit status.

- [ ] **Step 3: Append the second part to `verdict.py`**

```python
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests`
Expected: `21 passed`.

- [ ] **Step 5: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/verdict.py .github/testflinger/t0/tests/test_verdict.py
git -C $W commit -m "test: judge t0 results against the known-failures list

A failure the list does not cover makes the run red; missing files make
it incomplete; a missing run-meta.json, a non-zero harness exit or a
failed provision make it an infrastructure problem. Reruns are chosen
from uncovered failures only. Durations add each chunk's unaccounted
wall time (pytest collection) evenly to its files.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: sonic-mgmt testbed settings

**Files:**
- Create: `.github/testflinger/t0/configure_sonic_mgmt.py`
- Test: `.github/testflinger/t0/tests/test_configure_sonic_mgmt.py`

**Interfaces:**
- Produces: `set_creds(text, user, password) -> str`; `set_inventory(text, user) -> str`; `set_server(text) -> str`; `main(root, user, password)`; CLI `configure_sonic_mgmt.py <sonic-mgmt dir> <user> <password>`.

- [ ] **Step 1: Write the failing tests**

`.github/testflinger/t0/tests/test_configure_sonic_mgmt.py`:

```python
import pytest

import configure_sonic_mgmt as cfg

CREDS = ("ptf_host_user: root\n\nvm_host_user: use_own_value\nvm_host_password: use_own_value\n"
         "vm_host_become_password: use_own_value\n\ncsonic_image: docker-sonic-vs\n")
VEOS = """all:
  children:
    lab:
      hosts:
        vlab-01:
          ansible_host: 10.250.0.101

          ansible_password: password
          ansible_user: admin
        vlab-02:
          ansible_user: admin
          ansible_python_interpreter: /usr/bin/python3
vm_host_1:
  hosts:
    STR-ACS-VSERV-01:
      ansible_host: 172.17.0.1
      ansible_user: use_own_value
      vm_host_user: use_own_value
"""
PY = "ansible_python_interpreter: /usr/bin/python3"


def test_set_creds_replaces_the_three_keys():
    out = cfg.set_creds(CREDS, "tb", "s3cret")
    assert "vm_host_user: tb\nvm_host_password: s3cret\nvm_host_become_password: s3cret\n" in out
    assert "use_own_value" not in out and "csonic_image: docker-sonic-vs" in out


def test_set_creds_fails_when_a_key_is_missing():
    with pytest.raises(ValueError):
        cfg.set_creds("vm_host_user: x\n", "tb", "p")


def test_set_inventory_adds_interpreter_once_and_sets_the_server_user():
    out = cfg.set_inventory(VEOS, "tb")
    assert "          ansible_user: admin\n          %s\n        vlab-02:" % PY in out
    assert out.count(PY) == 2
    assert "      ansible_user: tb\n      vm_host_user: tb\n" in out
    assert cfg.set_inventory(out, "tb") == out


def test_set_server_appends_interpreter_once():
    out = cfg.set_server("internal_mgmt_port: True\n")
    assert out == "internal_mgmt_port: True\n\n%s\n" % PY
    assert cfg.set_server(out) == out


def test_main_edits_the_tree(tmp_path):
    a = tmp_path / "ansible"
    (a / "group_vars" / "all").mkdir(parents=True)
    (a / "group_vars" / "vm_host").mkdir(parents=True)
    (a / "host_vars").mkdir()
    (a / "group_vars" / "all" / "creds.yml").write_text(CREDS)
    (a / "group_vars" / "vm_host" / "creds.yml").write_text(CREDS)
    (a / "veos_vtb").write_text(VEOS)
    (a / "host_vars" / "STR-ACS-VSERV-01.yml").write_text("internal_mgmt_port: True\n")
    cfg.main(str(tmp_path), "tb", "pw")
    assert (a / "password.txt").read_text() == "abc\n"
    assert "vm_host_user: tb" in (a / "group_vars" / "vm_host" / "creds.yml").read_text()
    assert PY in (a / "host_vars" / "STR-ACS-VSERV-01.yml").read_text()
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_configure_sonic_mgmt.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'configure_sonic_mgmt'`.

- [ ] **Step 3: Write `configure_sonic_mgmt.py`**

```python
#!/usr/bin/env python3
"""Apply the KVM testbed settings of the upstream guide to a sonic-mgmt tree.

usage: configure_sonic_mgmt.py <sonic-mgmt dir> <vm host user> <vm host password>
"""
import re
import sys
from pathlib import Path

PY = "ansible_python_interpreter: /usr/bin/python3"


def set_creds(text, user, password):
    for key, value in (("vm_host_user", user), ("vm_host_password", password), ("vm_host_become_password", password)):
        text, count = re.subn(r"(?m)^%s:.*$" % key, "%s: %s" % (key, value), text)
        if count != 1:
            raise ValueError("expected one %s line, found %d" % (key, count))
    return text


def set_inventory(text, user):
    text = re.sub(r"(?m)^([ \t]+)ansible_user: admin\n(?!\1%s)" % re.escape(PY),
                  lambda m: "%sansible_user: admin\n%s%s\n" % (m.group(1), m.group(1), PY), text)
    return re.sub(r"(?m)^([ \t]+)(ansible_user|vm_host_user): use_own_value$",
                  lambda m: "%s%s: %s" % (m.group(1), m.group(2), user), text)


def set_server(text):
    return text if PY in text else text.rstrip("\n") + "\n\n" + PY + "\n"


def main(root, user, password):
    ansible = Path(root) / "ansible"
    for creds in (ansible / "group_vars/all/creds.yml", ansible / "group_vars/vm_host/creds.yml"):
        creds.write_text(set_creds(creds.read_text(), user, password))
    inventory = ansible / "veos_vtb"
    inventory.write_text(set_inventory(inventory.read_text(), user))
    server = ansible / "host_vars/STR-ACS-VSERV-01.yml"
    server.write_text(set_server(server.read_text()))
    (ansible / "password.txt").write_text("abc\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
```

- [ ] **Step 4: Run the tests to see them pass, then check the real tree**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_configure_sonic_mgmt.py`
Expected: `5 passed`.

Then apply it to a clean copy of the pinned sonic-mgmt and compare with the settings that worked on 2026-11-19:

```bash
d=$(mktemp -d) && git -C ~/scratch/pr2-split/run2 archive a88d1d5f9323833d8cf2e050c84904deb22ed3bc ansible | tar -x -C $d
python3 ~/scratch/wt-t0/.github/testflinger/t0/configure_sonic_mgmt.py $d tb pw
diff <(git -C ~/scratch/pr2-split/run2 diff -U0 -- ansible/veos_vtb | grep '^[+-] ' | sed 's/sheldon-qi/tb/') \
     <(diff -U0 <(git -C ~/scratch/pr2-split/run2 show a88d1d5f9323833d8cf2e050c84904deb22ed3bc:ansible/veos_vtb) $d/ansible/veos_vtb | grep '^[+-] ')
rm -rf $d
```

Expected: no output, or only extra `+ … ansible_python_interpreter: /usr/bin/python3` lines under DUT hosts other than `vlab-01` (harmless: the t0 testbed uses `vlab-01` only). The `vlab-01` interpreter line and the two `STR-ACS-VSERV-01` user lines must match the 2026-11-19 tree.

- [ ] **Step 5: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/configure_sonic_mgmt.py .github/testflinger/t0/tests/test_configure_sonic_mgmt.py
git -C $W commit -m "test: apply the KVM testbed settings to a sonic-mgmt tree

The VM host login, python3 for the DUT hosts and the server, and the
git-ignored vault password file: the edits the upstream vs testbed
guide asks for, matching the tree used on 2026-11-19.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Job template and agent side

**Files:**
- Create: `.github/testflinger/t0/job.yaml.in`
- Create: `.github/testflinger/t0/render_job.py`
- Create: `.github/testflinger/t0/agent.sh`
- Test: `.github/testflinger/t0/tests/test_render_job.py`
- Test: `.github/testflinger/t0/tests/test_shell_syntax.py`

**Interfaces:**
- Produces: `render_job.render(sha12, gh_run, image_url, image_sha256, scope, ghcr_user) -> str`; CLI `render_job.py --sha12 --gh-run --image-url --image-sha256 --scope --ghcr-user` (job YAML on stdout). `agent.sh` reads `DEVICE_IP`, `GHCR_TOKEN`, `IMAGE_URL`, `IMAGE_SHA256`, `SCOPE`, `GHCR_USER`; expects `attachments/test/t0-harness.tar.gz`; writes `artifacts/{results.tar.zst,run-meta.json,run-t0.log,host-setup.log}`; exits with the harness exit code.
- Consumes (from Task 6, on the machine): `~/t0/run-t0.sh` writes `~/t0-out/progress.log` and `~/t0-out/EXIT`.

- [ ] **Step 1: Write the failing tests**

`.github/testflinger/t0/tests/test_render_job.py`:

```python
import subprocess

import pytest
import yaml

import render_job

ARGS = dict(sha12="0123456789ab", gh_run="42",
            image_url="https://github.com/canonical/sonic-buildimage/releases/download/t0-images/sonic-vs-0123456789ab.img.gz",
            image_sha256="a" * 64, scope="smoke", ghcr_user="xdqi")


def test_render_gives_a_valid_job():
    job = yaml.safe_load(render_job.render(**ARGS))
    assert job["job_queue"] == "sonic-ci-large"
    assert job["global_timeout"] == 43200 and job["output_timeout"] == 7200
    assert job["provision_data"] == {"distro": "resolute"}
    assert job["test_data"]["secrets"] == {"GHCR_TOKEN": "sonic-buildimage/ghcr-read-token"}
    assert job["test_data"]["attachments"] == [{"local": "t0-harness.tar.gz"}]
    assert "sha:0123456789ab" in job["tags"] and "gh-run:42" in job["tags"]
    cmds = job["test_data"]["test_cmds"]
    assert "SCOPE='smoke'" in cmds and ARGS["image_url"] in cmds
    subprocess.run(["bash", "-n"], input=cmds, text=True, check=True)


@pytest.mark.parametrize("field,value", [("scope", "all"), ("image_url", "http://example.com/x"),
                                         ("image_url", "https://example.com/it's"), ("sha12", "XYZ"),
                                         ("image_sha256", "abc"), ("gh_run", "12a"), ("ghcr_user", "a b")])
def test_render_rejects_bad_values(field, value):
    with pytest.raises(ValueError):
        render_job.render(**dict(ARGS, **{field: value}))
```

`.github/testflinger/t0/tests/test_shell_syntax.py`:

```python
import subprocess
from pathlib import Path

import pytest

T0 = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("script", sorted(p.name for p in T0.glob("*.sh")))
def test_shell_syntax(script):
    subprocess.run(["bash", "-n", str(T0 / script)], check=True)
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_render_job.py .github/testflinger/t0/tests/test_shell_syntax.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'render_job'` (the shell test collects no cases yet).

- [ ] **Step 3: Write the template, the renderer and `agent.sh`**

`.github/testflinger/t0/job.yaml.in`:

```yaml
job_queue: sonic-ci-large
global_timeout: 43200
output_timeout: 7200
tags:
  - sonic-buildimage-t0
  - "sha:${SHA12}"
  - "gh-run:${GH_RUN}"
provision_data:
  distro: resolute
test_data:
  attachments:
    - local: t0-harness.tar.gz
  secrets:
    GHCR_TOKEN: sonic-buildimage/ghcr-read-token
  test_cmds: |
    set -u
    mkdir -p t0 && tar -xzf attachments/test/t0-harness.tar.gz -C t0
    IMAGE_URL='${IMAGE_URL}' IMAGE_SHA256='${IMAGE_SHA256}' SCOPE='${SCOPE}' GHCR_USER='${GHCR_USER}' bash t0/agent.sh
```

`.github/testflinger/t0/render_job.py`:

```python
#!/usr/bin/env python3
"""Render job.yaml.in into a Testflinger job file on stdout."""
import argparse
import re
import string
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent / "job.yaml.in"


def render(sha12, gh_run, image_url, image_sha256, scope, ghcr_user):
    checks = [(re.fullmatch(r"[0-9a-f]{12}", sha12), "sha12"), (re.fullmatch(r"\d+", gh_run), "gh-run"),
              (re.fullmatch(r"https://[^'\s]+", image_url), "image-url"),
              (re.fullmatch(r"[0-9a-f]{64}", image_sha256), "image-sha256"),
              (scope in ("full", "smoke"), "scope"), (re.fullmatch(r"[A-Za-z0-9-]+", ghcr_user), "ghcr-user")]
    for ok, name in checks:
        if not ok:
            raise ValueError("invalid --%s" % name)
    return string.Template(TEMPLATE.read_text()).substitute(
        SHA12=sha12, GH_RUN=gh_run, IMAGE_URL=image_url, IMAGE_SHA256=image_sha256, SCOPE=scope, GHCR_USER=ghcr_user)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for opt in ("--sha12", "--gh-run", "--image-url", "--image-sha256", "--scope", "--ghcr-user"):
        parser.add_argument(opt, required=True)
    a = parser.parse_args(argv)
    sys.stdout.write(render(a.sha12, a.gh_run, a.image_url, a.image_sha256, a.scope, a.ghcr_user))


if __name__ == "__main__":
    main()
```

`.github/testflinger/t0/agent.sh`:

```bash
#!/bin/bash
# Agent side of the resolute t0 job: start the harness detached on the machine, relay progress, fetch the results.
set -u
opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=30
      -o ServerAliveInterval=60 -o LogLevel=ERROR)
m=ubuntu@$DEVICE_IP
on() { ssh "${opts[@]}" "$m" "$@"; }
mkdir -p artifacts
scp "${opts[@]}" attachments/test/t0-harness.tar.gz "$m:t0-harness.tar.gz" || exit 1
on 'rm -rf t0 t0-out && mkdir -p t0 t0-out && tar -xzf t0-harness.tar.gz -C t0' || exit 1
# The token reaches the detached harness through stdin and its environment, never a command line.
printf '%s\n' "${GHCR_TOKEN:-}" | on "read -r GHCR_TOKEN; export GHCR_TOKEN IMAGE_URL='$IMAGE_URL' \
IMAGE_SHA256='$IMAGE_SHA256' SCOPE='$SCOPE' GHCR_USER='$GHCR_USER'; \
setsid nohup bash t0/run-t0.sh > t0-out/run-t0.log 2>&1 < /dev/null &" || exit 1
seen=0
while :; do
    sleep 60
    finished=no
    on 'test -e t0-out/EXIT' && finished=yes
    if new=$(on "tail -n +$((seen + 1)) t0-out/progress.log 2>/dev/null") && [ -n "$new" ]; then
        printf '%s\n' "$new"
        seen=$((seen + $(printf '%s\n' "$new" | wc -l)))
    fi
    [ "$finished" = yes ] && break
done
for f in results.tar.zst run-meta.json run-t0.log host-setup.log; do
    scp "${opts[@]}" "$m:t0-out/$f" artifacts/ || true
done
rc=$(on 'cat t0-out/EXIT' 2>/dev/null)
exit "${rc:-1}"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests`
Expected: `35 passed` (21 + 5 + 8 render cases + 1 shell syntax case).

- [ ] **Step 5: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/job.yaml.in .github/testflinger/t0/render_job.py .github/testflinger/t0/agent.sh \
    .github/testflinger/t0/tests/test_render_job.py .github/testflinger/t0/tests/test_shell_syntax.py
git -C $W commit -m "test: Testflinger job template and agent side of the t0 run

The harness runs detached on the machine so an SSH drop cannot end the
run; the agent relays progress.log every minute, which also keeps the
output timeout quiet. GHCR_TOKEN goes over stdin into the harness
environment. Template values are validated, so none can carry a quote
into test_cmds.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Machine side — host setup, testbed worker, entry script, data files

**Files:**
- Create: `.github/testflinger/t0/host-setup.sh`
- Create: `.github/testflinger/t0/tb-run.sh`
- Create: `.github/testflinger/t0/run-t0.sh`
- Create: `.github/testflinger/t0/known-failures.yaml`
- Create: `.github/testflinger/t0/sonic-mgmt.ref`
- Create: `.github/testflinger/t0/smoke.txt`
- Test: `.github/testflinger/t0/tests/test_shell_syntax.py` (already parametrised over `*.sh`)

**Interfaces:**
- Consumes: `make_chunks.py` CLI (Task 1); `verdict.py rerun-files` (Task 3); `configure_sonic_mgmt.py` CLI (Task 4); env from `agent.sh` (Task 5).
- Produces: `host-setup.sh` prints `TESTBEDS=<n>`, `VCPU=<n>`, `POOL=<name>` as its last lines; `run-t0.sh` writes `~/t0-out/{progress.log,host-setup.log,tb-<i>.log,files.txt,run-meta.json,results.tar.zst,EXIT}`; `run-meta.json` keys `machine, testbeds, image_url, image_sha256, sonic_mgmt, scope, files, phases, time_guard, rc, phase`; results under `/srv/queue/results/<label>/<NNN[.retry][.rerun]>/` plus `<NNN[.retry]>.time` = `<start> <end>` epoch seconds of the first run.

- [ ] **Step 1: Write `host-setup.sh`**

```bash
#!/bin/bash
# Prepare the reserved machine for the testbed VMs; the last lines are TESTBEDS=, VCPU= and POOL=.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
S=/srv/share
sudo apt-get update -q
sudo apt-get install -y -q docker.io zfsutils-linux zstd python3-yaml >/dev/null
sudo snap install lxd 2>/dev/null || sudo snap refresh lxd || true
sudo lxc storage show default >/dev/null 2>&1 || sudo lxd init --auto --storage-backend dir
root_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")
spare=$(lsblk -dbn -o NAME,TYPE,SIZE,ROTA | awk -v r="$root_disk" '$2 == "disk" && $1 != r && $3 >= 200e9 && $4 == 0 {print "/dev/" $1}' | xargs)
if [ -n "$spare" ]; then
    # shellcheck disable=SC2086
    sudo zpool list tbpool >/dev/null 2>&1 || sudo zpool create -f tbpool $spare
    echo $((8 << 30)) | sudo tee /sys/module/zfs/parameters/zfs_arc_max >/dev/null
    sudo lxc storage show tb >/dev/null 2>&1 || sudo lxc storage create tb zfs source=tbpool
    pool=tb
    pool_gb=$(( $(sudo zpool list -Hp -o free tbpool) / 1000000000 ))
else
    pool=default
    pool_gb=$(( $(df -B1 --output=avail /var/snap/lxd/common/lxd/storage-pools/default | tail -1) / 1000000000 ))
fi
# VM memory is shmem on the host and the VM limits nearly fill RAM.
[ -f /swapfile-host ] || { sudo fallocate -l 64G /swapfile-host && sudo chmod 600 /swapfile-host && sudo mkswap /swapfile-host >/dev/null; }
swapon --show | grep -q /swapfile-host || sudo swapon /swapfile-host
# docker sets the FORWARD policy to DROP, which leaves the LXD VMs without network.
sudo iptables -C DOCKER-USER -i lxdbr0 -j ACCEPT 2>/dev/null || sudo iptables -I DOCKER-USER -i lxdbr0 -j ACCEPT
sudo iptables -C DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I DOCKER-USER -o lxdbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo mkdir -p $S /srv/queue
sudo chown ubuntu:ubuntu $S
sudo chmod 1777 /srv/queue
proxy=$(cat /etc/apt/apt.conf /etc/apt/apt.conf.d/* 2>/dev/null | grep -oP 'Acquire::http::Proxy "http://\K[^/"]+' | head -1 || true)
[ -n "$proxy" ] || { echo "no apt proxy configured on the host"; exit 1; }
echo "$proxy" > $S/apt-proxy
for img in docker-sonic-mgmt docker-ptf; do
    sudo docker pull -q sonicdev-microsoft.azurecr.io:443/$img:latest
    sudo docker save sonicdev-microsoft.azurecr.io:443/$img:latest -o $S/$img.tar
done
sudo chown ubuntu:ubuntu $S/*.tar
mem=$(free -g | awk '/^Mem:/{print $2}')
cpu=$(nproc)
t=$(( (mem - 16) / 18 ))
if [ $(( cpu / 8 )) -lt $t ]; then t=$(( cpu / 8 )); fi
if [ $(( pool_gb / 40 )) -lt $t ]; then t=$(( pool_gb / 40 )); fi
[ "$t" -ge 1 ] || { echo "machine too small: mem=${mem}G cpu=$cpu pool=${pool_gb}G"; exit 1; }
echo "TESTBEDS=$t"
echo "VCPU=$(( cpu / t ))"
echo "POOL=$pool"
```

- [ ] **Step 2: Write `tb-run.sh`**

```bash
#!/bin/bash
# One vms-kvm-t0 testbed in an LXD VM, then chunks from /srv/queue; usage: tb-run.sh <label> (as root).
set -euxo pipefail
LABEL=$1
U=tb H=/home/tb S=/srv/share Q=/srv/queue TB=vms-kvm-t0 DUT=vlab-01
R=$Q/results/$LABEL
mkdir -p "$R" $Q/claimed $Q/done $Q/finished
current=""
finish() {
    local rc=$?
    if [ -n "$current" ] && [ -f "$Q/claimed/$current.$LABEL" ]; then
        case $current in
            *.retry) mv "$Q/claimed/$current.$LABEL" "$Q/done/$current.$LABEL" ;;
            *) mv "$Q/claimed/$current.$LABEL" "$Q/pending/$current.retry" ;;
        esac
    fi
    echo "$rc" > "$Q/finished/$LABEL"
}
trap finish EXIT
export DEBIAN_FRONTEND=noninteractive
# The LXD VM image keeps a 70G root partition on the 140G disk.
growpart /dev/sda 1 || true
resize2fs /dev/sda1 || true
if ! swapon --show | grep -q /swapfile; then
    fallocate -l 8G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
fi
id $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
set +x
echo "$U:$(cat $S/tb-pass)" | chpasswd
set -x
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U
echo "Acquire::http::Proxy \"http://$(cat $S/apt-proxy)/\";" > /etc/apt/apt.conf.d/90proxy
# vm_set installs docker-ce with apt-key, gone in 26.04, unless a docker apt source already exists.
install -d -m 0755 /etc/apt/keyrings
[ -s /etc/apt/keyrings/docker.asc ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
# A daily upgrade restarts openvswitch, which drops the testbed flows.
systemctl disable --now apt-daily-upgrade.timer apt-daily.timer unattended-upgrades >/dev/null 2>&1 || true
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io libvirt-daemon-system qemu-system-x86 openvswitch-switch \
    bridge-utils j2cli sshpass net-tools ethtool python3-pip python3-yaml xz-utils openssh-server >/dev/null
usermod -aG docker,libvirt,kvm $U
systemctl enable --now ssh docker libvirtd
# ovsdb-server first starts before the ovs-vswitchd alternative exists, and systemd stops retrying.
systemctl reset-failed ovsdb-server ovs-vswitchd openvswitch-switch || true
systemctl restart openvswitch-switch
ovs-vsctl show >/dev/null
mkdir -p $H/sonic-vm/images $H/veos-vm/images
[ -s $H/sonic-vm/images/sonic-vs.img ] || cp $S/sonic-vs.img $H/sonic-vm/images/sonic-vs.img
for t in ceos docker-sonic-mgmt docker-ptf; do docker load -q -i $S/$t.tar; done
docker image inspect publicmirror.azurecr.io:443/debian:trixie >/dev/null 2>&1 || docker pull -q publicmirror.azurecr.io:443/debian:trixie
[ -d $H/sonic-mgmt ] || cp -a $S/sonic-mgmt $H/sonic-mgmt
chown -R $U:$U $H
ip link show br1 >/dev/null 2>&1 || (cd $H/sonic-mgmt/ansible && ./setup-management-network.sh >/dev/null)
docker rm -f sonic-mgmt >/dev/null 2>&1 || true
su - $U -c "cd $H/sonic-mgmt && ./setup-container.sh -n sonic-mgmt -i sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest -d /data" | tail -3
mgmt() { docker exec --user $U sonic-mgmt bash -c "$1"; }
tbcli="cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb"
mgmt "$tbcli add-topo $TB password.txt" > "$R/add-topo.log" 2>&1
mgmt "$tbcli deploy-mg $TB veos_vtb password.txt" > "$R/deploy-mg.log" 2>&1
echo "TESTBED READY $(date -Is)"
run_files() {
    local dir=$1
    shift
    mgmt "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $TB -d $DUT -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -m individual -O -p logs/$dir -c '$*'" \
        > "$H/run_tests.log" 2>&1 || true
    mkdir -p "$R/$dir"
    cp -a "$H/sonic-mgmt/tests/logs/$dir/." "$R/$dir/" 2>/dev/null || true
    cp "$H/run_tests.log" "$R/$dir/run_tests.log"
}
while [ ! -e $Q/STOP ]; do
    current=""
    for p in "$Q"/pending/*; do
        [ -e "$p" ] || continue
        c=${p##*/}
        if mv "$p" "$Q/claimed/$c.$LABEL" 2>/dev/null; then current=$c; break; fi
    done
    [ -n "$current" ] || break
    mapfile -t files < "$Q/claimed/$current.$LABEL"
    start=$(date +%s)
    run_files "$current" "${files[@]}"
    echo "$start $(date +%s)" > "$R/$current.time"
    mapfile -t rerun < <(python3 $S/t0/verdict.py rerun-files --chunk-dir "$R/$current" --known $S/t0/known-failures.yaml)
    if [ "${#rerun[@]}" -gt 0 ]; then
        mgmt "$tbcli deploy-mg $TB veos_vtb password.txt" > "$R/$current.deploy-mg.log" 2>&1 || true
        run_files "$current.rerun" "${rerun[@]}"
    fi
    mv "$Q/claimed/$current.$LABEL" "$Q/done/$current.$LABEL"
    current=""
done
echo "QUEUE DONE $(date -Is)"
```

- [ ] **Step 3: Write `run-t0.sh`**

```bash
#!/bin/bash
# Machine side of the resolute t0 run, started detached by agent.sh; everything lands in ~/t0-out.
set -euo pipefail
T0=$(cd "$(dirname "$0")" && pwd)
OUT=$HOME/t0-out S=/srv/share Q=/srv/queue
CEOS=ghcr.io/canonical/sonic-ceos:4.32.5M-1
MGMT_IMAGE=sonicdev-microsoft.azurecr.io:443/docker-sonic-mgmt:latest
START=$(date +%s)
DISPATCH_STOP=$((START + 37800))
HARD_STOP=$((START + 41400))
mkdir -p "$OUT"
: > "$OUT/progress.log"
phase=start phase_start=$START phases="" testbeds=0 time_guard=false
progress() { echo "$(date -u +%FT%TZ) $*" | tee -a "$OUT/progress.log"; }
enter() {
    local now
    now=$(date +%s)
    [ "$phase" = start ] || phases="$phases $phase=$((now - phase_start))"
    phase=$1 phase_start=$now
    progress "phase $phase"
}
finish() {
    local rc=$? failed=$phase
    set +e
    enter packing
    [ ! -d $Q/results ] || sudo tar -C $Q -cf - results | zstd -19 -T0 -q --force -o "$OUT/results.tar.zst"
    RC=$rc PHASE=$failed PHASES="$phases" TESTBEDS=$testbeds TIME_GUARD=$time_guard MGMT=$(cat "$T0/sonic-mgmt.ref") \
        python3 - "$OUT/files.txt" "$OUT/run-meta.json" <<'EOF'
import json, os, socket, sys
from pathlib import Path
files = Path(sys.argv[1]).read_text().split() if Path(sys.argv[1]).exists() else []
Path(sys.argv[2]).write_text(json.dumps({
    "machine": socket.gethostname(), "testbeds": int(os.environ["TESTBEDS"]),
    "image_url": os.environ.get("IMAGE_URL", ""), "image_sha256": os.environ.get("IMAGE_SHA256", ""),
    "sonic_mgmt": os.environ["MGMT"], "scope": os.environ.get("SCOPE", ""), "files": files,
    "phases": {k: int(v) for k, v in (p.split("=") for p in os.environ["PHASES"].split())},
    "time_guard": os.environ["TIME_GUARD"] == "true", "rc": int(os.environ["RC"]), "phase": os.environ["PHASE"]},
    indent=1))
EOF
    progress "exit $rc"
    echo "$rc" > "$OUT/EXIT"
}
trap finish EXIT
progress "start scope=$SCOPE image=$IMAGE_URL"

enter host-setup
bash "$T0/host-setup.sh" > "$OUT/host-setup.log" 2>&1
TESTBEDS=0 VCPU=0 POOL=default
eval "$(grep -E '^(TESTBEDS|VCPU|POOL)=[A-Za-z0-9_-]+$' "$OUT/host-setup.log")"
testbeds=$TESTBEDS
if [ "$SCOPE" = smoke ] && [ "$testbeds" -gt 2 ]; then testbeds=2; fi
progress "testbeds=$testbeds vcpu=$VCPU pool=$POOL"

enter payload
curl -fsSL --retry 5 -o $S/sonic-vs.img.gz "$IMAGE_URL"
echo "$IMAGE_SHA256  $S/sonic-vs.img.gz" | sha256sum -c -
gunzip -f $S/sonic-vs.img.gz
dc=$(mktemp -d -p /dev/shm)
printf '%s' "$GHCR_TOKEN" | sudo env DOCKER_CONFIG="$dc" docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null
sudo env DOCKER_CONFIG="$dc" docker pull -q $CEOS
sudo rm -rf "$dc"
unset GHCR_TOKEN
sudo docker tag $CEOS ceosimage:4.32.5M-1
sudo docker save ceosimage:4.32.5M-1 -o $S/ceos.tar
sudo chown ubuntu:ubuntu $S/ceos.tar
rm -rf $S/sonic-mgmt
mkdir -p $S/sonic-mgmt
curl -fsSL --retry 5 "https://codeload.github.com/canonical/sonic-mgmt/tar.gz/$(cat "$T0/sonic-mgmt.ref")" | tar -xz -C $S/sonic-mgmt --strip-components=1
openssl rand -hex 12 > $S/tb-pass
python3 "$T0/configure_sonic_mgmt.py" $S/sonic-mgmt tb "$(cat $S/tb-pass)"
rm -rf $S/t0
cp -a "$T0" $S/t0

enter test-list
if [ "$SCOPE" = smoke ]; then
    cp "$T0/smoke.txt" "$OUT/files.txt"
else
    sudo docker run --rm -v $S/sonic-mgmt:/sm:ro -w /sm/.azure-pipelines/impacted_area_testing $MGMT_IMAGE \
        python3 get_test_scripts.py --features "" --location /sm/tests \
        | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["t0_checker"]))' > "$OUT/files.txt"
fi
progress "$(wc -l < "$OUT/files.txt") test files"
sudo rm -rf $Q/pending $Q/claimed $Q/done $Q/finished $Q/results $Q/STOP
mkdir -p $Q/pending $Q/finished
target=3000
if [ "$SCOPE" = smoke ]; then target=1; fi
python3 "$T0/make_chunks.py" "$OUT/files.txt" "$T0/durations.json" $Q/pending $target

enter testbeds
for i in $(seq 1 "$testbeds"); do
    sudo lxc delete -f tb$i >/dev/null 2>&1 || true
    sudo lxc init ubuntu:26.04 tb$i --vm -s "$POOL" -c limits.cpu="$VCPU" -c limits.memory=18GiB -d root,size=140GiB
    sudo lxc config device add tb$i share disk source=$S path=$S readonly=true
    sudo lxc config device add tb$i queue disk source=$Q path=$Q
    sudo lxc start tb$i
done
for i in $(seq 1 "$testbeds"); do
    for _ in $(seq 120); do sudo lxc exec tb$i -- true 2>/dev/null && break; sleep 5; done
    if ! sudo lxc exec tb$i -- true 2>/dev/null; then
        echo "vm did not boot" > $Q/finished/tb$i
        progress "tb$i did not boot"
        continue
    fi
    setsid nohup sudo lxc exec tb$i -- bash $S/t0/tb-run.sh tb$i > "$OUT/tb-$i.log" 2>&1 < /dev/null &
    # Many lxc exec calls at once fail with "transient scope not created".
    sleep 5
done

enter tests
while :; do
    now=$(date +%s)
    progress "chunks pending=$(ls $Q/pending | wc -l) running=$(ls $Q/claimed | wc -l) done=$(ls $Q/done | wc -l); testbeds finished=$(ls $Q/finished | wc -l)/$testbeds"
    if [ "$(ls $Q/finished | wc -l)" -ge "$testbeds" ]; then break; fi
    if [ "$now" -ge $DISPATCH_STOP ] && [ ! -e $Q/STOP ]; then
        touch $Q/STOP
        time_guard=true
        progress "time guard: no new chunks from now on"
    fi
    if [ "$now" -ge $HARD_STOP ]; then
        progress "hard stop: packing the results that exist"
        break
    fi
    sleep 300
done
```

- [ ] **Step 4: Write the data files**

`.github/testflinger/t0/sonic-mgmt.ref`:

```
a88d1d5f9323833d8cf2e050c84904deb22ed3bc
```

`.github/testflinger/t0/smoke.txt`:

```
clock/test_clock.py
syslog/test_cron_health.py
tacacs/test_rw_user.py
arp/test_wr_arp.py
```

`.github/testflinger/t0/known-failures.yaml`:

```yaml
known: []
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

- [ ] **Step 5: Run the tests and shellcheck**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests && python3 -c "import sys; sys.path.insert(0, '.github/testflinger/t0'); import verdict; verdict.Known('.github/testflinger/t0/known-failures.yaml')"`
Expected: `38 passed` (35 + 3 new shell syntax cases) and no error from loading the list.

Run: `docker run --rm -v ~/scratch/wt-t0/.github/testflinger/t0:/t0:ro koalaman/shellcheck:stable -S warning /t0/agent.sh /t0/host-setup.sh /t0/tb-run.sh /t0/run-t0.sh`
Expected: no output. Fix any warning before committing.

- [ ] **Step 6: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/host-setup.sh .github/testflinger/t0/tb-run.sh .github/testflinger/t0/run-t0.sh \
    .github/testflinger/t0/known-failures.yaml .github/testflinger/t0/sonic-mgmt.ref .github/testflinger/t0/smoke.txt
git -C $W commit -m "test: machine side of the t0 run on Testflinger

host-setup.sh, tb-run.sh and run-t0.sh are the 2026-11-10/19 farm
scripts made self-contained: the eight environment traps fixed in
place, VMs on spare SSDs (jasperoid's root disk holds only 10
testbeds), testbeds sized from RAM, threads and pool space, chunks
from a shared queue with a 10.5 h dispatch stop, reruns of uncovered
failures after deploy-mg, and a cEOS pull whose token only lives in
/dev/shm. The smoke list is four short files that all passed on rock
on 2026-11-19. sonic-mgmt is pinned to the head of PR stack #5-#9,
the commit of the 2026-11-19 full run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: One-time setup

**Files:** none in the repository.

**Interfaces:**
- Produces: `ghcr.io/canonical/sonic-ceos:4.32.5M-1` (internal); a classic PAT with `read:packages` in `~/.config/sonic-t0/ghcr-pat` (mode 600); Testflinger secret `sonic-buildimage/ghcr-read-token`; repository secrets `TESTFLINGER_CLIENT_ID` and `TESTFLINGER_SECRET_KEY`; queue `sonic-ci-large` live on the agents.

- [ ] **Step 1: Push the cEOS image**

```bash
export DOCKER_CONFIG=$(mktemp -d)
gh auth token | docker login ghcr.io -u xdqi --password-stdin
docker tag ceosimage:4.32.5M-1 ghcr.io/canonical/sonic-ceos:4.32.5M-1
docker push ghcr.io/canonical/sonic-ceos:4.32.5M-1
docker logout ghcr.io; rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG
gh api /orgs/canonical/packages/container/sonic-ceos --jq .visibility
```

Expected: the push ends with a `4.32.5M-1: digest: sha256:…` line and the last command prints `internal`.

- [ ] **Step 2: Ask the user for the PAT**

Ask the user to open `https://github.com/settings/tokens/new?scopes=read:packages&description=sonic-ci-ghcr-read`, choose a one-year expiry, generate the token, and store it themselves with:

```bash
mkdir -p ~/.config/sonic-t0 && install -m 600 /dev/stdin ~/.config/sonic-t0/ghcr-pat
```

(paste the token, press Enter, then Ctrl-D). Do not ask for the token in chat.

- [ ] **Step 3: Prove the PAT can pull**

```bash
export DOCKER_CONFIG=$(mktemp -d)
docker login ghcr.io -u xdqi --password-stdin < ~/.config/sonic-t0/ghcr-pat
docker pull ghcr.io/canonical/sonic-ceos:4.32.5M-1 | tail -2
docker logout ghcr.io; rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG
```

Expected: `Login Succeeded`, then a `Digest: sha256:…` line. If login fails with a message about classic tokens being blocked by the organization, stop and report to the user: the fallback is a machine account or a GitHub App (spec section 10).

- [ ] **Step 4: Write the Testflinger secret with the CI credentials**

Ask the user to store the CI client id and secret key as `~/.config/sonic-t0/tf-client-id` and `~/.config/sonic-t0/tf-secret-key` (mode 600, same `install -m 600 /dev/stdin` method), then:

```bash
testflinger-cli secret write --client-id "$(cat ~/.config/sonic-t0/tf-client-id)" \
    --secret-key "$(cat ~/.config/sonic-t0/tf-secret-key)" --expire-after -1 \
    sonic-buildimage/ghcr-read-token "$(cat ~/.config/sonic-t0/ghcr-pat)"
```

Expected: exit status 0.

- [ ] **Step 5: Ask the user to add the repository secrets**

The user (a repository admin) adds `TESTFLINGER_CLIENT_ID` and `TESTFLINGER_SECRET_KEY` under Settings → Secrets and variables → Actions of `canonical/sonic-buildimage`. Then check:

```bash
gh secret list -R canonical/sonic-buildimage | grep -E '^TESTFLINGER_(CLIENT_ID|SECRET_KEY)'
```

Expected: both names listed.

- [ ] **Step 6: Check the queue**

```bash
testflinger-cli list-agents --fields name,status --filter-queues sonic-ci-large
```

Expected: the 10 machines (fleetroc, alarmmonkey, alienbunny, kroop, vlacq, cajal, parakarry, smilax, jasperoid, hoodin). If the list is empty, tell the user that the certification team must sync TOR3-DH1 (C3 already has the queue on all 10), and continue with Task 8, which does not need the queue.

---

### Task 8: M1 — smoke run by hand on one machine

**Files:** fixes to Task 5/6 files if the run exposes bugs.

**Interfaces:**
- Consumes: the harness (Tasks 1–6), the PAT (Task 7).

- [ ] **Step 1: Prepare the payload**

```bash
M1=~/scratch/t0-m1 && rm -rf $M1 && mkdir -p $M1/attachments/test
run=$(gh api "repos/canonical/sonic-buildimage/actions/workflows/resolute-build.yml/runs?branch=202605_resolute&event=push&status=success&per_page=1" --jq '.workflow_runs[0].id')
gh run download "$run" -R canonical/sonic-buildimage -n sonic-vs-img -D $M1/img
sha256sum $M1/img/sonic-vs.img.gz | cut -d' ' -f1 > $M1/img.sha256
tar -czf $M1/attachments/test/t0-harness.tar.gz -C ~/scratch/wt-t0/.github/testflinger/t0 --exclude=tests .
echo "build run $run, image $(cat $M1/img.sha256)"
```

- [ ] **Step 2: Reserve alarmmonkey (no reserve phase; 4 h hold)**

Write `~/testflinger-jobs/t0-m1-alarmmonkey.yaml`:

```yaml
job_queue: alarmmonkey
global_timeout: 43200
output_timeout: 8000
provision_data:
  distro: resolute
test_data:
  test_cmds: |
    SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=30"
    $SSH ubuntu@$DEVICE_IP 'uname -a; nproc; free -g | head -2'
    $SSH ubuntu@$DEVICE_IP 'ssh-import-id lp:sheldon-qi gh:xdqi'
    echo "*** HOLD STARTED: ssh ubuntu@$DEVICE_IP ***"
    end=$((SECONDS + 14400))
    while [ $SECONDS -lt $end ]; do sleep 300; echo "hold: $(( (end - SECONDS) / 60 )) min left"; done
```

```bash
cd ~/testflinger-jobs && testflinger-cli submit --quiet t0-m1-alarmmonkey.yaml | tee t0-m1-jobid
```

Poll until the log shows `HOLD STARTED` and note the IP (`testflinger-cli poll $(cat t0-m1-jobid)` in the background, or `testflinger-cli status`).

- [ ] **Step 3: Copy the image and run the agent side from this VM**

```bash
IP=<device ip from the hold line>
scp -o StrictHostKeyChecking=no ~/scratch/t0-m1/img/sonic-vs.img.gz ubuntu@$IP:sonic-vs.img.gz
cd ~/scratch/t0-m1 && DEVICE_IP=$IP GHCR_TOKEN=$(cat ~/.config/sonic-t0/ghcr-pat) \
  IMAGE_URL=file:///home/ubuntu/sonic-vs.img.gz IMAGE_SHA256=$(cat img.sha256) SCOPE=smoke GHCR_USER=xdqi \
  bash ~/scratch/wt-t0/.github/testflinger/t0/agent.sh > agent.log 2>&1; echo "agent exit $?"
```

Run it in the background (`run_in_background`); it prints a progress line every 5 minutes and ends in about 40–60 minutes.

- [ ] **Step 4: Judge the result**

```bash
cd ~/scratch/t0-m1 && rm -rf results && mkdir results && zstd -dc artifacts/results.tar.zst | tar -x -C results --strip-components=1
python3 ~/scratch/wt-t0/.github/testflinger/t0/verdict.py report --results results \
  --known ~/scratch/wt-t0/.github/testflinger/t0/known-failures.yaml --meta artifacts/run-meta.json \
  --out-json summary.json --out-md report.md --out-durations durations.json
cat report.md; ls results; jq '.files, .testbeds, .rc, .phases' artifacts/run-meta.json
```

Expected (M1 acceptance): `agent exit 0`; `results/` has `tb1` and `tb2`, each with at least one chunk directory; every file of `smoke.txt` has a JUnit result (no "Files not run"); the outcome is `Pass`. A smoke file that fails is analysed: either a harness bug (fix it, commit, and repeat Step 3 — `run-t0.sh` is safe to rerun on the same machine) or a real image failure (record it for the Task 11 list).

- [ ] **Step 5: Commit any fixes and report**

Commit each harness fix separately with a `test:` message stating the observed failure. Report to the user: the outcome, the phase times from `run-meta.json`, and that the alarmmonkey hold (job id in `~/testflinger-jobs/t0-m1-jobid`) is still running until they say to release it.

---

### Task 9: The workflow

**Files:**
- Create: `.github/workflows/resolute-t0.yml`

**Interfaces:**
- Consumes: `render_job.py` CLI, `verdict.py report` CLI, `known-failures.yaml`, the Testflinger secrets and repository secrets from Task 7.
- Produces: commit status `resolute-t0`; job summary; workflow artifact `resolute-t0-<sha12>-<attempt>` containing `summary.json`, `report.md`, `durations.json`, `artifacts/`; release assets in `t0-images`; the PR comment marked `<!-- resolute-t0 -->`.

- [ ] **Step 1: Write the workflow**

```yaml
name: resolute-t0

on:
  schedule:
    - cron: "0 15 * * *"
  workflow_run:
    workflows: [resolute-build]
    types: [completed]
  issue_comment:
    types: [created]
  workflow_dispatch:
    inputs:
      run_id:
        description: resolute-build run id to test (empty = latest successful push build of 202605_resolute)
        type: string
        default: ""
      scope:
        description: Test list
        type: choice
        options: [full, smoke]
        default: full
  push:
    branches: ["ci-workflow/t0-*"]

permissions:
  actions: read
  contents: write
  issues: write
  pull-requests: write
  statuses: write

env:
  GH_TOKEN: ${{ github.token }}
  REPO: ${{ github.repository }}
  GHCR_USER: xdqi

jobs:
  resolve:
    if: >-
      github.event_name != 'issue_comment' ||
      (github.event.issue.pull_request && startsWith(github.event.comment.body, '/test-t0'))
    runs-on: ubuntu-latest
    outputs:
      run_id: ${{ steps.r.outputs.run_id }}
      sha: ${{ steps.r.outputs.sha }}
      sha12: ${{ steps.r.outputs.sha12 }}
      status_sha: ${{ steps.r.outputs.status_sha }}
      known_ref: ${{ steps.r.outputs.known_ref }}
      scope: ${{ steps.r.outputs.scope }}
      pr: ${{ steps.r.outputs.pr }}
    steps:
      - name: Pick the build to test
        id: r
        env:
          EVENT: ${{ github.event_name }}
          WR_ID: ${{ github.event.workflow_run.id }}
          WR_OK: ${{ github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && (github.event.workflow_run.head_branch == '202605_resolute' || startsWith(github.event.workflow_run.head_branch, 'v')) }}
          IN_RUN: ${{ inputs.run_id }}
          IN_SCOPE: ${{ inputs.scope }}
          PR: ${{ github.event.issue.number }}
          COMMENT_ID: ${{ github.event.comment.id }}
          COMMENT: ${{ github.event.comment.body }}
          COMMENTER: ${{ github.event.comment.user.login }}
        run: |
          set -euo pipefail
          latest_push_build() {
            gh api "repos/$REPO/actions/workflows/resolute-build.yml/runs?branch=202605_resolute&event=push&status=success&per_page=1" \
              --jq '.workflow_runs[0].id // empty'
          }
          run_id="" scope=full pr="" known_ref="" status_sha=""
          say() { [ -z "$pr" ] || gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="resolute-t0: $1" >/dev/null; echo "$1"; }
          case "$EVENT" in
            workflow_run)
              if [ "$WR_OK" != true ]; then echo "not a successful push or tag build; nothing to test"; exit 0; fi
              run_id=$WR_ID ;;
            schedule) run_id=$(latest_push_build) ;;
            workflow_dispatch) run_id=${IN_RUN:-$(latest_push_build)}; scope=$IN_SCOPE ;;
            push)
              run_id=$(latest_push_build); known_ref=$GITHUB_SHA; status_sha=$GITHUB_SHA
              case "$GITHUB_REF_NAME" in ci-workflow/t0-full-*) scope=full ;; *) scope=smoke ;; esac ;;
            issue_comment)
              perm=$(gh api "repos/$REPO/collaborators/$COMMENTER/permission" --jq .permission 2>/dev/null || echo none)
              case "$perm" in admin|maintain|write) ;; *) echo "$COMMENTER has $perm permission; ignoring the comment"; exit 0 ;; esac
              gh api -X POST "repos/$REPO/issues/comments/$COMMENT_ID/reactions" -f content=eyes >/dev/null
              pr=$PR
              case "$(printf '%s\n' "$COMMENT" | head -1)" in *smoke*) scope=smoke ;; esac
              head=$(gh api "repos/$REPO/pulls/$PR" --jq .head.sha)
              run_id=$(gh api "repos/$REPO/actions/workflows/resolute-build.yml/runs?head_sha=$head&status=success&per_page=1" \
                --jq '.workflow_runs[0].id // empty')
              [ -n "$run_id" ] || { say "no successful resolute-build run for \`${head:0:12}\` yet; nothing to test."; exit 0; } ;;
          esac
          [ -n "$run_id" ] || { echo "no build to test"; exit 0; }
          sha=$(gh api "repos/$REPO/actions/runs/$run_id" --jq .head_sha)
          art=$(gh api "repos/$REPO/actions/runs/$run_id/artifacts" \
            --jq '[.artifacts[] | select(.name == "sonic-vs-img" and (.expired | not))][0].id // empty')
          [ -n "$art" ] || { say "build run $run_id has no unexpired sonic-vs-img artifact; nothing to test."; exit 0; }
          {
            echo "run_id=$run_id"; echo "sha=$sha"; echo "sha12=${sha:0:12}"; echo "scope=$scope"; echo "pr=$pr"
            echo "known_ref=${known_ref:-$sha}"; echo "status_sha=${status_sha:-$sha}"
          } >> "$GITHUB_OUTPUT"

  t0:
    needs: resolve
    if: needs.resolve.outputs.run_id != ''
    runs-on: [self-hosted-linux-amd64-noble-private-endpoint-small]
    timeout-minutes: 1440
    concurrency:
      group: resolute-t0-${{ needs.resolve.outputs.sha }}
      cancel-in-progress: false
    env:
      RUN_ID: ${{ needs.resolve.outputs.run_id }}
      SHA12: ${{ needs.resolve.outputs.sha12 }}
      STATUS_SHA: ${{ needs.resolve.outputs.status_sha }}
      KNOWN_REF: ${{ needs.resolve.outputs.known_ref }}
      SCOPE: ${{ needs.resolve.outputs.scope }}
      PR: ${{ needs.resolve.outputs.pr }}
      RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
      T0: .github/testflinger/t0
    steps:
      - uses: actions/checkout@v4
        with:
          sparse-checkout: .github

      - name: Install tools
        run: |
          missing=()
          command -v gh >/dev/null || missing+=(gh)
          command -v zstd >/dev/null || missing+=(zstd)
          python3 -c 'import yaml, pytest' 2>/dev/null || missing+=(python3-yaml python3-pytest)
          [ "${#missing[@]}" -eq 0 ] || { sudo apt-get update -q && sudo apt-get install -y -q "${missing[@]}"; }

      - name: Unit tests of the harness
        run: python3 -m pytest -q "$T0/tests"

      - name: Mark the commit pending
        run: |
          gh api -X POST "repos/$REPO/statuses/$STATUS_SHA" -f state=pending -f context=resolute-t0 \
            -f target_url="$RUN_URL" -f description="t0 ($SCOPE) on Testflinger: running" >/dev/null

      - name: Download the vs image
        uses: actions/download-artifact@v4
        with:
          name: sonic-vs-img
          run-id: ${{ env.RUN_ID }}
          github-token: ${{ github.token }}
          path: img

      - name: Publish the image as a release asset
        id: img
        run: |
          set -euo pipefail
          name=sonic-vs-$SHA12.img.gz
          mv img/sonic-vs.img.gz "$name"
          sha256sum "$name" | cut -d' ' -f1 > "$name.sha256"
          gh release view t0-images -R "$REPO" >/dev/null 2>&1 || gh release create t0-images -R "$REPO" --prerelease \
            --title "t0 test images" --notes "vs images under test by the resolute-t0 workflow; only the newest 10 are kept."
          gh release upload t0-images -R "$REPO" --clobber "$name" "$name.sha256"
          gh api "repos/$REPO/releases/tags/t0-images" \
            --jq '[.assets[] | select(.name | endswith(".img.gz"))] | sort_by(.created_at) | reverse | .[10:][] | .name' |
            while read -r old; do
              gh release delete-asset t0-images "$old" -R "$REPO" -y
              gh release delete-asset t0-images "$old.sha256" -R "$REPO" -y || true
            done
          echo "url=https://github.com/$REPO/releases/download/t0-images/$name" >> "$GITHUB_OUTPUT"
          echo "sha256=$(cat "$name.sha256")" >> "$GITHUB_OUTPUT"
          rm -f "$name" "$name.sha256"

      - name: Chunk durations from the latest nightly run
        run: |
          set -uo pipefail
          echo '{}' > durations.json
          for id in $(gh run list -R "$REPO" -w resolute-t0.yml -e schedule -s completed -L 5 --json databaseId --jq '.[].databaseId'); do
            rm -rf prev
            if gh run download "$id" -R "$REPO" -p 'resolute-t0-*' -D prev 2>/dev/null; then
              f=$(find prev -name durations.json -size +2c | head -1)
              if [ -n "$f" ]; then cp "$f" durations.json; echo "durations from run $id"; break; fi
            fi
          done

      - name: Pack the harness and render the job
        env:
          IMAGE_URL: ${{ steps.img.outputs.url }}
          IMAGE_SHA256: ${{ steps.img.outputs.sha256 }}
        run: |
          set -euo pipefail
          rm -rf pack && mkdir pack
          cp -a "$T0/." pack/
          rm -rf pack/tests
          if gh api "repos/$REPO/contents/$T0/known-failures.yaml?ref=$KNOWN_REF" --jq .content > kf.b64 2>/dev/null; then
            base64 -d kf.b64 > pack/known-failures.yaml
          fi
          cp durations.json pack/durations.json
          tar -czf t0-harness.tar.gz -C pack .
          python3 "$T0/render_job.py" --sha12 "$SHA12" --gh-run "$GITHUB_RUN_ID" --image-url "$IMAGE_URL" \
            --image-sha256 "$IMAGE_SHA256" --scope "$SCOPE" --ghcr-user "$GHCR_USER" > job.yaml
          cat job.yaml

      - name: Run on Testflinger
        id: tf
        continue-on-error: true
        uses: canonical/testflinger/.github/actions/submit@257ef71c8042a41925d7185d46fc3171ea2112f5 # submit/v1.6.0
        with:
          poll: true
          job-path: job.yaml
          retries: 2
          client-id: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          secret-key: ${{ secrets.TESTFLINGER_SECRET_KEY }}

      - name: Fetch the Testflinger results
        if: always() && steps.tf.outputs.id != ''
        env:
          TESTFLINGER_CLIENT_ID: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          TESTFLINGER_SECRET_KEY: ${{ secrets.TESTFLINGER_SECRET_KEY }}
          JOB_ID: ${{ steps.tf.outputs.id }}
        run: |
          set -uo pipefail
          mkdir -p out/results
          testflinger results "$JOB_ID" > out/tf-results.json || true
          if testflinger artifacts --filename out/artifacts.tgz "$JOB_ID"; then
            tar -xzf out/artifacts.tgz -C out && rm -f out/artifacts.tgz
          fi
          if [ -f out/artifacts/results.tar.zst ]; then
            zstd -dc out/artifacts/results.tar.zst | tar -x -C out/results --strip-components=1
          fi

      - name: Judge
        id: verdict
        if: always()
        env:
          JOB_ID: ${{ steps.tf.outputs.id }}
        run: |
          set -uo pipefail
          mkdir -p out/results
          infra=""
          if [ -z "$JOB_ID" ]; then
            infra="the Testflinger job was not submitted"
          elif [ "$(jq -r '.provision_status // 1' out/tf-results.json 2>/dev/null)" != 0 ]; then
            infra="provisioning failed after the retries"
          fi
          args=()
          [ ! -f out/artifacts/run-meta.json ] || args+=(--meta out/artifacts/run-meta.json)
          [ -z "$infra" ] || args+=(--infra "$infra")
          known=pack/known-failures.yaml
          [ -f "$known" ] || known=$T0/known-failures.yaml
          python3 "$T0/verdict.py" report --results out/results --known "$known" "${args[@]}" \
            --out-json out/summary.json --out-md out/report.md --out-durations out/durations.json
          cat out/report.md >> "$GITHUB_STEP_SUMMARY"
          echo "state=$(jq -r .state out/summary.json)" >> "$GITHUB_OUTPUT"
          echo "description=$(jq -r .description out/summary.json)" >> "$GITHUB_OUTPUT"

      - name: Upload the results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: resolute-t0-${{ env.SHA12 }}-${{ github.run_attempt }}
          path: |
            out/summary.json
            out/report.md
            out/durations.json
            out/artifacts/
          retention-days: 30
          if-no-files-found: warn

      - name: Report
        if: always()
        env:
          STATE: ${{ steps.verdict.outputs.state }}
          DESC: ${{ steps.verdict.outputs.description }}
        run: |
          set -uo pipefail
          state=${STATE:-error}
          desc=${DESC:-"resolute-t0 did not finish (cancelled or timed out)"}
          gh api -X POST "repos/$REPO/statuses/$STATUS_SHA" -f state="$state" -f context=resolute-t0 \
            -f target_url="$RUN_URL" -f description="${desc:0:140}" >/dev/null
          if [ -n "$PR" ]; then
            body="<!-- resolute-t0 -->"$'\n'"$(cat out/report.md 2>/dev/null || echo "$desc")"$'\n\n'"[Workflow run]($RUN_URL)"
            cid=$(gh api "repos/$REPO/issues/$PR/comments" --paginate \
              --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- resolute-t0 -->"))) | .id' | tail -1)
            if [ -n "$cid" ]; then
              gh api -X PATCH "repos/$REPO/issues/comments/$cid" -f body="${body:0:65000}" >/dev/null
            else
              gh api -X POST "repos/$REPO/issues/$PR/comments" -f body="${body:0:65000}" >/dev/null
            fi
          fi
          [ "$state" = success ]
```

- [ ] **Step 2: Lint the workflow**

Run: `docker run --rm -v ~/scratch/wt-t0:/repo:ro -w /repo rhysd/actionlint:latest -ignore 'label "self-hosted-linux-amd64-noble-private-endpoint-small" is unknown' .github/workflows/resolute-t0.yml`
Expected: no output. Fix every finding (shellcheck findings inside `run:` blocks included) before committing.

- [ ] **Step 3: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/workflows/resolute-t0.yml
git -C $W commit -m "test: run sonic-mgmt t0 on Testflinger nightly, after builds and on /test-t0

One job on the small self-hosted runner follows the Testflinger job to
the end (self-hosted jobs may run 5 days; the 24 h timeout bounds the
queue wait). Comment triggers need write access, checked with the
collaborator permission API because event payloads show private org
members as CONTRIBUTOR. The machine-side scripts come from the default
branch; only the image and known-failures.yaml come from the commit
under test. ci-workflow/t0-* pushes run the smoke list for development.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: M2 — the workflow end to end, smoke

**Files:** fixes to Task 5/6/9 files if the run exposes bugs (committed on `feat/resolute-t0-testflinger`).

**Interfaces:**
- Consumes: Tasks 1–9 and the setup of Task 7, including the `sonic-ci-large` queue on the agents.

- [ ] **Step 1: Push a development branch without the build workflow**

```bash
W=~/scratch/wt-t0
git -C $W checkout -q -b ci-workflow/t0-m2
git -C $W rm -q .github/workflows/resolute-build.yml
git -C $W commit -q -m "test: development branch for the t0 workflow (drop resolute-build so the push does not build)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C $W push -q canonical ci-workflow/t0-m2
git -C $W checkout -q feat/resolute-t0-testflinger
gh run list -R canonical/sonic-buildimage --branch ci-workflow/t0-m2 -L 3
```

Expected: one `resolute-t0` run, no `resolute-build` run.

- [ ] **Step 2: Follow the run**

`gh run watch <id> -R canonical/sonic-buildimage` in the background. The `t0` job waits about 9 minutes for a runner, then about 20 minutes for provisioning and about 40 minutes for the smoke run. Do not cancel it without asking the user (AGENTS.md).

- [ ] **Step 3: Check M2 acceptance**

```bash
c=$(git -C ~/scratch/wt-t0 rev-parse ci-workflow/t0-m2)
gh api repos/canonical/sonic-buildimage/commits/$c/statuses --jq '.[] | select(.context == "resolute-t0") | .state + " " + .description' | head -2
gh run view <id> -R canonical/sonic-buildimage --json jobs --jq '.jobs[] | .name + " " + .conclusion'
gh run download <id> -R canonical/sonic-buildimage -D ~/scratch/t0-m2 && ls -R ~/scratch/t0-m2 | head -30
```

Expected: a `resolute-t0` status (`success`, plus the earlier `pending`) on the pushed commit; the job summary shows the report; the artifact holds `summary.json`, `report.md`, `durations.json` and `artifacts/{results.tar.zst,run-meta.json,run-t0.log,host-setup.log}`; `summary.json` agrees with `report.md` and with the Testflinger job's output.

- [ ] **Step 4: Fix, then clean up**

Commit each fix on `feat/resolute-t0-testflinger` and rebase `ci-workflow/t0-m2` on it to retest. When M2 passes, delete the branch:

```bash
git -C ~/scratch/wt-t0 push -q canonical --delete ci-workflow/t0-m2
git -C ~/scratch/wt-t0 branch -D ci-workflow/t0-m2
```

---

### Task 11: M3 — full run and the first known-failures list

**Files:**
- Modify: `.github/testflinger/t0/known-failures.yaml`

**Interfaces:**
- Consumes: the workflow (Task 9); the 2026-11-19 rock results in `~/scratch/pr2-split/farm/analysis/rock-*` and `~/scratch/pr2-split/farm/compare-full-a88d1d5f9.txt`.

- [ ] **Step 1: Start the full run**

Same as Task 10 Step 1, with branch `ci-workflow/t0-full-m3` (the name selects `scope=full`). Follow it in the background; expected wall time 4–6 hours after provisioning.

- [ ] **Step 2: Check M3 acceptance and collect the failures**

```bash
gh run download <id> -R canonical/sonic-buildimage -D ~/scratch/t0-m3
jq '.outcome, .totals, .meta.phases, .meta.testbeds, (.new | length)' ~/scratch/t0-m3/*/summary.json
jq -r '.new[] | "\(.outcome)\t\(.id)\t\(.message)"' ~/scratch/t0-m3/*/summary.json > ~/scratch/t0-m3/new.tsv
wc -l ~/scratch/t0-m3/new.tsv
```

Expected: the tests phase finished within 6 hours on a 16-testbed machine (fewer testbeds scale the time up proportionally); `.totals` is close to the 2026-11-19 rock run (1219 passed, 2654 skipped, 31 failed, 17 setup errors).

- [ ] **Step 3: Write the first list**

For every line of `new.tsv`, compare with the 2026-11-19 rock result of the same case (`compare-full-a88d1d5f9.txt` and `farm/analysis/rock-*`). Then:
- a case that also failed on 2026-11-19 for the same reason becomes an entry with `kind: fail` or `error` and an English `reason` taken from the 2026-11-19 analysis (for example `"Process monitoring: rock stops the container when a critical service exits (PR #28 behaviour)"`);
- a parametrised family with random parameters becomes one `*` entry with `kind: flaky` (the 14 `generic_hash` cases);
- a case that did not fail on 2026-11-19 is investigated before it goes into the list: a new image or environment problem gets a written reason, or it is fixed first.

Run `python3 -m pytest -q .github/testflinger/t0/tests` and re-judge the downloaded M3 results locally with the new list:

```bash
cd ~/scratch/t0-m3 && mkdir -p results && zstd -dc */artifacts/results.tar.zst | tar -x -C results --strip-components=1
python3 ~/scratch/wt-t0/.github/testflinger/t0/verdict.py report --results results \
  --known ~/scratch/wt-t0/.github/testflinger/t0/known-failures.yaml --meta */artifacts/run-meta.json \
  --out-json s.json --out-md r.md --out-durations d.json && jq '.outcome, (.new | length)' s.json
```

Expected: `"pass"` and `0`.

- [ ] **Step 4: Commit and clean up**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/known-failures.yaml
git -C $W commit -m "test: first known-failures list for the resolute t0 run

From the full run <workflow run id> at <image sha12>, compared case by
case with the rock run of 2026-11-19.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C $W push -q canonical --delete ci-workflow/t0-full-m3
git -C $W branch -D ci-workflow/t0-full-m3
```

(Fill in the run id and image SHA in the message from Step 2.)

---

### Task 12: Pull request and M4

**Files:** none new.

- [ ] **Step 1: Ask the user before pushing and opening the pull request**

With the user's go-ahead:

```bash
git -C ~/scratch/wt-t0 push -q canonical feat/resolute-t0-testflinger
gh pr create -R canonical/sonic-buildimage --base 202605_resolute --head feat/resolute-t0-testflinger \
  --title "test: run sonic-mgmt t0 on Testflinger nightly, after builds and on /test-t0" --body-file <body file>
```

The body states the current state only: what runs when, where the results appear, the one-time setup already done (Task 7), the M1–M3 results with run links, and how to maintain `known-failures.yaml` and `sonic-mgmt.ref`. It ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 2: After the user merges, check M4**

```bash
gh run list -R canonical/sonic-buildimage -w resolute-t0.yml -L 10 --json databaseId,event,conclusion,createdAt
```

Expected within about a day: one `schedule` run, one `workflow_run` run after a merge to `202605_resolute`, and one `issue_comment` run after the user (or the agent, with the user's go-ahead) comments `/test-t0 smoke` on an open PR; each with a report, a `resolute-t0` commit status, and for the comment run, the PR comment marked `<!-- resolute-t0 -->`.

- [ ] **Step 3: Record the outcome**

Update the memory file `resolute-nightly-testflinger-design.md` with the PR number, the M1–M4 results and anything the runs taught that is not in the code.
