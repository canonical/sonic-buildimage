# Automated sonic-mgmt t0 runs on Testflinger for `202605_resolute` — design

- Date: 2026-11-20
- Repository: `canonical/sonic-buildimage` `202605_resolute` holds the workflow, the Testflinger harness and the known-failures list
- Test code: `canonical/sonic-mgmt` at a pinned commit. The first pin is `a88d1d5f93`, the head of the PR stack #5–#9
- Image under test: the rock vs image (`sonic-vs-img` artifact) produced by the `resolute-build` workflow
- This English version is the single source of truth; the Chinese version (`-zh.md`) is a translation

## 1. Goal and scope

Run the upstream KVM t0 PR-checker test list against the vs image that `resolute-build` produces, on Testflinger hardware, with no manual steps. Runs start every night, after every successful build of a push or tag, and on request from a pull request comment. Each run reports regressions against a reviewed list of known failures.

**In scope:**

1. A GitHub Actions workflow that picks the build, submits one Testflinger job, waits for it, judges the results and reports them.
2. The Testflinger job and the harness that runs on the reserved machine. The harness sets up the host, builds the testbeds, runs the tests and packs the results.
3. The verdict logic and the known-failures list.
4. One-time setup: the Testflinger queue, the cEOS image and its access, and the Testflinger credentials.

**Out of scope:** the Dockerfile (supervisord) image, because CI builds only the rock image; topologies other than t0 (dualtor, t0-2vlans, t0-sonic, t1-lag); arm64; the broadcom image and physical DUTs; changes to `resolute-build.yml` other than the artifact retention; upstreaming.

## 2. Decisions

| Topic | Decision |
|---|---|
| Size of a run | One Testflinger machine, the rock vs image, and the full upstream t0 checker list. The list comes from `get_test_scripts.py` at the pinned sonic-mgmt commit, minus the folders `run_tests.sh` never runs (389 files at `a88d1d5f93`) |
| Image | The latest successful `sonic-vs-img` artifact. No rebuild. `resolute-build` keeps the artifact for 30 days |
| Triggers | Nightly schedule; `resolute-build` success on a push to `202605_resolute` or a `v*` tag; a `/test-t0` pull request comment; manual dispatch |
| Who may trigger from a comment | Users whose permission on the repository is `write`, `maintain` or `admin` |
| Pass/fail | A known-failures list kept in the repository. Failed files are rerun once. A failure that the list does not cover makes the run red |
| Where things live | Everything in `canonical/sonic-buildimage`, including the pinned sonic-mgmt commit |
| Runners | Job `t0` runs on the regular Canonical runner `self-hosted-linux-amd64-noble-medium` from submission to verdict. Jobs `resolve` and `report` run on `ubuntu-latest` |
| Machines | Testflinger queue `sonic-ci` |
| Image and cEOS on the machine | The machine downloads the build artifact and pulls the cEOS image itself, with the `t0` job's `GITHUB_TOKEN`. That token can only read actions, contents and packages, expires when the job ends, and reaches Testflinger as a per-run secret. No personal access token is involved |
| cEOS | `ghcr.io/canonical/sonic-ceos:4.32.5M-1`, visibility internal, with Actions read access granted to `canonical/sonic-buildimage`. This is the `ceosimage:4.32.5M-1` image that sonic-mgmt itself builds from the cEOS tarball; sonic-mgmt finds it locally under that tag and skips its own cEOS preparation |
| Provisioning | 25 minutes per attempt; after that, or after a failed attempt, the job is cancelled and submitted again, at most twice. Waiting in the queue has no limit |
| Logs | All results and logs, compressed with zstd, returned through Testflinger artifacts |
| Chunk durations | `durations.json` in the harness, measured on the M3 run; the newest completed run of any kind overrides the entries it measured. Each chunk aims at the estimated total divided by two rounds per testbed |

## 3. Verified facts

