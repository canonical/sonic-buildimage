"""Work stealing between the testbed VMs of one image (runs on the Testflinger host).

A VM whose run has finished takes the second half of the files not yet started by the slowest run of the same
image (never the donor's next file). The donor's own copies of those files are renamed to *.stolen, so its
run_tests.sh gets "file not found" for them and moves on; nothing is killed. Results the donor writes for stolen
files are listed under "stolen" in ~/bal/state.json and must be dropped.

A run that run_tests.sh cut short after a failed sanity check (or an unusable duthosts/ptfhost) leaves its VM out
of further work; its files not yet started go to the next idle VM of the same image.

Runs are grouped by image and test group (e.g. rock/t1); work only moves within a group. With $BAL_DIR/config.json
(default ~/bal) the jobs come from it: {"jobs": {vm: {"image", "group", "label", "shard", "testbed", "duts", "marks",
"pytest_extra"}}}; without it, the t0 layout of tb1..tb12.

usage: python3 balancer.py            # loop until every run is finished
       python3 balancer.py --dry      # print what each VM is doing and exit
"""
import os
import json
import re
import sys
import subprocess
import time
from pathlib import Path

HOME = Path.home()
BAL = Path(os.environ.get("BAL_DIR", str(HOME / "bal")))
STATE = BAL / "state.json"
LOG = BAL / "balancer.log"
CONFIG = BAL / "config.json"
T0 = {"group": "t0", "testbed": "vms-kvm-t0", "duts": "vlab-01", "marks": "t0,any", "pytest_extra": ""}
SHARDS = Path("/srv/share/shards")
# test modules other modules import: renaming one breaks collection of its importers, so never hand them over
IMPORTED = set(Path("/srv/share/imported_tests.txt").read_text().split())
VM_HOME = "/home/sheldon-qi"
MIN_STEAL = 4
RUNNING = re.compile(r"^Running: python3 -m pytest (\S+)", re.M)


def log(message):
    with LOG.open("a") as f:
        f.write("{} {}\n".format(time.strftime("%H:%M:%S"), message))


def vm_sh(vm, script, check=False):
    return subprocess.run(["sudo", "lxc", "exec", vm, "--", "bash", "-c", script], capture_output=True, text=True,
                          check=check, timeout=120).stdout


def initial_state():
    if CONFIG.exists():
        jobs = json.loads(CONFIG.read_text())["jobs"]
        for job in jobs.values():
            job.update({"files": (SHARDS / job.pop("shard")).read_text().split(), "stolen": [],
                        "runlog": "{}/run.log".format(VM_HOME), "history": [], "broken": False})
        return {"jobs": jobs, "queue": {}, "runs": 0, "handoffs": []}
    jobs = {}
    for i in range(1, 13):
        image, n = ("rock", i) if i <= 6 else ("df", i - 6)
        label = "{}-{}".format(image, n)
        files = (SHARDS / "shard-{}".format(label)).read_text().split()
        jobs["tb{}".format(i)] = dict(T0, image=image, label=label, files=files, stolen=[],
                                      runlog="{}/run.log".format(VM_HOME), history=[], broken=False)
    return {"jobs": jobs, "queue": {}, "runs": 0, "handoffs": []}


def pool(job):
    return "{}/{}".format(job["image"], job.get("group", "t0"))


def progress(vm, job):
    """Files started so far, and whether run_tests.sh / pytest are still running in the VM."""
    text = vm_sh(vm, "cat {} 2>/dev/null; echo @@ps@@; docker exec sonic-mgmt ps -eww -o args".format(job["runlog"]))
    log_text, _, ps = text.partition("@@ps@@")
    started = RUNNING.findall(log_text)
    job["aborted"] = "Skip rest of the scripts" in log_text
    runner = any(line.startswith("/bin/bash ./run_tests.sh") and "-p logs/{} ".format(job["label"]) in line
                 for line in ps.splitlines())
    pytest = any(line.startswith("python3 -m pytest") and "logs/{}/".format(job["label"]) in line
                 for line in ps.splitlines())
    return started, runner, pytest


