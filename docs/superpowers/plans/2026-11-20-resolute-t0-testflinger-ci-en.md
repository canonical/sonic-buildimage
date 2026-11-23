# Automated sonic-mgmt t0 runs on Testflinger — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A GitHub Actions workflow in `canonical/sonic-buildimage` that runs the upstream sonic-mgmt t0 checker list against the `resolute-build` vs image on one Testflinger machine, judges the results against a known-failures list in the repository, and reports them nightly, after push/tag builds and on a `/test-t0` PR comment.

**Architecture:** One workflow (`resolute-t0.yml`) with three jobs. `resolve` runs on `ubuntu-latest`: it picks the build and its artifact and marks the commit pending. `t0` runs on the regular self-hosted runner `self-hosted-linux-amd64-noble-medium`: it writes its own `GITHUB_TOKEN` to a per-run Testflinger secret, submits the Testflinger job with `submit.sh`, follows it to the end and judges the returned artifacts with `verdict.py`. `report` runs on `ubuntu-latest` and posts the final commit status and the PR comment. On the Testflinger machine, `run-t0.sh` downloads the build artifact and pulls cEOS with that token, then builds LXD VMs. Each VM (`tb-run.sh`) builds a `vms-kvm-t0` testbed and takes chunks of test files from a shared queue. The results come back compressed. Design: `docs/superpowers/specs/2026-11-20-resolute-t0-testflinger-ci-design-en.md` on `202605_resolute_doc`.

**Tech Stack:** GitHub Actions; Testflinger (`testflinger-cli`, set up on the runner by the `canonical/testflinger` `testflinger-setup` action); bash; Python 3.12+ with only the standard library and PyYAML; pytest; LXD VMs on Ubuntu 26.04; sonic-mgmt `run_tests.sh` / `testbed-cli.sh`; docker; zstd.

## Global Constraints

- Work in the worktree `~/scratch/wt-t0` on branch `feat/resolute-t0-testflinger`, created from `canonical/202605_resolute`. Use `git -C <dir>` for every git command: the shell's working directory can silently reset to the docs repository.
- `202605_resolute` is a production branch: changes reach it only through a pull request. Never cancel a running GitHub Actions run without asking the user first (AGENTS.md).
- Commits are GPG-signed (`commit.gpgsign` is already `true`), use the `test:` prefix (`build:` for the change to `resolute-build.yml`), and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Comments in code: only where the reason is not obvious, one line each. Root causes and numbers go into commit messages.
- Python must run on Python 3.12 (the runner) and 3.14 (Ubuntu 26.04), with the standard library plus PyYAML only.
- Every `reason` in `known-failures.yaml` is written in English.
- Never release or cancel a Testflinger reservation the user holds without their explicit word.
- Fixed names, used verbatim everywhere:
  - Testflinger queue `sonic-ci`; per-run Testflinger secret `sonic-buildimage/t0-run-<run id>-<attempt>`, which expires after one day and is deleted when the `t0` job ends
  - build artifact `sonic-vs-img` of `resolute-build`, kept for 30 days; the machine checks the zip against the digest GitHub recorded for the artifact
  - cEOS image `ghcr.io/canonical/sonic-ceos:4.32.5M-1`, with Actions read access for `canonical/sonic-buildimage`; retagged on the machine as `ceosimage:4.32.5M-1`
  - commit status context `resolute-t0`; PR comment marker `<!-- resolute-t0 -->`
  - job `t0` on `self-hosted-linux-amd64-noble-medium` with `timeout-minutes: 1440`; jobs `resolve` and `report` on `ubuntu-latest`
  - permissions `{}` at workflow level; `t0` gets `actions`, `contents` and `packages` read only; `resolve` and `report` get `actions: read` and write on `issues`, `pull-requests` and `statuses`
  - Testflinger CLI setup action `canonical/testflinger/.github/actions/testflinger-setup@257ef71c8042a41925d7185d46fc3171ea2112f5` (submit/v1.6.0); `submit.sh` allows 25 minutes per provision attempt and 2 retries, with no limit on the queue wait
  - schedule `cron: "0 15 * * *"`; job file `global_timeout: 43200`, `output_timeout: 7200`
  - sonic-mgmt pin `a88d1d5f9323833d8cf2e050c84904deb22ed3bc` (`canonical/sonic-mgmt`)
  - testbed `vms-kvm-t0`, DUT `vlab-01`, VM user `tb`; chunk target = estimated total / (2 × testbeds), unknown file 480 s
  - sizing T = min(⌊(RAM GiB − 16) / 18⌋, ⌊threads / 8⌋, ⌊free pool GB / 40⌋), at most 2 for smoke; dispatch stops 37800 s after the harness starts, hard stop at 41400 s

---

## File Structure

New files, in `canonical/sonic-buildimage`:

| File | Responsibility |
|---|---|
| `.github/workflows/resolute-t0.yml` | Triggers, build resolution, Testflinger submission, verdict, reporting |
| `.github/testflinger/t0/make_chunks.py` | Packs test files into chunks by expected duration |
| `.github/testflinger/t0/durations.json` | Per-file times measured on M3, used for chunking |
| `.github/testflinger/t0/verdict.py` | Parses JUnit, picks files to rerun, classifies cases against the known list, writes summary/report/durations |
| `.github/testflinger/t0/configure_sonic_mgmt.py` | Applies the KVM testbed settings to a sonic-mgmt tree |
| `.github/testflinger/t0/render_job.py` + `job.yaml.in` | Renders the Testflinger job file |
| `.github/testflinger/t0/submit.sh` | Submits the job, cancels and resubmits a provision attempt over 25 minutes, retries twice, cancels the job when interrupted |
| `.github/testflinger/t0/agent.sh` | Agent side: copies the harness, starts it detached, relays progress, fetches artifacts |
| `.github/testflinger/t0/run-t0.sh` | Machine side entry: phases, artifact download, cEOS pull, VM launch, monitoring, time guard, packing, `run-meta.json` |
| `.github/testflinger/t0/host-setup.sh` | Host packages, LXD, storage pool, swap, firewall, shared images, sizing |
| `.github/testflinger/t0/tb-run.sh` | One testbed in one VM: tools, add-topo, deploy-mg, chunk loop, reruns |
| `.github/testflinger/t0/known-failures.yaml` | Reviewed known failures and loganalyzer noise rules |
| `.github/testflinger/t0/sonic-mgmt.ref` | Pinned sonic-mgmt commit |
| `.github/testflinger/t0/smoke.txt` | Smoke test list |
| `.github/testflinger/t0/tests/` | pytest tests: `conftest.py`, `test_make_chunks.py`, `test_verdict.py`, `test_configure_sonic_mgmt.py`, `test_render_job.py`, `test_shell_syntax.py`, `test_submit.py` |

Changed files:

| File | Change |
|---|---|
| `.github/workflows/resolute-build.yml` | The `sonic-vs-img` artifact is kept for 30 days |
| `.github/actionlint.yaml` | Declares the runner label `self-hosted-linux-amd64-noble-medium` |

Test command, from the worktree root: `python3 -m pytest -q .github/testflinger/t0/tests`

---

### Task 1: Worktree and chunk packing

**Files:**
- Create: `.github/testflinger/t0/make_chunks.py`
- Create: `.github/testflinger/t0/tests/conftest.py`
- Test: `.github/testflinger/t0/tests/test_make_chunks.py`

**Interfaces:**
- Produces: `make_chunks.pack(files: list[str], durations: dict[str, float], target: float = 3000.0, default: float = 480.0) -> list[list[str]]`; `make_chunks.auto_target(files, durations, testbeds, rounds=2, default=480.0) -> float`, the estimated total divided by `testbeds × rounds`; CLI `make_chunks.py <file list> <durations.json> <out dir> [target seconds|auto] [default seconds] [testbeds]` writing files `000`, `001`, … (one test file per line).

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


def test_auto_target_gives_each_testbed_two_rounds():
    durations = {"f%02d.py" % i: 600 for i in range(40)}
    assert make_chunks.auto_target(list(durations), durations, testbeds=4) == 3000
    assert make_chunks.auto_target(["new.py"], {}, testbeds=1, default=480) == 240