| Fact | Evidence |
|---|---|
| The 392-file list costs 40.7 testbed-hours per image; the legacy 271-file list costs 33.7 | Sum of JUnit file times of the rock run on 2026-11-19 (the 125 files beyond the legacy list add 7.0 h) |
| On a 16-testbed machine the 389 files take 45.7 testbed-hours including pretest and posttest; pretest takes about 7 minutes and posttest about 5 per chunk | M3, run 45114609003 (alarmmonkey) |
| Regular Canonical runners pick up a job within seconds. The private-endpoint pool is small and reserved for jobs that need internal endpoints | `canonical/self-hosted-github-runner-docs`; a job on `private-endpoint-small` waited 18 minutes without a runner, while `noble-medium` started within 5 seconds (runs 45097064692 and 45099274044) |
| A job on a self-hosted runner may run for up to 5 days; `timeout-minutes` defaults to 360 and must be raised | GitHub Actions usage limits; the runner documentation |
| The maas2 provisioning timeout (60 minutes) comes from the agent configuration (`timeout_min`) and cannot be set per job; the `canonical/testflinger` submit action adds no limit of its own | `device-connectors/.../maas2/maas2.py`; `.github/actions/submit/action.yaml` |
| Successful deploys on the `sonic-ci` machines took 3.4–26.5 minutes (p90 16.1); 49 of 50 failed provisions ran 62–66 minutes before failing; our 28 resolute installs took at most 17.7 minutes in MAAS and 19.6 minutes for the whole provision phase | Testflinger results kept since 2026-11-16 for the 11 `sonic-ci` agents; our own job logs |
| The `sonic-ci` agents have `global_timeout` 43200 s and `output_timeout` 8000 s | `testflinger-agent.conf` of each agent in `canonical/testflinger-agent-charm-configs` |
| The agent uploads the `artifacts/` directory as one tarball; the server accepts up to 500 MB per request by default | Agent `save_artifacts`; server `MAX_BODY_SIZE` |
| All results of one image (389 files, JUnit and logs) take 1198 MB, or 17 MB after `zstd -19` | The rock results of 2026-11-19 |
| Downloading a workflow artifact needs a token even on a public repository (anonymous: 401; a classic PAT with only `read:packages`: 403, "actions scope"). The API answers with a redirect to a signed blob URL that is valid for minutes. A `GITHUB_TOKEN` with `actions: read` works from any host | Tests on 2026-11-23; M2, run 45107247028 |
| GHCR accepts only classic PATs among personal tokens. A workflow's `GITHUB_TOKEN` can pull a package that grants the repository Actions access. GHCR ignores the user name of a token login | GitHub documentation; a pull with a deliberately wrong user name; M2 |
| A push by an org member creates an internal GHCR package; anonymous pulls are refused | Probe package `ghcr.io/canonical/sonic-ci-probe` (deleted after the test) |
| On a reserved machine: nested KVM is enabled; MAAS configures the apt proxy `http://10.239.8.11:8000/`, which cannot resolve download.docker.com for HTTPS; GitHub, download.docker.com, azurecr.io, ghcr.io, PyPI and Testflinger are reachable directly; downloads from GitHub run at about 5.9 MB/s | Probe job on romano, 2026-11-20; M1 |
| A queue added in the C3 "Customized queues" field reaches the agent only after the certification bot syncs `testflinger-agent-charm-configs`, and the sync has no fixed schedule | Commit history of `server-cert/data-tor3-dh1` |
| `author_association` in event payloads shows private org members as `CONTRIBUTOR` | 3 of 4 active members of this repository have private membership |
| `get_test_scripts.py --features "" --location <tests>` run in the docker-sonic-mgmt image gives the same 392-file `t0_checker` list. `run_tests.sh` silently drops every file under its `SKIP_FOLDERS` (`ptftests acstests saitests scripts k8s sai_qualify`), which removes the 3 k8s files | Run at `a88d1d5f93`; `tests/run_tests.sh` |
| The upstream KVM PR checker adds `--device_type=vs`, which skips tests marked `device_type('physical')` before their fixtures run; 23 files of the `t0_checker` list carry that mark | `.azure-pipelines/test_plan.py`; `tests/common/plugins/custom_markers` |
| sonic-mgmt uses a local image tagged `ceosimage:4.32.5M-1` and then skips downloading, importing and building cEOS | `ansible/roles/vm_set/tasks/add_ceos_list.yml` |
| add-topo runs `docker-ptf` with the tag of the sonic-mgmt branch (`202605`), not `latest` | `ansible/roles/vm_set/tasks/add_topo.yml` |
| Until sonic-buildimage PR #30 merges, the run has dozens of loganalyzer errors whose only matched line is `nss_tacplus: /etc/tacplus_nss.conf fopen failed`, on different cases each time. Tests with their own LogAnalyzer report them as `LogAnalyzerError: match: N`, with the full lines in the `E` block of the traceback | 36 such errors on 2026-11-19; `test_pktgen` and the mocked temperature test on M3 |
| JUnit test cases have `classname="tests.<module path in dots>[.<class>]"`; `run_tests.sh -m individual` writes one JUnit file per test file, at the test file's path | The results of 2026-11-19 |

