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


def test_a_job_taken_by_an_agent_is_followed(tmp_path):
    p, calls, out = run(tmp_path, [{"states": ["waiting", "running", "setup", "provision", "test"], "results": {}}])
    assert p.returncode == 0, p.stdout + p.stderr
    assert [c[0] for c in calls].count("submit") == 1
    assert not any(c[0] == "cancel" for c in calls)


def test_a_failed_attempt_is_cancelled_before_resubmitting(tmp_path):
    failed = {"states": ["provision", "complete"], "results": {"setup_status": 0, "provision_status": 1}}
    p, calls, _ = run(tmp_path, [failed, {"states": ["test"], "results": OK}], RETRIES="1")
    assert p.returncode == 0, p.stdout + p.stderr
    assert calls.index(["cancel", "job1"]) < [i for i, c in enumerate(calls) if c[0] == "submit"][1]