def test_cli_auto_target(tmp_path):
    (tmp_path / "files.txt").write_text("".join("f%d.py\n" % i for i in range(8)))
    (tmp_path / "d.json").write_text(json.dumps({"f%d.py" % i: 100 for i in range(8)}))
    subprocess.run([sys.executable, str(Path(make_chunks.__file__)), str(tmp_path / "files.txt"),
                    str(tmp_path / "d.json"), str(tmp_path / "out"), "auto", "480", "2"], check=True)
    assert len(list((tmp_path / "out").iterdir())) == 4
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_make_chunks.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'make_chunks'`.

- [ ] **Step 4: Write `make_chunks.py`**

```python
#!/usr/bin/env python3
"""Pack test files into chunks of about TARGET seconds, longest first.

usage: make_chunks.py <file list> <durations.json> <out dir> [target seconds|auto] [default seconds] [testbeds]
"""
import json
import os
import sys


def auto_target(files, durations, testbeds, rounds=2, default=480.0):
    return sum(float(durations.get(f, default)) for f in dict.fromkeys(files)) / (max(1, testbeds) * rounds)


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
    default = float(argv[5]) if len(argv) > 5 else 480.0
    if len(argv) > 4 and argv[4] == "auto":
        target = auto_target(files, durations, int(argv[6]), default=default)
    else:
        target = float(argv[4]) if len(argv) > 4 else 3000.0
    chunks = pack(files, durations, target, default)
    os.makedirs(argv[3], exist_ok=True)
    for i, chunk in enumerate(chunks):
        with open(os.path.join(argv[3], "%03d" % i), "w") as fh:
            fh.write("\n".join(chunk) + "\n")
    print("%d files -> %d chunks of about %d s" % (len(set(files)), len(chunks), target))


if __name__ == "__main__":
    main(sys.argv)
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_make_chunks.py`
Expected: `8 passed`.

- [ ] **Step 6: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/make_chunks.py .github/testflinger/t0/tests/conftest.py .github/testflinger/t0/tests/test_make_chunks.py
git -C $W commit -m "test: pack sonic-mgmt test files into chunks by expected duration

Longest file first into the fullest chunk that still fits, so testbeds
finish at about the same time; files with no recorded duration count
480 s, as in the 2026-11-19 farm run. With \"auto\" the target is the
estimated total divided by two rounds per testbed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Verdict — JUnit parsing and known-failures matching

**Files:**
- Create: `.github/testflinger/t0/verdict.py`
- Test: `.github/testflinger/t0/tests/test_verdict.py`

**Interfaces:**
- Produces: `Case(outcome: str, message: str = "")` with outcome in `passed|skipped|failed|error`; `id_pattern(text) -> re.Pattern`; `Known(path)` with `.entries` (dicts with `id`, `kind`, `reason`, `_re`, `_file`), `.noise` (compiled patterns), `.covers(cid, case) -> bool`; `case_id(rel_xml, classname, name) -> str`; `own_loganalyzer_noise(text, noise) -> bool`; `parse_xml(path, rel_xml, noise) -> dict[str, Case]`; `chunk_dirs(results) -> iterator of ((chunk, retry, rerun), Path)`; `parse_dir(d, noise) -> dict[test file, dict[str, Case]]`; `load_results(results, noise) -> (first: dict[str, Case], final: dict[str, Case], ran: set[str])`; constants `SKIP_XML`, `CHUNK_DIR`, `BAD`, `LA_ERROR`, `LA_LINE`.

- [ ] **Step 1: Write the failing tests**

`.github/testflinger/t0/tests/test_verdict.py`:

```python
import json
import re
import subprocess
import sys
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

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


def own_la(lines, tag="failure", missing=0, count=None, teardown=False):
    n = len(lines) if count is None else count
    msg = "tests.common.plugins.loganalyzer.loganalyzer.LogAnalyzerError: match: %d\nexpected_match: 0" % n
    if teardown:
        msg = 'failed on teardown with "' + msg
    body = ("analyzer_summary = {'total': {'match': %d}, 'match_files': {'/tmp/syslog': ['u...ailed']}}\n"
            "E   tests.common.plugins.loganalyzer.loganalyzer.LogAnalyzerError: match: %d\nE   expected_match: 0\n"
            "E   expected_missing_match: %d\nE   Match Messages:\n" % (n, n, missing))
    body += "".join("E   2026 Nov 23 07:30:43.324521 vlab-01 ERR %s\n" % line for line in lines)
    return "<%s message=%s>%s</%s>" % (tag, quoteattr(msg), escape(body), tag)


def test_own_loganalyzer_noise_only_is_ignored(tmp_path):
    noise = "unix_chkpwd: nss_tacplus: /etc/tacplus_nss.conf fopen failed"
    xml = tmp_path / "t.xml"
    junit(xml, [("tests.t", "a", own_la([noise, noise])),
                ("tests.t", "b", own_la([noise, "orchagent: boom"])),
                ("tests.t", "c", own_la([noise], missing=1)),
                ("tests.t", "d", own_la([noise], count=3)),
                ("tests.t", "e", ""), ("tests.t", "e", own_la([noise], tag="error", teardown=True))])
    cases = verdict.parse_xml(xml, "t.xml", [re.compile(NOISE)])
    assert cases["t.py::a"].outcome == "passed"
    assert cases["t.py::b"].outcome == "failed"
    assert cases["t.py::c"].outcome == "failed"
    assert cases["t.py::d"].outcome == "failed"
    assert cases["t.py::e"].outcome == "passed"


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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_verdict.py`
Expected: `9 passed`.

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

Tests that run their own LogAnalyzer (test_pktgen, the mocked
temperature test in test_platform_info) fail with \"LogAnalyzerError:
match: N\" instead. Such an error counts as noise when nothing expected
is missing, the full syslog lines in its \"E\" block number exactly N,
and every one matches a noise pattern; the truncated repr of the
analyzer summary is ignored.

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
Expected: FAIL, `7 failed, 9 passed`: `AttributeError: module 'verdict' has no attribute 'decide'`, and the CLI tests fail because `verdict.py` has no command line yet: no `summary.json` appears (`FileNotFoundError`) and `rerun-files` prints nothing.

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
Expected: `24 passed`.

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
- Produces: `render_job.render(sha12, gh_run, repo, artifact_id, artifact_digest, scope, secret) -> str`; CLI `render_job.py --sha12 --gh-run --repo --artifact-id --artifact-digest --scope --secret` (job YAML on stdout). The job maps the Testflinger secret at the `--secret` path to `GH_TOKEN`. `agent.sh` reads `DEVICE_IP`, `GH_TOKEN`, `REPO`, `ARTIFACT_ID`, `ARTIFACT_DIGEST`, `SCOPE`; expects `attachments/test/t0-harness.tar.gz`; writes `artifacts/{results.tar.zst,run-meta.json,run-t0.log,host-setup.log,tb-*.log}`; exits with the harness exit code.
- Consumes (from Task 6, on the machine): `~/t0/run-t0.sh` writes `~/t0-out/progress.log`, `~/t0-out/tb-<i>.log` and `~/t0-out/EXIT`.

- [ ] **Step 1: Write the failing tests**

`.github/testflinger/t0/tests/test_render_job.py`:

```python
import subprocess

import pytest
import yaml

import render_job

ARGS = dict(sha12="0123456789ab", gh_run="42", repo="canonical/sonic-buildimage", artifact_id="14400660343",
            artifact_digest="sha256:" + "a" * 64, scope="smoke", secret="sonic-buildimage/run-42-1")


def test_render_gives_a_valid_job():
    job = yaml.safe_load(render_job.render(**ARGS))
    assert job["job_queue"] == "sonic-ci"
    assert job["global_timeout"] == 43200 and job["output_timeout"] == 7200
    assert job["provision_data"] == {"distro": "resolute"}
    assert job["test_data"]["secrets"] == {"GH_TOKEN": "sonic-buildimage/run-42-1"}
    assert job["test_data"]["attachments"] == [{"local": "t0-harness.tar.gz"}]
    assert "sha:0123456789ab" in job["tags"] and "gh-run:42" in job["tags"]
    cmds = job["test_data"]["test_cmds"]
    for part in ("SCOPE='smoke'", "REPO='canonical/sonic-buildimage'", "ARTIFACT_ID='14400660343'",
                 "ARTIFACT_DIGEST='sha256:" + "a" * 64 + "'"):
        assert part in cmds
    subprocess.run(["bash", "-n"], input=cmds, text=True, check=True)