def hide_files(vm, files):
    vm_sh(vm, "cd {}/sonic-mgmt/tests && for f in {}; do [ -e $f ] && mv $f $f.stolen; done; true"
          .format(VM_HOME, " ".join(files)))


def start_run(vm, job, label, files):
    runlog = "{}/run-{}.log".format(VM_HOME, label)
    tests = " ".join(files)
    job = dict(T0, **job)
    extra = " -e '{}'".format(job["pytest_extra"]) if job["pytest_extra"] else ""
    cmd = ("cd /data/sonic-mgmt/tests && ./run_tests.sh -n {} -d {} -f vtestbed.yaml -i ../ansible/veos_vtb -t {} "
           "-m individual -O -p logs/{}{} -c '{}'".format(job["testbed"], job["duts"], job["marks"], label, extra, tests))
    vm_sh(vm, "setsid nohup docker exec --user sheldon-qi sonic-mgmt bash -c \"{}\" > {} 2>&1 < /dev/null &"
          .format(cmd, runlog))
    return runlog


def step(state):
    jobs, queue = state["jobs"], state["queue"]
    status = {vm: progress(vm, job) for vm, job in jobs.items()}
    for vm, job in jobs.items():
        started, runner, pytest = status[vm]
        if not (runner or pytest) and job.get("aborted") and not job["broken"]:
            job["broken"] = True
            orphans = [f for f in job["files"] if f not in started and f not in job["stolen"]]
            queue.setdefault(pool(job), []).extend(orphans)
            log("{} {}: run cut short by run_tests.sh; {} files requeued".format(vm, job["label"], len(orphans)))
    for vm, job in jobs.items():
        started, runner, pytest = status[vm]
        if runner or pytest or job["broken"]:
            continue
        if queue.get(pool(job)):
            give, queue[pool(job)] = queue[pool(job)], []
            source = "queue"
        else:
            donors = []
            for other, ojob in jobs.items():
                ostarted, orunner, opytest = status[other]
                if other == vm or pool(ojob) != pool(job) or not orunner:
                    continue
                remaining = [f for f in ojob["files"] if f not in ostarted and f not in ojob["stolen"]][1:]
                remaining = [f for f in remaining if f not in IMPORTED]
                if len(remaining) >= MIN_STEAL:
                    donors.append((len(remaining), other, remaining))
            if not donors:
                continue
            _, source, remaining = max(donors)
            give = remaining[len(remaining) // 2:]
            hide_files(source, give)
            jobs[source]["stolen"].extend(give)
        state["runs"] += 1
        label = "{}-{}-x{}".format(job.get("group", "t0"), job["image"], state["runs"])
        state.setdefault("handoffs", []).append({"from": source, "from_label": jobs[source]["label"] if source != "queue"
                                                 else "queue", "to": vm, "to_label": label, "files": give})
        job["history"].append("{} (from {})".format(label, source))
        job.update({"label": label, "files": give, "stolen": [], "runlog": start_run(vm, job, label, give),
                    "aborted": False})
        log("{} takes {} files from {} as {}: {} .. {}".format(vm, len(give), source, label, give[0], give[-1]))
        status[vm] = ([], True, False)
    return all(not (runner or pytest) for _, runner, pytest in status.values()) and not any(queue.values())


def main():
    STATE.parent.mkdir(exist_ok=True)
    state = json.loads(STATE.read_text()) if STATE.exists() else initial_state()
    if "--dry" in sys.argv:
        for vm, job in state["jobs"].items():
            started, runner, pytest = progress(vm, job)
            left = [f for f in job["files"] if f not in started and f not in job["stolen"]]
            print(vm, job["label"], "runner" if runner else "-", "pytest" if pytest else "-",
                  "started={} left={} now={}".format(len(started), len(left), started[-1] if started else None))
        return
    while True:
        try:
            done = step(state)
        except (subprocess.SubprocessError, OSError) as error:
            log("error: {!r}".format(error))
            done = False
        STATE.write_text(json.dumps(state, indent=1))
        if done:
            log("all runs finished")
            return
        time.sleep(10)


if __name__ == "__main__":
    main()