## 4. Architecture

```
trigger (schedule / workflow_run / issue_comment / workflow_dispatch)
  │
  ▼
resolve (ubuntu-latest): pick the build and its artifact; authorise a comment trigger;
                         commit status "resolute-t0" = pending
  │
  ▼
t0 (noble-medium, timeout 1440 min, token: actions/contents/packages read)
  1. unit tests; durations; pack the harness and the known-failures list; render the job
  2. write this job's GITHUB_TOKEN to a per-run Testflinger secret
  3. submit.sh: submit, 25 min per provisioning attempt, 2 retries ───► Testflinger
                                                                          │
     reserved machine, queue sonic-ci, Ubuntu 26.04 ◄─────────────────────┘
       host setup → artifact download and cEOS pull with the token →
       testbeds in LXD VMs → chunked t0 run → reruns → results.tar.zst
                                                                          │
  4. follow the test phase; delete the secret                             │
  5. download the Testflinger artifacts ◄─────────────────────────────────┘
  6. verdict against known-failures.yaml; job summary; workflow artifact
  │
  ▼
report (ubuntu-latest): final commit status; sticky PR comment
```

Trust boundary: every script that runs on the machine comes from the default branch (`202605_resolute` at the time of the run), because `schedule`, `workflow_run` and `issue_comment` all run the workflow file from the default branch. Only two things come from the commit under test: the vs image, and `known-failures.yaml`, which is data. Only users with write access can start a run from a comment. The machine holds the `t0` job's token, which can only read and dies with that job; writing statuses and comments happens in the other two jobs.

## 5. Workflow `.github/workflows/resolute-t0.yml`

### 5.1 Resolving the build

| Trigger | Condition | Build under test |
|---|---|---|
| `schedule` | Daily at 15:00 UTC | The latest successful `resolute-build` run of event `push` on `202605_resolute` |
| `workflow_run` | `resolute-build` completed with `success`, event `push`, on `202605_resolute` or a `v*` tag | The triggering run |
| `issue_comment` | Comment on a pull request whose body starts with `/test-t0` (`smoke` on the first line selects the smoke list) | The latest successful `resolute-build` run whose head SHA equals the PR head SHA |
| `workflow_dispatch` | Manual; input `run_id` (a `resolute-build` run); input `scope` = `full` or `smoke` | The given run, or the latest push build |
| `push` | A branch named `ci-workflow/t0-*`; development only. `smoke`, or `full` when the branch is named `ci-workflow/t0-full-*`. The commit status and the known-failures list both use the pushed commit | The build run named by a `-run<id>` suffix of the branch, otherwise the latest successful push build of `202605_resolute` |

For a comment trigger, the workflow first checks `GET /repos/{repo}/collaborators/{user}/permission` and stops unless the result is `admin`, `maintain` or `write`. Next it adds an "eyes" reaction to the comment. If no successful build exists for the head SHA, or its artifact has expired, it replies on the pull request and stops.

### 5.2 Steps

**`resolve`** (permissions: `actions: read`, `issues: write`, `pull-requests: write`, `statuses: write`)

1. Resolve the build (5.1). The outputs are the commit SHA, the build run id, the `sonic-vs-img` artifact id and the digest GitHub recorded for it.
2. Set the commit status `resolute-t0` to `pending`, with a link to this run.

**`t0`** (permissions: `actions: read`, `contents: read`, `packages: read`)