@pytest.mark.parametrize("field,value", [("scope", "all"), ("sha12", "XYZ"), ("gh_run", "12a"),
                                         ("repo", "canonical"), ("repo", "a/b c"), ("artifact_id", "x1"),
                                         ("artifact_digest", "f" * 64), ("artifact_digest", "sha256:abc"),
                                         ("secret", "a b"), ("secret", "x'y")])
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
job_queue: sonic-ci
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
    GH_TOKEN: ${SECRET}
  test_cmds: |
    set -u
    mkdir -p t0 && tar -xzf attachments/test/t0-harness.tar.gz -C t0
    REPO='${REPO}' ARTIFACT_ID='${ARTIFACT_ID}' ARTIFACT_DIGEST='${ARTIFACT_DIGEST}' SCOPE='${SCOPE}' bash t0/agent.sh
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


def render(sha12, gh_run, repo, artifact_id, artifact_digest, scope, secret):
    checks = [(re.fullmatch(r"[0-9a-f]{12}", sha12), "sha12"), (re.fullmatch(r"\d+", gh_run), "gh-run"),
              (re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo), "repo"),
              (re.fullmatch(r"\d+", artifact_id), "artifact-id"),
              (re.fullmatch(r"sha256:[0-9a-f]{64}", artifact_digest), "artifact-digest"),
              (scope in ("full", "smoke"), "scope"), (re.fullmatch(r"[A-Za-z0-9_./-]+", secret), "secret")]
    for ok, name in checks:
        if not ok:
            raise ValueError("invalid --%s" % name)
    return string.Template(TEMPLATE.read_text()).substitute(
        SHA12=sha12, GH_RUN=gh_run, REPO=repo, ARTIFACT_ID=artifact_id, ARTIFACT_DIGEST=artifact_digest,
        SCOPE=scope, SECRET=secret)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for opt in ("--sha12", "--gh-run", "--repo", "--artifact-id", "--artifact-digest", "--scope", "--secret"):
        parser.add_argument(opt, required=True)
    a = parser.parse_args(argv)
    sys.stdout.write(render(a.sha12, a.gh_run, a.repo, a.artifact_id, a.artifact_digest, a.scope, a.secret))


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
printf '%s\n' "${GH_TOKEN:-}" | on "read -r GH_TOKEN; export GH_TOKEN REPO='$REPO' ARTIFACT_ID='$ARTIFACT_ID' \
ARTIFACT_DIGEST='$ARTIFACT_DIGEST' SCOPE='$SCOPE'; \
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
for f in results.tar.zst run-meta.json run-t0.log host-setup.log 'tb-*.log'; do
    scp "${opts[@]}" "$m:t0-out/$f" artifacts/ || true
done
rc=$(on 'cat t0-out/EXIT' 2>/dev/null)
exit "${rc:-1}"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests`
Expected: `41 passed` (24 + 5 + 11 render cases + 1 shell syntax case).

- [ ] **Step 5: Commit**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/job.yaml.in .github/testflinger/t0/render_job.py .github/testflinger/t0/agent.sh \
    .github/testflinger/t0/tests/test_render_job.py .github/testflinger/t0/tests/test_shell_syntax.py
git -C $W commit -m "test: Testflinger job template and agent side of the t0 run

The harness runs detached on the machine so an SSH drop cannot end the
run; the agent relays progress.log every minute, which also keeps the
output timeout quiet, and brings back the per-testbed logs with the
results. GH_TOKEN goes over stdin into the harness environment.
Template values are validated, so none can carry a quote into
test_cmds.

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
- Create: `.github/testflinger/t0/durations.json`
- Test: `.github/testflinger/t0/tests/test_shell_syntax.py` (already parametrised over `*.sh`)

**Interfaces:**
- Consumes: `make_chunks.py` CLI with `auto` (Task 1); `verdict.py rerun-files` (Task 3); `configure_sonic_mgmt.py` CLI (Task 4); `GH_TOKEN`, `REPO`, `ARTIFACT_ID`, `ARTIFACT_DIGEST` and `SCOPE` from `agent.sh` (Task 5).
- Produces: `host-setup.sh` prints `TESTBEDS=<n>`, `VCPU=<n>`, `POOL=<name>` as its last lines; `run-t0.sh` writes `~/t0-out/{progress.log,host-setup.log,tb-<i>.log,files.txt,run-meta.json,results.tar.zst,EXIT}` and exits 3 when no chunk finished on any testbed; `run-meta.json` keys `machine, testbeds, artifact_id, image_sha256, sonic_mgmt, scope, files, phases, time_guard, rc, phase`; results under `/srv/queue/results/<label>/<NNN[.retry][.rerun]>/` plus `<NNN[.retry]>.time` = `<start> <end>` epoch seconds of the first run.

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
# add-topo runs docker-ptf with the tag of the sonic-mgmt branch, 202605 at the pinned commit.
for img in docker-sonic-mgmt:latest docker-ptf:202605; do
    sudo docker pull -q sonicdev-microsoft.azurecr.io:443/$img
    sudo docker save sonicdev-microsoft.azurecr.io:443/$img -o $S/${img%%:*}.tar
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
# Without the https line apt sends https through the lab proxy, which cannot resolve download.docker.com.
printf 'Acquire::http::Proxy "http://%s/";\nAcquire::https::Proxy "DIRECT";\n' "$(cat $S/apt-proxy)" > /etc/apt/apt.conf.d/90proxy
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
    mgmt "cd /data/sonic-mgmt/tests && ./run_tests.sh -n $TB -d $DUT -f vtestbed.yaml -i ../ansible/veos_vtb -t t0,any -e --device_type=vs -m individual -O -p logs/$dir -c '$*'" \
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
    "artifact_id": os.environ.get("ARTIFACT_ID", ""), "image_sha256": os.environ.get("IMAGE_SHA256", ""),
    "sonic_mgmt": os.environ["MGMT"], "scope": os.environ.get("SCOPE", ""), "files": files,
    "phases": {k: int(v) for k, v in (p.split("=") for p in os.environ["PHASES"].split())},
    "time_guard": os.environ["TIME_GUARD"] == "true", "rc": int(os.environ["RC"]), "phase": os.environ["PHASE"]},
    indent=1))
EOF
    progress "exit $rc"
    echo "$rc" > "$OUT/EXIT"
}
trap finish EXIT
progress "start scope=$SCOPE artifact=$REPO/$ARTIFACT_ID"

enter host-setup
bash "$T0/host-setup.sh" > "$OUT/host-setup.log" 2>&1
TESTBEDS=0 VCPU=0 POOL=default
eval "$(grep -E '^(TESTBEDS|VCPU|POOL)=[A-Za-z0-9_-]+$' "$OUT/host-setup.log")"
testbeds=$TESTBEDS
if [ "$SCOPE" = smoke ] && [ "$testbeds" -gt 2 ]; then testbeds=2; fi
progress "testbeds=$testbeds vcpu=$VCPU pool=$POOL"

enter payload
# GH_TOKEN is the workflow job's own token, read-only for actions and packages; it dies with that job.
zip=$S/sonic-vs-img.zip
for _ in 1 2 3; do
    url=$(curl -fsS -o /dev/null -w '%{redirect_url}' -H @<(printf 'Authorization: Bearer %s\n' "$GH_TOKEN") \
        "https://api.github.com/repos/$REPO/actions/artifacts/$ARTIFACT_ID/zip") || url=""
    if [ -n "$url" ] && curl -fsSL -o "$zip" "$url"; then break; fi
    rm -f "$zip"
    sleep 30
done
echo "${ARTIFACT_DIGEST#sha256:}  $zip" | sha256sum -c -
python3 -m zipfile -e "$zip" $S
rm -f "$zip"
IMAGE_SHA256=$(sha256sum $S/sonic-vs.img.gz | cut -d' ' -f1)
export IMAGE_SHA256
gunzip -f $S/sonic-vs.img.gz
dc=$(mktemp -d -p /dev/shm)
printf '%s' "$GH_TOKEN" | sudo env DOCKER_CONFIG="$dc" docker login ghcr.io -u token --password-stdin >/dev/null
sudo env DOCKER_CONFIG="$dc" docker pull -q $CEOS
sudo rm -rf "$dc"
unset GH_TOKEN
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
    # run_tests.sh silently drops files under its SKIP_FOLDERS.
    sudo docker run --rm -v $S/sonic-mgmt:/sm:ro -w /sm/.azure-pipelines/impacted_area_testing $MGMT_IMAGE \
        python3 get_test_scripts.py --features "" --location /sm/tests \
        | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["t0_checker"]))' \
        | grep -vE '^(ptftests|acstests|saitests|scripts|k8s|sai_qualify)/' > "$OUT/files.txt"
fi
progress "$(wc -l < "$OUT/files.txt") test files"
sudo rm -rf $Q/pending $Q/claimed $Q/done $Q/finished $Q/results $Q/STOP
mkdir -p $Q/pending $Q/finished
target=auto
if [ "$SCOPE" = smoke ]; then target=1; fi
python3 "$T0/make_chunks.py" "$OUT/files.txt" "$T0/durations.json" $Q/pending $target 480 "$testbeds"

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
if [ "$(ls $Q/done | wc -l)" -eq 0 ]; then
    progress "no chunk finished on any testbed"
    exit 3
fi
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

`.github/testflinger/t0/known-failures.yaml` starts with an empty list, `known: []`, followed by the loganalyzer noise rule. Task 11 fills in the list; the noise rule stays as it is:

```yaml
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

