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