1. Run the unit tests of the harness (7.6) before using a machine.
2. Build `durations.json`: start from the harness copy and let the `durations.json` of the newest completed `resolute-t0` run, of any kind, override the entries it has.
3. Build `t0-harness.tar.gz`: the contents of `.github/testflinger/t0/` from the default branch, `known-failures.yaml` from the commit under test, and `durations.json`.
4. Render the Testflinger job (6.1).
5. Write the job's `GITHUB_TOKEN` to the Testflinger secret `sonic-buildimage/t0-run-<run id>-<attempt>`, expiring after one day, with the CI client id and key from repository secrets.
6. `submit.sh` submits the job and returns when its test phase starts. A provision phase longer than 25 minutes is cancelled; a cancelled or failed setup or provision is submitted again, at most twice. If the step is interrupted, it cancels the Testflinger job.
7. Follow the test phase until the job completes; if the workflow is cancelled, cancel the Testflinger job.
8. Delete the secret, whatever happened before.
9. Download the Testflinger results and artifacts (`testflinger results`, `testflinger artifacts`).
10. Run the verdict (7.3) and write the job summary.
11. Upload a workflow artifact `resolute-t0-<sha12>-<attempt>` (`summary.json`, `report.md`, `durations.json` and the Testflinger artifacts), kept for 30 days.

**`report`** (permissions: `actions: read`, `issues: write`, `pull-requests: write`, `statuses: write`)

1. Set the final commit status from the outcome of `t0`; a `t0` that did not finish gives `error`.
2. For a comment trigger, create or update the single PR comment marked `<!-- resolute-t0 -->`.

Job settings: `t0` has `timeout-minutes: 1440` and the concurrency group `resolute-t0-<sha>` with `cancel-in-progress: false`; `report` runs whenever `resolve` picked a build, including after a cancelled or timed-out `t0`.

## 6. Testflinger job and harness

### 6.1 Job file

```yaml
job_queue: sonic-ci
global_timeout: 43200
output_timeout: 7200
tags: [sonic-buildimage-t0, "sha:<sha12>", "gh-run:<run id>"]
provision_data:
  distro: resolute
test_data:
  attachments:
    - local: t0-harness.tar.gz
  secrets:
    GH_TOKEN: sonic-buildimage/t0-run-<run id>-<attempt>
  test_cmds: |
    <agent side, 6.2>
```

`render_job.py` validates every value it puts into the template: the SHA, run id, repository name, artifact id and digest, scope and secret path.

### 6.2 Agent side (`test_cmds`)

The agent side does as little as possible:

1. Copy the attachment to the machine (`ubuntu@$DEVICE_IP`, `BatchMode=yes`).
2. Start `run-t0.sh` there, detached (`setsid nohup`), with the repository, the artifact id and digest, and the run scope. `GH_TOKEN` goes over the SSH session's stdin into the environment of the detached process, never onto a command line. A dropped SSH connection therefore does not stop the run.
3. Every minute, fetch the new lines of the machine's `progress.log` and print them, until the harness writes its `EXIT` file.
4. Copy `results.tar.zst`, `run-meta.json`, the harness logs and the per-testbed logs into `artifacts/`, whatever the exit status.

### 6.3 Harness on the machine (`run-t0.sh`)

1. **Host setup.** These fixes come from the 2026-11-10/11-19 runs and M1:
   - growpart the root filesystem of each LXD VM;
   - let `lxdbr0` through the `DOCKER-USER` chain;
   - keep the MAAS apt proxy for HTTP in the VMs and send HTTPS direct;
   - install docker-ce from download.docker.com;
   - after the first install of openvswitch-switch, run `reset-failed` and restart it;
   - pull `publicmirror.azurecr.io/debian:trixie` before add-topo;
   - preload `docker-sonic-mgmt:latest` and `docker-ptf:202605`, the tag add-topo runs;
   - disable `apt-daily*` and `unattended-upgrades` in the VMs;
   - put the VMs on a zfs pool built from the spare SSDs of at least 200 GB when the machine has any, otherwise on the LXD `default` dir pool on the root SSD; rotational disks are never used.