`.github/testflinger/t0/durations.json` starts empty, so every file counts 480 s until Task 11 commits the times measured on M3:

```bash
printf '{}' > ~/scratch/wt-t0/.github/testflinger/t0/durations.json
```

- [ ] **Step 5: Run the tests and shellcheck**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests && python3 -c "import sys; sys.path.insert(0, '.github/testflinger/t0'); import verdict; verdict.Known('.github/testflinger/t0/known-failures.yaml')"`
Expected: `44 passed` (41 + 3 new shell syntax cases) and no error from loading the list.

Run: `docker run --rm -v ~/scratch/wt-t0/.github/testflinger/t0:/t0:ro koalaman/shellcheck:stable -S warning /t0/agent.sh /t0/host-setup.sh /t0/tb-run.sh /t0/run-t0.sh`
Expected: no output. Fix any warning before committing.

- [ ] **Step 6: Commit**

The scripts are executable:

```bash
W=~/scratch/wt-t0
T=.github/testflinger/t0
chmod +x $W/$T/agent.sh $W/$T/host-setup.sh $W/$T/tb-run.sh $W/$T/run-t0.sh \
    $W/$T/configure_sonic_mgmt.py $W/$T/make_chunks.py $W/$T/render_job.py $W/$T/verdict.py
git -C $W add $T/host-setup.sh $T/tb-run.sh $T/run-t0.sh $T/known-failures.yaml $T/sonic-mgmt.ref $T/smoke.txt \
    $T/durations.json $T/agent.sh $T/configure_sonic_mgmt.py $T/make_chunks.py $T/render_job.py $T/verdict.py
git -C $W commit -m "test: machine side of the t0 run on Testflinger

host-setup.sh, tb-run.sh and run-t0.sh are the 2026-11-10/19 farm
scripts made self-contained: the environment traps fixed in place
(https apt traffic of the VMs goes direct, docker-ptf:202605 is
preloaded because add-topo runs that tag), VMs on spare SSDs
(jasperoid's root disk holds only 10 testbeds), testbeds sized from
RAM, threads and pool space, the t0_checker list minus the folders
run_tests.sh skips, run with --device_type=vs like the upstream PR
checker, chunks from a shared queue with a 10.5 h dispatch stop, reruns
of uncovered failures after deploy-mg, and exit 3 when no chunk
finishes. The machine downloads the build artifact, checks it against
the artifact digest, and pulls cEOS with a token that only lives in
/dev/shm. The smoke list is four short files that all passed on rock
on 2026-11-19. sonic-mgmt is pinned to the head of PR stack #5-#9,
the commit of the 2026-11-19 full run.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: One-time setup

**Files:** none in the repository.

**Interfaces:**
- Produces: `ghcr.io/canonical/sonic-ceos:4.32.5M-1` (internal) with Actions read access for `canonical/sonic-buildimage`; repository secrets `TESTFLINGER_CLIENT_ID` and `TESTFLINGER_SECRET_KEY`; queue `sonic-ci` on the 10 agents.

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

- [ ] **Step 2: Ask the user to give the repository Actions access to the package**

The user (a package admin) opens `https://github.com/orgs/canonical/packages/container/sonic-ceos/settings` and, under "Manage Actions access", adds `canonical/sonic-buildimage` with the Read role. The `t0` job's `GITHUB_TOKEN` can then pull the image. The cEOS pull on the machine in M2 (Task 10) proves it.

- [ ] **Step 3: Ask the user to add the repository secrets**

The user (a repository admin) adds `TESTFLINGER_CLIENT_ID` and `TESTFLINGER_SECRET_KEY` under Settings → Secrets and variables → Actions of `canonical/sonic-buildimage`. Then check:

```bash
gh secret list -R canonical/sonic-buildimage | grep -E '^TESTFLINGER_(CLIENT_ID|SECRET_KEY)'
```

Expected: both names listed.

- [ ] **Step 4: Set and check the queue**

In C3, set the "Customized queues" field so that exactly these 10 machines carry `sonic-ci`: fleetroc (20 testbeds); alarmmonkey, alienbunny, kroop, vlacq, cajal, parakarry (16 each); smilax, jasperoid, hoodin (13 each). The rule is "at least 13 testbeds". Then:

```bash
testflinger-cli list-agents --fields name,status --filter-queues sonic-ci
```

Expected: exactly these 10 machines. If the list differs, the certification bot has not synced `testflinger-agent-charm-configs` yet: tell the user to ask the certification team to sync TOR3-DH1, and continue with Task 8, which does not need the queue. Until the sync, the M3 branch points `job_queue` at one large machine (Task 11 Step 1).

---

### Task 8: M1 — smoke run by hand on one machine

**Files:** fixes to Task 5/6 files if the run exposes bugs.

**Interfaces:**
- Consumes: the harness (Tasks 1–6), the cEOS image (Task 7), and the user's `gh` login token, which can read the artifact and, as in Task 7 Step 1, the cEOS package.

- [ ] **Step 1: Prepare the payload**

```bash
M1=~/scratch/t0-m1 && rm -rf $M1 && mkdir -p $M1/attachments/test
gh api "repos/canonical/sonic-buildimage/actions/artifacts?name=sonic-vs-img&per_page=1" \
  --jq '.artifacts[0] | select(.expired | not) | "\(.workflow_run.id) \(.id) \(.digest)"' > $M1/artifact
tar -czf $M1/attachments/test/t0-harness.tar.gz -C ~/scratch/wt-t0/.github/testflinger/t0 --exclude=tests --exclude=__pycache__ .
cat $M1/artifact
```

Expected: one line with the build run id, the artifact id and its `sha256:` digest. An empty line means the newest `sonic-vs-img` artifact has expired.

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

- [ ] **Step 3: Run the agent side from this VM**

```bash
IP=<device ip from the hold line>
cd ~/scratch/t0-m1 && read -r run art digest < artifact && DEVICE_IP=$IP GH_TOKEN=$(gh auth token) \
  REPO=canonical/sonic-buildimage ARTIFACT_ID=$art ARTIFACT_DIGEST=$digest SCOPE=smoke \
  bash ~/scratch/wt-t0/.github/testflinger/t0/agent.sh > agent.log 2>&1; echo "agent exit $?"
```

Run it in the background (`run_in_background`); it prints a progress line every 5 minutes and ends in about 40–60 minutes. The machine downloads the artifact itself; the harness drops the token after the payload phase.

- [ ] **Step 4: Judge the result**

```bash
cd ~/scratch/t0-m1 && rm -rf results && mkdir results && zstd -dc artifacts/results.tar.zst | tar -x -C results --strip-components=1
python3 ~/scratch/wt-t0/.github/testflinger/t0/verdict.py report --results results \
  --known ~/scratch/wt-t0/.github/testflinger/t0/known-failures.yaml --meta artifacts/run-meta.json \
  --out-json summary.json --out-md report.md --out-durations durations.json
cat report.md; ls results; jq '.files, .testbeds, .rc, .phases' artifacts/run-meta.json
```

Expected (M1 acceptance): `agent exit 0`; `artifacts/` holds `tb-1.log` and `tb-2.log`; `results/` has `tb1` and `tb2`, each with at least one chunk directory; every file of `smoke.txt` has a JUnit result (no "Files not run"); the outcome is `Pass`. A smoke file that fails is analysed: either a harness bug (fix it, commit, and repeat Step 3 — `run-t0.sh` is safe to rerun on the same machine) or a real image failure (record it for the Task 11 list).

Result: M1 passed on alarmmonkey: 12 passed, 1 skipped, outcome `Pass`.

- [ ] **Step 5: Commit any fixes and report**

Commit each harness fix separately with a `test:` message stating the observed failure. Report to the user: the outcome, the phase times from `run-meta.json`, and that the alarmmonkey hold (job id in `~/testflinger-jobs/t0-m1-jobid`) is still running until they say to release it.

---

### Task 9: The workflow

**Files:**
- Create: `.github/testflinger/t0/submit.sh`
- Test: `.github/testflinger/t0/tests/test_submit.py`
- Modify: `.github/workflows/resolute-build.yml`
- Create: `.github/workflows/resolute-t0.yml`
- Modify: `.github/actionlint.yaml`

**Interfaces:**
- Consumes: `render_job.py` CLI, `verdict.py report` CLI, `known-failures.yaml`, `durations.json`, the repository secrets and the cEOS Actions access from Task 7.
- Produces: `submit.sh <job file>`, which reads `PROVISION_LIMIT` (minutes, default 25), `RETRIES` (default 2), `POLL` (seconds, default 30) and `GITHUB_OUTPUT`, writes `id=<job id>` to `GITHUB_OUTPUT`, exits 0 once the test phase starts, 1 when submission fails or no attempt gets through setup and provisioning, and 130 after cancelling the job on SIGINT or SIGTERM. The workflow produces the commit status `resolute-t0` (pending from `resolve`, final from `report`); the job summary; the workflow artifact `resolute-t0-<sha12>-<attempt>` containing `summary.json`, `report.md`, `durations.json`, `artifacts/`; the PR comment marked `<!-- resolute-t0 -->`; and the per-run Testflinger secret, deleted at the end of `t0`.

- [ ] **Step 1: Write the failing test for `submit.sh`**

`.github/testflinger/t0/tests/test_submit.py` runs `submit.sh` against a fake `testflinger` command that plays a scenario of job states:

```python
import json
import os
import subprocess
from pathlib import Path

T0 = Path(__file__).resolve().parents[1]

FAKE = r'''#!/usr/bin/env python3
import json, os, sys
d = os.environ["FAKE_TF"]
sc = json.load(open(f"{d}/scenario.json"))
st = json.load(open(f"{d}/state.json")) if os.path.exists(f"{d}/state.json") else {"jobs": [], "calls": []}
args = [a for a in sys.argv[1:] if a != "--quiet"]
st["calls"].append(args)
cmd, rest = args[0], args[1:]
out = ""
if cmd == "submit":
    st["jobs"].append({"n": 0, "cancelled": False})
    out = f"job{len(st['jobs'])}"
else:
    i = int(rest[-1][3:]) - 1
    job, spec = st["jobs"][i], sc[i]
    if cmd == "status":
        out = "cancelled" if job["cancelled"] else spec["states"][min(job["n"], len(spec["states"]) - 1)]
        job["n"] += 1
    elif cmd == "cancel":
        job["cancelled"] = True
    elif cmd == "results":
        out = json.dumps(spec.get("results", {}))
json.dump(st, open(f"{d}/state.json", "w"))
print(out)
'''


def run(tmp_path, scenario, **env):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "testflinger").write_text(FAKE)
    (bin_dir / "testflinger").chmod(0o755)
    (tmp_path / "scenario.json").write_text(json.dumps(scenario))
    out = tmp_path / "gh-output"
    out.touch()
    full_env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "FAKE_TF": str(tmp_path),
                "GITHUB_OUTPUT": str(out), "POLL": "0", **env}
    p = subprocess.run(["bash", str(T0 / "submit.sh"), "job.yaml"], env=full_env, capture_output=True, text=True)
    calls = json.loads((tmp_path / "state.json").read_text())["calls"]
    return p, calls, out.read_text()


OK = {"setup_status": 0, "provision_status": 0}


def test_first_attempt_reaches_the_test_phase(tmp_path):
    p, calls, out = run(tmp_path, [{"states": ["waiting", "setup", "provision", "provision", "test"], "results": OK}])
    assert p.returncode == 0, p.stdout + p.stderr
    assert [c[0] for c in calls].count("submit") == 1
    assert not any(c[0] == "cancel" for c in calls)
    assert out == "id=job1\n"


def test_overrunning_provision_is_cancelled_and_resubmitted(tmp_path):
    p, calls, out = run(tmp_path, [{"states": ["waiting", "provision"]}, {"states": ["waiting", "test"], "results": OK}],
                        PROVISION_LIMIT="0")
    assert p.returncode == 0, p.stdout + p.stderr
    assert ["cancel", "job1"] in calls
    assert [c[0] for c in calls].count("submit") == 2
    assert out == "id=job2\n"


def test_waiting_in_the_queue_is_not_limited(tmp_path):
    p, calls, _ = run(tmp_path, [{"states": ["waiting"] * 5 + ["test"], "results": OK}], PROVISION_LIMIT="0")
    assert p.returncode == 0, p.stdout + p.stderr
    assert not any(c[0] == "cancel" for c in calls)


def test_failed_provisioning_uses_up_the_retries(tmp_path):
    failed = {"states": ["provision", "complete"], "results": {"setup_status": 0, "provision_status": 1}}
    p, calls, out = run(tmp_path, [failed, failed], RETRIES="1")
    assert p.returncode != 0
    assert [c[0] for c in calls].count("submit") == 2
    assert out == "id=job2\n"
```

- [ ] **Step 2: Run the test to see it fail**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests/test_submit.py`
Expected: FAIL, `4 failed`, each with `FileNotFoundError` for `state.json`: without `submit.sh` the fake CLI is never called.

- [ ] **Step 3: Write `submit.sh`**

```bash
#!/bin/bash
# Submit the job and return once its test phase starts; setup or provisioning that fails or overruns is retried.
set -u
job=$1 limit=$((${PROVISION_LIMIT:-25} * 60)) retries=${RETRIES:-2} poll=${POLL:-30}
id=""
trap '[ -z "$id" ] || testflinger cancel "$id"; exit 130' INT TERM
for attempt in $(seq 0 "$retries"); do
    id=$(testflinger submit --quiet "$job") || exit 1
    echo "id=$id" > "$GITHUB_OUTPUT"
    echo "::notice::Testflinger job $id (attempt $((attempt + 1)) of $((retries + 1)))"
    since=""
    while :; do
        state=$(testflinger status "$id") || state=""
        case "$state" in
            ""|waiting|setup) ;;
            provision)
                since=${since:-$SECONDS}
                if [ $((SECONDS - since)) -ge "$limit" ]; then
                    echo "::warning::$id has been provisioning for over $((limit / 60)) minutes; cancelling it"
                    testflinger cancel "$id"
                    break
                fi ;;
            *) break ;;
        esac
        sleep "$poll"
    done
    [ "$state" != test ] || exit 0
    if testflinger results "$id" | jq -e '.setup_status == 0 and .provision_status == 0' >/dev/null; then
        exit 0
    fi
    echo "::error::$id did not get through setup and provisioning ($state)"
done
exit 1
```

- [ ] **Step 4: Run the tests and shellcheck**

Run: `cd ~/scratch/wt-t0 && python3 -m pytest -q .github/testflinger/t0/tests`
Expected: `49 passed` (44 + 4 submit cases + 1 shell syntax case).

Run: `docker run --rm -v ~/scratch/wt-t0/.github/testflinger/t0:/t0:ro koalaman/shellcheck:stable -S warning /t0/submit.sh`
Expected: no output.

- [ ] **Step 5: Commit `submit.sh`**

```bash
W=~/scratch/wt-t0
chmod +x $W/.github/testflinger/t0/submit.sh
git -C $W add .github/testflinger/t0/submit.sh .github/testflinger/t0/tests/test_submit.py
git -C $W commit -m "test: give t0 provisioning 25 minutes per attempt

A maas2 deploy that is going to fail runs into the agent's 60-minute
timeout, which lives in the agent config and cannot be set per job;
the canonical/testflinger submit action has no limit of its own
either. In the Testflinger results still kept for the 11 sonic-ci
machines (since 2026-11-16), 49 of 50 failed provisions took 62-66
minutes, while the 81 successful deploys took 3.4-26.5 minutes (p90
16.1). Our own 28 successful resolute installs took 12.8-17.7 minutes
in MAAS and at most 19.6 minutes for the whole provision phase.