2. **Sizing.** Testbeds T = min(⌊(RAM GiB − 16) / 18⌋, ⌊threads / 8⌋, ⌊free pool GB / 40⌋). Each VM gets ⌊threads / T⌋ vCPUs, 18 GiB of RAM and a 140 GiB sparse disk. In `scope=smoke`, T is at most 2. T is printed and recorded in `run-meta.json`.
3. **Payload.**
   - Ask the GitHub API for the artifact's download URL with `GH_TOKEN` and download the zip right away, retrying with a fresh URL. Check the zip against the artifact digest, extract `sonic-vs.img.gz` and record its SHA-256.
   - `docker pull` the cEOS image with the same token, using a docker config directory in `/dev/shm` that is deleted right after the pull. Then drop the token, so it is never written to disk and never enters a VM. Tag the image `ceosimage:4.32.5M-1` and save it to the share that the VMs mount read-only.
   - Download sonic-mgmt as a GitHub tarball of the pinned commit into the share. Apply the testbed settings of the upstream KVM guide with `configure_sonic_mgmt.py`: the VM host user and password, `ansible_python_interpreter`, and the git-ignored `ansible/password.txt`. The VMs copy the tree with `cp -a`, which keeps every symlink.
4. **Test list.** Run `get_test_scripts.py --features ""` in the docker-sonic-mgmt image at the pinned commit, take its `t0_checker` list and drop the files under `run_tests.sh`'s `SKIP_FOLDERS`. In `scope=smoke` the list is `smoke.txt`: 4 short files; `run_tests.sh` adds pretest and posttest itself.
5. **Chunks.** Pack the files longest first, using `durations.json` (480 s for a file with no entry), into chunks of the estimated total divided by 2 × T. Pretest and posttest cost about 12 minutes per chunk, so fewer, larger chunks finish sooner: a scheduling model calibrated on M3 gives 3.1 hours of tests for 16 testbeds, against 3.9 hours on M3 with flat estimates. In `scope=smoke` every file is its own chunk. Chunks go into a shared queue, longest first; each testbed takes the next chunk with an atomic rename.
6. **Execution.** Each testbed runs add-topo and deploy-mg once, then runs its chunks with `run_tests.sh -t t0,any -e --device_type=vs -m individual`, as the upstream PR checker does. After a chunk, `verdict.py rerun-files` lists the files with failures or errors that the known-failures list does not cover; the testbed restores the DUT configuration with deploy-mg and reruns those files once. The final result of a case is the result of its last run. The first result is kept for the report. If a testbed dies in the middle of a chunk, the chunk goes back to the queue once.
7. **Time guard.** 10.5 hours after the harness starts, no new chunks are handed out. The files that were never started are recorded as "not run".
8. **Progress.** Every 5 minutes, append one line with the chunks pending, running and done, and the testbeds finished, to `progress.log`. The agent prints these lines, which also keeps `output_timeout` from firing.
9. **Output.**
   - `results.tar.zst`: every JUnit file and log, per testbed and chunk, plus the start and end time of each chunk;
   - `run-meta.json`: the machine, T, the artifact id, the image SHA-256, the sonic-mgmt commit, the scope, the full file list, phase times, whether the time guard fired, and the harness exit code. The harness exits with 3 when no chunk finished on any testbed.