submit.sh submits, cancels and resubmits a job whose provision phase
passes 25 minutes, retries failed setup or provisioning twice, and
cancels the job when it is interrupted. Queue waiting is not limited.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Keep the vs image artifact for 30 days**

In `.github/workflows/resolute-build.yml`, the `Upload sonic-vs image` step sets `retention-days: 30`:

```yaml
      - name: Upload sonic-vs image
        uses: actions/upload-artifact@v4
        with:
          name: sonic-vs-img
          path: target/sonic-vs.img.gz
          retention-days: 30
          if-no-files-found: error
```

```bash
W=~/scratch/wt-t0
git -C $W add .github/workflows/resolute-build.yml
git -C $W commit -m "build: keep the vs image artifact for 30 days

The t0 workflow tests the vs image of the latest successful push build.
Push builds of 202605_resolute can fail for weeks (the last success is
from 11-09), and a 7-day artifact would leave the nightly run nothing
to test.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Write the workflow**

`.github/workflows/resolute-t0.yml`:

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

permissions: {}

env:
  GH_TOKEN: ${{ github.token }}
  REPO: ${{ github.repository }}
  RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}

jobs:
  resolve:
    if: >-
      github.event_name != 'issue_comment' ||
      (github.event.issue.pull_request && startsWith(github.event.comment.body, '/test-t0'))
    runs-on: ubuntu-latest
    permissions:
      actions: read
      issues: write
      pull-requests: write
      statuses: write
    outputs:
      run_id: ${{ steps.r.outputs.run_id }}
      sha: ${{ steps.r.outputs.sha }}
      sha12: ${{ steps.r.outputs.sha12 }}
      status_sha: ${{ steps.r.outputs.status_sha }}
      known_ref: ${{ steps.r.outputs.known_ref }}
      scope: ${{ steps.r.outputs.scope }}
      pr: ${{ steps.r.outputs.pr }}
      art: ${{ steps.r.outputs.art }}
      art_digest: ${{ steps.r.outputs.art_digest }}
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
              known_ref=$GITHUB_SHA; status_sha=$GITHUB_SHA
              case "$GITHUB_REF_NAME" in ci-workflow/t0-full-*) scope=full ;; *) scope=smoke ;; esac
              case "$GITHUB_REF_NAME" in *-run[0-9]*) run_id=${GITHUB_REF_NAME##*-run} ;; *) run_id=$(latest_push_build) ;; esac ;;
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
          read -r art digest < <(gh api "repos/$REPO/actions/runs/$run_id/artifacts" \
            --jq '[.artifacts[] | select(.name == "sonic-vs-img" and (.expired | not))][0] // empty | "\(.id) \(.digest)"') || true
          [ -n "${art:-}" ] || { say "build run $run_id has no unexpired sonic-vs-img artifact; nothing to test."; exit 0; }
          {
            echo "run_id=$run_id"; echo "sha=$sha"; echo "sha12=${sha:0:12}"; echo "scope=$scope"; echo "pr=$pr"
            echo "known_ref=${known_ref:-$sha}"; echo "status_sha=${status_sha:-$sha}"
            echo "art=$art"; echo "art_digest=$digest"
          } >> "$GITHUB_OUTPUT"

      - name: Mark the commit pending
        if: steps.r.outputs.run_id != ''
        env:
          STATUS_SHA: ${{ steps.r.outputs.status_sha }}
          SCOPE: ${{ steps.r.outputs.scope }}
        run: |
          gh api -X POST "repos/$REPO/statuses/$STATUS_SHA" -f state=pending -f context=resolute-t0 \
            -f target_url="$RUN_URL" -f description="t0 ($SCOPE) on Testflinger: running" >/dev/null

  t0:
    needs: resolve
    if: needs.resolve.outputs.run_id != ''
    runs-on: [self-hosted-linux-amd64-noble-medium]
    timeout-minutes: 1440
    # The machine gets this job's token, so it may only read.
    permissions:
      actions: read
      contents: read
      packages: read
    concurrency:
      group: resolute-t0-${{ needs.resolve.outputs.sha }}
      cancel-in-progress: false
    outputs:
      state: ${{ steps.verdict.outputs.state }}
      description: ${{ steps.verdict.outputs.description }}
    env:
      SHA12: ${{ needs.resolve.outputs.sha12 }}
      KNOWN_REF: ${{ needs.resolve.outputs.known_ref }}
      SCOPE: ${{ needs.resolve.outputs.scope }}
      SECRET: sonic-buildimage/t0-run-${{ github.run_id }}-${{ github.run_attempt }}
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

      - name: Chunk durations from the latest run
        run: |
          set -uo pipefail
          cp "$T0/durations.json" durations.json
          for id in $(gh run list -R "$REPO" -w resolute-t0.yml -s completed -L 10 --json databaseId --jq '.[].databaseId'); do
            rm -rf prev
            if gh run download "$id" -R "$REPO" -p 'resolute-t0-*' -D prev 2>/dev/null; then
              f=$(find prev -name durations.json -size +2c | head -1)
              if [ -n "$f" ]; then
                python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d.update(json.load(open(sys.argv[2]))); json.dump(d, open(sys.argv[1], "w"))' durations.json "$f"
                echo "durations from run $id over the committed ones"; break
              fi
            fi
          done

      - name: Pack the harness and render the job
        env:
          ART: ${{ needs.resolve.outputs.art }}
          ART_DIGEST: ${{ needs.resolve.outputs.art_digest }}
        run: |
          set -euo pipefail
          rm -rf pack && mkdir pack
          cp -a "$T0/." pack/
          rm -rf pack/tests pack/__pycache__
          if gh api "repos/$REPO/contents/$T0/known-failures.yaml?ref=$KNOWN_REF" --jq .content > kf.b64 2>/dev/null; then
            base64 -d kf.b64 > pack/known-failures.yaml
          fi
          cp durations.json pack/durations.json
          tar -czf t0-harness.tar.gz -C pack .
          python3 "$T0/render_job.py" --sha12 "$SHA12" --gh-run "$GITHUB_RUN_ID" --repo "$REPO" --artifact-id "$ART" \
            --artifact-digest "$ART_DIGEST" --scope "$SCOPE" --secret "$SECRET" > job.yaml
          cat job.yaml

      - name: Set up the Testflinger CLI
        uses: canonical/testflinger/.github/actions/testflinger-setup@257ef71c8042a41925d7185d46fc3171ea2112f5 # submit/v1.6.0

      - name: Submit to Testflinger and wait for provisioning
        id: tf
        continue-on-error: true
        env:
          TESTFLINGER_CLIENT_ID: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          TESTFLINGER_SECRET_KEY: ${{ secrets.TESTFLINGER_SECRET_KEY }}
          PROVISION_LIMIT: "25"
          RETRIES: "2"
        run: |
          testflinger secret write --expire-after 86400 "$SECRET" "$GH_TOKEN"
          bash "$T0/submit.sh" job.yaml

      - name: Follow the test phase
        if: steps.tf.outcome == 'success'
        continue-on-error: true
        env:
          TESTFLINGER_CLIENT_ID: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          TESTFLINGER_SECRET_KEY: ${{ secrets.TESTFLINGER_SECRET_KEY }}
          JOB_ID: ${{ steps.tf.outputs.id }}
        run: |
          testflinger poll --phase test "$JOB_ID" 2>/dev/null
          until [[ "$(testflinger status "$JOB_ID")" =~ ^(complete|cancelled)$ ]]; do sleep 30; done

      - name: Cancel the Testflinger job
        if: cancelled() && steps.tf.outputs.id != ''
        env:
          TESTFLINGER_CLIENT_ID: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          TESTFLINGER_SECRET_KEY: ${{ secrets.TESTFLINGER_SECRET_KEY }}
          JOB_ID: ${{ steps.tf.outputs.id }}
        run: testflinger cancel "$JOB_ID"

      - name: Remove the token from Testflinger
        if: always()
        env:
          TESTFLINGER_CLIENT_ID: ${{ secrets.TESTFLINGER_CLIENT_ID }}
          TESTFLINGER_SECRET_KEY: ${{ secrets.TESTFLINGER_SECRET_KEY }}
        run: testflinger secret delete "$SECRET" || true

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
          JOB_STATUS: ${{ job.status }}
        run: |
          set -uo pipefail
          mkdir -p out/results
          infra=""
          if [ "$JOB_STATUS" = cancelled ]; then
            infra="the workflow run was cancelled"
          elif [ -z "$JOB_ID" ]; then
            infra="the Testflinger job was not submitted"
          elif [ "$(jq -r '.provision_status // 1' out/tf-results.json 2>/dev/null)" != 0 ]; then
            infra="provisioning failed or overran on every attempt"
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

  report:
    needs: [resolve, t0]
    if: always() && needs.resolve.outputs.run_id != ''
    runs-on: ubuntu-latest
    permissions:
      actions: read
      issues: write
      pull-requests: write
      statuses: write
    env:
      STATUS_SHA: ${{ needs.resolve.outputs.status_sha }}
      PR: ${{ needs.resolve.outputs.pr }}
    steps:
      - name: Download the report
        if: needs.resolve.outputs.pr != ''
        continue-on-error: true
        uses: actions/download-artifact@v4
        with:
          name: resolute-t0-${{ needs.resolve.outputs.sha12 }}-${{ github.run_attempt }}
          path: out

      - name: Report
        env:
          STATE: ${{ needs.t0.outputs.state }}
          DESC: ${{ needs.t0.outputs.description }}
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

- [ ] **Step 8: Declare the runner label for actionlint**

`.github/actionlint.yaml` lists the `t0` runner label next to the build runner labels:

```yaml
self-hosted-runner:
  labels:
    - self-hosted
    - resolute
    - amd64
    - large
    - self-hosted-linux-amd64-noble-medium
```

- [ ] **Step 9: Lint the workflow**

Run: `docker run --rm -v ~/scratch/wt-t0:/repo:ro -w /repo rhysd/actionlint:latest .github/workflows/resolute-t0.yml`
Expected: no output. Fix every finding (shellcheck findings inside `run:` blocks included) before committing.

- [ ] **Step 10: Commit the workflow**

```bash
W=~/scratch/wt-t0
git -C $W add .github/workflows/resolute-t0.yml .github/actionlint.yaml
git -C $W commit -m "test: run sonic-mgmt t0 on Testflinger nightly, after builds and on /test-t0

Job t0 runs on a regular self-hosted runner and follows the Testflinger
job to the end (self-hosted jobs may run 5 days; the 24 h timeout
bounds the queue wait). Its GITHUB_TOKEN reaches the machine as a
per-run Testflinger secret that expires after a day and is deleted
when the job ends, so t0 may only read actions, contents and packages;
resolve sets the pending status and report posts the result and the PR
comment. The test phase is followed in a separate step so a cancelled
workflow can still cancel the Testflinger job.

Comment triggers need write access, checked with the collaborator
permission API because event payloads show private org members as
CONTRIBUTOR. The machine-side scripts come from the default branch;
only the image and known-failures.yaml come from the commit under
test. ci-workflow/t0-* pushes run the smoke list for development, and
a -run<id> suffix picks the build. The runner label is declared for
actionlint next to the build runner labels.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: M2 — the workflow end to end, smoke

**Files:** fixes to Task 5/6/9 files if the run exposes bugs (committed on `feat/resolute-t0-testflinger`).

**Interfaces:**
- Consumes: Tasks 1–9 and the setup of Task 7. A smoke run fits any `sonic-ci` machine.

- [ ] **Step 1: Push a development branch without the build workflow**

The `-run<id>` suffix of the branch name picks the build: here, the build of the newest unexpired `sonic-vs-img` artifact.

```bash
W=~/scratch/wt-t0
run=$(gh api "repos/canonical/sonic-buildimage/actions/artifacts?name=sonic-vs-img&per_page=1" \
  --jq '.artifacts[0] | select(.expired | not) | .workflow_run.id')
b=ci-workflow/t0-m2-run$run
git -C $W checkout -q -b $b
git -C $W rm -q .github/workflows/resolute-build.yml
git -C $W commit -q -m "test: development branch for the t0 workflow (drop resolute-build so the push does not build)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C $W push -q canonical $b
git -C $W checkout -q feat/resolute-t0-testflinger
gh run list -R canonical/sonic-buildimage --branch $b -L 3
```

Expected: one `resolute-t0` run, no `resolute-build` run.

- [ ] **Step 2: Follow the run**

`gh run watch <id> -R canonical/sonic-buildimage` in the background. The `t0` job gets a runner within seconds; provisioning takes about 20 minutes and the smoke run on the machine about an hour. Do not cancel it without asking the user (AGENTS.md).

- [ ] **Step 3: Check M2 acceptance**

```bash
c=$(git -C ~/scratch/wt-t0 rev-parse ci-workflow/t0-m2-run<build run id>)
gh api repos/canonical/sonic-buildimage/commits/$c/statuses --jq '.[] | select(.context == "resolute-t0") | .state + " " + .description' | head -2
gh run view <id> -R canonical/sonic-buildimage --json jobs --jq '.jobs[] | .name + " " + .conclusion'
gh run download <id> -R canonical/sonic-buildimage -D ~/scratch/t0-m2 && ls -R ~/scratch/t0-m2 | head -30
```

Expected: a `resolute-t0` status (`success`, plus the earlier `pending`) on the pushed commit; `resolve`, `t0` and `report` all `success`; the job summary shows the report; the artifact holds `summary.json`, `report.md`, `durations.json` and `artifacts/{results.tar.zst,run-meta.json,run-t0.log,host-setup.log,tb-1.log,tb-2.log}`; `summary.json` agrees with `report.md` and with the Testflinger job's output.

Result: M2 passed: run 45107247028, 73 minutes from push to report, 12 passed and 1 skipped.

- [ ] **Step 4: Fix, then clean up**

Commit each fix on `feat/resolute-t0-testflinger` and rebase the development branch on it to retest. When M2 passes, delete the branch:

```bash
b=ci-workflow/t0-m2-run<build run id>
git -C ~/scratch/wt-t0 push -q canonical --delete $b
git -C ~/scratch/wt-t0 branch -D $b
```

---

### Task 11: M3 — full run, measured durations and the first known-failures list

**Files:**
- Modify: `.github/testflinger/t0/durations.json`
- Modify: `.github/testflinger/t0/known-failures.yaml`

**Interfaces:**
- Consumes: the workflow (Task 9); the 2026-11-19 rock results in `~/scratch/pr2-split/farm/analysis/rock-*` and `~/scratch/pr2-split/farm/compare-full-a88d1d5f9.txt`.

- [ ] **Step 1: Start the full run**

The branch name starts with `ci-workflow/t0-full-`, which selects `scope=full`. While `sonic-ci` is not synced (Task 7 Step 4), the queue also serves small machines that cannot finish the full list, so a second development-only commit points `job_queue` at one large machine. Leave out the two `sed` lines and that commit once `sonic-ci` lists exactly the 10 machines.

```bash
W=~/scratch/wt-t0
run=$(gh api "repos/canonical/sonic-buildimage/actions/artifacts?name=sonic-vs-img&per_page=1" \
  --jq '.artifacts[0] | select(.expired | not) | .workflow_run.id')
b=ci-workflow/t0-full-m3-run$run
git -C $W checkout -q -b $b
git -C $W rm -q .github/workflows/resolute-build.yml
git -C $W commit -q -m "test: development branch for the t0 workflow (drop resolute-build so the push does not build)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
sed -i 's/^job_queue: sonic-ci$/job_queue: alarmmonkey/' $W/.github/testflinger/t0/job.yaml.in
sed -i 's/== "sonic-ci"$/== "alarmmonkey"/' $W/.github/testflinger/t0/tests/test_render_job.py
git -C $W commit -q -am "test: development branch: run M3 on alarmmonkey

Until the cert team syncs the new sonic-ci members, the queue still
serves eight small machines that cannot finish the full list.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C $W push -q canonical $b
git -C $W checkout -q feat/resolute-t0-testflinger
```

Follow it in the background; expect 4–6 hours from push to report on a 16-testbed machine.

- [ ] **Step 2: Check M3 acceptance and collect the failures**

```bash
gh run download <id> -R canonical/sonic-buildimage -D ~/scratch/t0-m3
jq '.outcome, .totals, .meta.phases, .meta.testbeds, (.new | length)' ~/scratch/t0-m3/*/summary.json
jq -r '.new[] | "\(.outcome)\t\(.id)\t\(.message)"' ~/scratch/t0-m3/*/summary.json > ~/scratch/t0-m3/new.tsv
wc -l ~/scratch/t0-m3/new.tsv
```

Expected: the tests phase finished within 6 hours on a 16-testbed machine (fewer testbeds scale the time up proportionally); `.totals` is close to the 2026-11-19 rock run (1219 passed, 2654 skipped, 31 failed, 17 setup errors).