The runner, not the machine, parses the JUnit files: `verdict.py report` writes `summary.json` (outcome and per-case results) and `durations.json` (per-file times of this run, with each chunk's pretest and posttest spread over its files).

### 6.4 Files

```
.github/workflows/resolute-t0.yml
.github/testflinger/t0/
  job.yaml.in            job template (6.1)
  render_job.py          renders job.yaml.in
  submit.sh              submission with the provisioning limit and retries (5.2)
  agent.sh               agent side (6.2)
  run-t0.sh              entry on the machine (6.3)
  host-setup.sh          host fixes, storage pool, sizing
  configure_sonic_mgmt.py  testbed settings for the sonic-mgmt tree
  tb-run.sh              per-testbed worker: add-topo, deploy-mg, chunk loop, rerun
  make_chunks.py         chunk packing
  durations.json         per-file times measured on M3
  verdict.py             rerun selection, verdict and report rendering (7)
  tests/                 pytest unit tests
  known-failures.yaml    reviewed known failures (7.1)
  sonic-mgmt.ref         pinned canonical/sonic-mgmt commit SHA
  smoke.txt              the smoke list
```

## 7. Verdict and reporting

### 7.1 `known-failures.yaml`

```yaml
known:
  - id: "snmp/test_snmp_v2mib.py::test_snmp_v2mib[*]"
    kind: fail
    reason: "SNMP sysDescr distribution: the image side is fixed by sonic-buildimage #34, the test side by sonic-mgmt #4"
  - id: "sflow/test_sflow.py::*"
    kind: error
    reason: "setup calls pkgutil.find_loader on the DUT, which Python 3.14 removed"
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

- `id`: pytest node id relative to `tests/`, as built from the JUnit file path, class name and test name. `*` matches any text; every other character, including `[` and `]`, matches itself.
- `kind`: `fail` (test failure), `error` (setup or teardown error), or `flaky` (any outcome is accepted, and passing produces no notice).
- `reason`: required, written in English.
- `loganalyzer_noise`: regular expressions for syslog lines. A loganalyzer teardown error whose matched lines all match one of these patterns is ignored. So is a `LogAnalyzerError` raised by a test's own analyzer, when nothing expected is missing, the full syslog lines in its traceback number exactly the reported matches, and every one matches a pattern. Any other matched line keeps the error.
- Every change to the list goes through a pull request.

### 7.2 Classification of each case

A case whose final outcome is failure or error is **covered** when an entry with a matching `id` has the same `kind` or `flaky`. Otherwise it is **new**. Entries are reported in two more groups:

- **now passing**: entries of kind `fail` or `error` whose `id` matches at least one case, where every matching case passed;
- **stale**: entries whose `id` matches no case, although their file part matches a file that ran. Entries for files outside this run's list (for example in `scope=smoke`) are not reported.

### 7.3 Outcome of a run

| Condition | Commit status | Summary title |
|---|---|---|
| At least one new failure or error | `failure` | Regressions |
| No new failures, and some files were not run | `error` | Incomplete |
| The job was not submitted, provisioning failed or overran on every attempt, the workflow was cancelled, no `run-meta.json` came back, or the harness exited non-zero | `error` | Infrastructure |
| Otherwise | `success` | Pass |

"Now passing" and "stale" entries never change the outcome; they are listed so that the list can be cleaned up.

### 7.4 Report

The job summary and the PR comment show:

- the outcome, with totals of passed, skipped, failed, errored and not run;
- new failures, with the first line of each message and the file log name;
- covered failures, collapsed;
- "now passing" and "stale" entries;
- cases that passed only on the rerun;
- the machine, testbed count, image SHA-256, sonic-mgmt commit and phase times.

### 7.5 First version of the list

The first list comes from M3 (run 45114609003: image `d47807d2e1`, the head of sonic-buildimage PR #34; sonic-mgmt `a88d1d5f93`; alarmmonkey with 16 testbeds). After the loganalyzer noise filter, 44 cases failed. All 44 also failed on the rock run of 2026-11-19, and 41 of them also failed on that day's Dockerfile image. 16 of them are in physical-only tests, which M3 ran because it did not pass `--device_type=vs`; the harness now skips them as upstream does. The remaining 28 cases form the list (11 entries), and judged against it M3 has no new failures.

| Group | Cases | Reason |
|---|---|---|
| TACACS per-command authorization | 3 | The bash plugin resolves `/usr/bin/*` to the uutils binaries, so no server rule matches; a product issue |
| SNMP sysDescr distribution | 1 | Image side fixed by sonic-buildimage #34, test side by sonic-mgmt #4 |
| sflow | 14 | Setup calls `pkgutil.find_loader`, which Python 3.14 removed |
| radv deployment id | 1 | Test race: the check runs after radvd has respawned |
| STATE_DB `PROCESS_HEALTH` after a swss restart | 1 | The branch forked from upstream 202605 before the backport #28740 that cleans it in `swss.sh` |
| gNMI audit log | 5 | `src/sonic-gnmi` predates upstream #750, which writes the `RPC_COMPLETION` records; on rock, the rsyslog rule for `/var/log/gnmi.log` matches the supervisord message format and misses Pebble's tag |
| `test_po_cleanup` (rock) | 2 | The teamd rock does not order its daemons after rsyslogd, so Pebble stops rsyslogd in parallel and teammgrd's cleanup lines are lost |
| `staticd` state (rock) | 1 | Rock services use `on-failure: shutdown` and the Pebble exit listener ignores `auto_restart`, so killing zebra stops the whole bgp container |

The two groups where the branch predates upstream go away with the next upstream merge; the three rock groups need fixes in the rock definitions and the Pebble exit listener.

### 7.6 Unit tests

pytest covers:

- `id` matching with and without `*`;
- the loganalyzer noise filter, including a test's own `LogAnalyzerError`;
- the four outcomes in 7.3;
- "now passing" and "stale";
- final results after a rerun;
- `make_chunks.py`: no chunk exceeds the target unless a single file does, every file appears exactly once, and the automatic target gives two rounds per testbed;
- `render_job.py`: the rendered job and the validation of every value;
- `submit.sh` against a fake Testflinger CLI: a normal run, a provision phase over the limit, an unlimited queue wait, and failed provisioning that uses up the retries;
- the shell syntax of every script.

## 8. One-time setup

| # | Step | Owner |
|---|---|---|
| 1 | Push the local `ceosimage:4.32.5M-1` to `ghcr.io/canonical/sonic-ceos:4.32.5M-1` (internal) | Agent |
| 2 | In the package settings, under "Manage Actions access", give `canonical/sonic-buildimage` the Read role | User (package admin) |
| 3 | Add repository secrets `TESTFLINGER_CLIENT_ID` and `TESTFLINGER_SECRET_KEY` | User (repository admin) |
| 4 | Set the `sonic-ci` membership in the C3 "Customized queues" field, and confirm that `testflinger-cli list-agents --filter-queues sonic-ci` lists exactly the 10 machines. If it does not, ask the certification team to sync TOR3-DH1 | Agent sets and checks; user asks |

The 10 machines in `sonic-ci`: fleetroc (20 testbeds); alarmmonkey, alienbunny, kroop, vlacq, cajal, parakarry (16 each); smilax, jasperoid, hoodin (13 each). The rule for membership is "at least 13 testbeds". Provision reliability is not part of the rule, because failed and slow provisioning is retried.

## 9. Verification

Until the workflow is on the default branch, the `schedule`, `workflow_run` and `issue_comment` triggers cannot fire. Before the merge, runs are started by pushing to a `ci-workflow/t0-*` branch whose commit also removes `resolute-build.yml`, so that the push does not start a build; a `-run<id>` suffix picks the build. While the `sonic-ci` membership is not synced, such a branch may also point `job_queue` at one large machine.

| Stage | What | Accepted when | Result |
|---|---|---|---|
| M1 | `run-t0.sh` by hand on one large machine, `scope=smoke` | Every smoke file has a JUnit result, each of the 2 testbeds ran at least one chunk, and `verdict.py report` on the results gives the expected outcome | Passed: 12 passed, 1 skipped |
| M2 | Full workflow on a `ci-workflow/t0-*` branch, `scope=smoke` | Commit status, job summary, workflow artifact and the Testflinger artifact all appear, and agree with each other | Passed: run 45107247028, 73 minutes from push to report |
| M3 | Full workflow, `scope=full` | The run finishes within 6 hours on a 16-testbed machine; the first `known-failures.yaml` is written (7.5) | Passed: run 45114609003, 4 h 28 min |
| M4 | Pull request to `202605_resolute`, then after the merge | One nightly run, one `workflow_run` run after a merge, and one run from a `/test-t0` comment each finish with a report | Open |

## 10. Risks

| Risk | Mitigation |
|---|---|
| The `sonic-ci` membership has not been synced to the agents, so jobs may land on small machines that cannot finish the full list | Step 4 of section 8; ask the certification team to sync. Development branches can point at one large machine |
| The machines are shared and the queue wait has no bound | `timeout-minutes: 1440` caps the wait; the run ends as "Infrastructure", not as a regression |
| Provisioning fails often on some members (parakarry 50 %, mostly from kernel-team jobs) | 25 minutes per attempt and 2 retries; drop a member if its failures repeat on our jobs |
| A token reaches shared lab machines | It is the `t0` job's own token: read-only for actions, contents and packages, expiring when the job ends; the per-run secret expires after a day and is deleted at the end of the job; the machine drops it after the payload phase, before any VM starts |
| A pull request image runs on lab hardware | Only users with write access can trigger; every script comes from the default branch |
| A sonic-mgmt upgrade brings new environment traps or new failures | The pin changes only through a pull request, which also updates the list and is checked with `/test-t0` |
| The build artifact expires before it is tested | `resolute-build` keeps `sonic-vs-img` for 30 days; a missing artifact is reported and the run stops |
| The vs image grows | Nothing in the path has a size limit below the artifact's own |