Result: M3 passed: run 45114609003 on alarmmonkey with 16 testbeds, 4 h 28 min from push to report.

- [ ] **Step 3: Commit the measured durations**

The run's `durations.json` holds the time of every file, with each chunk's pretest and posttest spread over its files. It becomes the committed `durations.json`:

```bash
W=~/scratch/wt-t0
cp ~/scratch/t0-m3/resolute-t0-*/durations.json $W/.github/testflinger/t0/durations.json
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(len(d), round(sum(d.values()) / 3600, 1))' \
    $W/.github/testflinger/t0/durations.json
```

Expected: `389 45.7` (files, testbed-hours).

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/durations.json
git -C $W commit -m "test: size t0 chunks from measured durations and the testbed count

durations.json holds the per-file times of M3 (run 45114609003: 389
files, 45.7 testbed-hours including pretest and posttest). The workflow
lets the newest completed run of any kind override the entries it
measured. run-t0.sh aims each chunk at the estimated total divided by
two rounds per testbed: pretest and posttest cost about 12 min per
chunk, so fewer, larger chunks win. A scheduling model calibrated on
M3 (fit factor 0.82 against the 11-19 file times) gives 3.13 h for 16
testbeds (3.32 h with three rounds, 3.38 h with a fixed 3000 s
target), 3.63 h for 13 and 2.63 h for 20.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Write the first list**

For every line of `new.tsv`, compare with the 2026-11-19 results of the same case (`compare-full-a88d1d5f9.txt` and `farm/analysis/rock-*`). Then:
- a case in a file marked `device_type('physical')` gets no entry: the harness passes `--device_type=vs`, as the upstream PR checker does, so these files are skipped;
- a case that also failed on 2026-11-19 for the same reason becomes an entry with `kind: fail` or `error` and an English `reason` that names the cause;
- a parametrised family with random parameters becomes one `*` entry with `kind: flaky`;
- a case that did not fail on 2026-11-19 is investigated before it goes into the list: a new image or environment problem gets a written reason, or it is fixed first.

M3 had 44 failing cases after the loganalyzer noise filter, and all 44 also failed on the 2026-11-19 rock run. 16 of them sit in physical-only files. The other 28 make 11 entries in `.github/testflinger/t0/known-failures.yaml`:

```yaml
known:
  - id: "database/test_state_db_flush.py::test_state_db_cleanup_after_swss_restart[*]"
    kind: fail
    reason: "branch predates upstream 202605 backport #28740: swss.sh does not clean STATE_DB PROCESS_HEALTH on cold start"
  - id: "gnmi/test_gnmi_aaa.py::test_gnmi_audit_*"
    kind: fail
    reason: "sonic-gnmi predates upstream #750 (no RPC_COMPLETION audit log); on rock the gnmi.log rsyslog rule misses Pebble's tag"
  - id: "pc/test_po_cleanup.py::test_po_cleanup[*]"
    kind: error
    reason: "rock: Pebble stops rsyslogd in parallel with teammgrd, so the cleanTeamProcesses syslog lines are lost"
  - id: "pc/test_po_cleanup.py::test_po_cleanup_after_reload[*]"
    kind: fail
    reason: "rock: Pebble stops rsyslogd in parallel with teammgrd, so the cleanTeamProcesses syslog lines are lost"
  - id: "process_monitoring/test_critical_process_monitoring.py::test_monitoring_critical_processes"
    kind: fail
    reason: "rock: on-failure: shutdown ignores auto_restart=disabled, so killing zebra stops the whole bgp container"
  - id: "radv/test_radv_run.py::test_radv_deployment_id"
    kind: fail
    reason: "test race: radvd respawns 6-7 s after the restart and on resolute the check runs after that"
  - id: "sflow/test_sflow.py::*"
    kind: error
    reason: "setup calls pkgutil.find_loader on the DUT, which Python 3.14 removed"
  - id: "snmp/test_snmp_v2mib.py::test_snmp_v2mib[*]"
    kind: fail
    reason: "SNMP sysDescr distribution: the image side is fixed by sonic-buildimage #34, the test side by sonic-mgmt #4"
  - id: "tacacs/test_authorization.py::test_authorization_tacacs_only[*]"
    kind: fail
    reason: "per-command authorization is bypassed: the bash plugin resolves /usr/bin/* to the uutils binaries, so no rule matches"
  - id: "tacacs/test_authorization.py::test_authorization_tacacs_only_some_server_down[*]"
    kind: fail
    reason: "per-command authorization is bypassed: the bash plugin resolves /usr/bin/* to the uutils binaries, so no rule matches"
  - id: "tacacs/test_authorization.py::test_tacacs_authorization_wildcard[*]"
    kind: fail
    reason: "per-command authorization is bypassed: the bash plugin resolves /usr/bin/* to the uutils binaries, so no rule matches"
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

Run `python3 -m pytest -q .github/testflinger/t0/tests` and re-judge the downloaded M3 results locally with the new list:

```bash
cd ~/scratch/t0-m3 && mkdir -p results && zstd -dc */artifacts/results.tar.zst | tar -x -C results --strip-components=1
python3 ~/scratch/wt-t0/.github/testflinger/t0/verdict.py report --results results \
  --known ~/scratch/wt-t0/.github/testflinger/t0/known-failures.yaml --meta */artifacts/run-meta.json \
  --out-json s.json --out-md r.md --out-durations d.json && jq '.outcome, (.new | length), (.covered | length), .not_run' s.json
```

Expected: `"regressions"`, `16`, `28`, and the three `k8s/` files. M3 ran without `--device_type=vs` and with the 392-file list. The 16 new cases are all in physical-only files, and the three `k8s/` files are under `run_tests.sh`'s `SKIP_FOLDERS`. The harness of Task 6 leaves out both groups, so only the 28 covered cases remain.

- [ ] **Step 5: Commit and clean up**

```bash
W=~/scratch/wt-t0
git -C $W add .github/testflinger/t0/known-failures.yaml
git -C $W commit -m "test: first t0 known-failures list, from M3 and the 11-19 run

M3 (run 45114609003, PR #34 image d47807d2e1, sonic-mgmt a88d1d5f93,
alarmmonkey, 16 testbeds) had 44 failing cases once the loganalyzer
noise filter caught the tests with their own analyzer. All 44 also
failed on the 11-19 rock run. 16 of them come from the 23 physical-only
files of the t0_checker list, which --device_type=vs skips. The other
28 make 11 entries; 25 of them failed on the 11-19 Dockerfile image
too.

Known causes: per-command TACACS authorization bypassed through uutils
paths; SNMP sysDescr distribution (sonic-buildimage #34 plus sonic-mgmt
#4); Python 3.14 dropping pkgutil.find_loader (sflow setup); a radv
test race; our branch forking from upstream 202605 at ba3fb8d5f5,
before #28740 added PROCESS_HEALTH to the STATE_DB cleanup in swss.sh;
src/sonic-gnmi 3ce95be predating upstream #750 (RPC_COMPLETION
records), while on rock Pebble tags gnmi-native so the gnmi.log rule
never fires; the teamd rock stopping rsyslogd in parallel with
teammgrd (test_po_cleanup); and on-failure: shutdown ignoring
auto_restart, so killing zebra stops the whole bgp container.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
b=$(git -C $W branch --list 'ci-workflow/t0-full-m3-run*' --format='%(refname:short)')
git -C $W push -q canonical --delete $b
git -C $W branch -D $b
```

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

The body states the current state only: what runs when, where the results appear, the one-time setup already done (Task 7), the M1–M3 results with run links, and how to maintain `known-failures.yaml`, `durations.json` and `sonic-mgmt.ref`. It ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 2: After the user merges, check M4**

```bash
gh run list -R canonical/sonic-buildimage -w resolute-t0.yml -L 10 --json databaseId,event,conclusion,createdAt
```

Expected within about a day: one `schedule` run, one `workflow_run` run after a merge to `202605_resolute`, and one `issue_comment` run after the user (or the agent, with the user's go-ahead) comments `/test-t0 smoke` on an open PR; each with a report, a `resolute-t0` commit status, and for the comment run, the PR comment marked `<!-- resolute-t0 -->`.

Result: M4 is open.

- [ ] **Step 3: Record the outcome**

Update the memory file `resolute-nightly-testflinger-design.md` with the PR number, the M1–M4 results and anything the runs taught that is not in the code.
