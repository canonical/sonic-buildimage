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
4. One-time setup: the Testflinger queue, the cEOS image, and the credentials.

**Out of scope:** the Dockerfile (supervisord) image, because CI builds only the rock image; topologies other than t0 (dualtor, t0-2vlans, t0-sonic, t1-lag); arm64; the broadcom image and physical DUTs; changes to `resolute-build.yml`; upstreaming.

## 2. Decisions

| Topic | Decision |
|---|---|
| Size of a run | One Testflinger machine, the rock vs image, and the full upstream t0 checker list. The list comes from `get_test_scripts.py` at the pinned sonic-mgmt commit (392 files at `a88d1d5f93`) |
| Image | The latest successful `sonic-vs-img` artifact. No rebuild |
| Triggers | Nightly schedule; `resolute-build` success on a push to `202605_resolute` or a `v*` tag; a `/test-t0` pull request comment; manual dispatch |
| Who may trigger from a comment | Users whose permission on the repository is `write`, `maintain` or `admin` |
| Pass/fail | A known-failures list kept in the repository. Failed files are rerun once. A failure that the list does not cover makes the run red |
| Where things live | Everything in `canonical/sonic-buildimage`, including the pinned sonic-mgmt commit |
| Runner | One job on `self-hosted-linux-amd64-noble-private-endpoint-small`, from submission to report |
| Machines | Testflinger queue `sonic-ci-large` |
| cEOS | `ghcr.io/canonical/sonic-ceos:4.32.5M-1`, visibility internal. This is the `ceosimage:4.32.5M-1` image that sonic-mgmt itself builds from the cEOS tarball; sonic-mgmt finds it locally under that tag and skips its own cEOS preparation. The machine pulls it with a classic PAT that has only `read:packages`, stored as a Testflinger secret |
| Logs | All results and logs, compressed with zstd, returned through Testflinger artifacts |
| Chunk durations | Taken from the latest nightly run's artifact; not committed |

## 3. Verified facts

| Fact | Evidence |
|---|---|
| The 392-file list costs 40.7 testbed-hours per image; the legacy 271-file list costs 33.7 | Sum of JUnit file times of the rock run on 2026-11-19 (the 125 files beyond the legacy list add 7.0 h) |
| The small runner is available to this repository | Run 44701651973: runner `private-endpoint-amd64-noble-small-*` in group "canonical self-hosted runners"; 2 vCPU, 7 GB RAM, 19 GB disk, Ubuntu 24.04, with `snap`, `docker`, `jq` and `yq`; reaches the Testflinger API and GitHub. The job started 9 minutes after it was queued |
| A job on a self-hosted runner may run for up to 5 days; `timeout-minutes` defaults to 360 and must be raised | GitHub Actions usage limits |
| With `poll: true`, the `canonical/testflinger` submit action cancels and resubmits the job when setup or provision fails (up to `retries`), then follows the test phase, and cancels the Testflinger job when the workflow run is cancelled | `.github/actions/submit/action.yaml` in `canonical/testflinger` |
| The agents in `sonic-ci-large` have `global_timeout` 43200 s and `output_timeout` 8000 s | `testflinger-agent.conf` of each agent in `canonical/testflinger-agent-charm-configs` |
| The agent uploads the `artifacts/` directory as one tarball; the server accepts up to 500 MB per request by default | Agent `save_artifacts`; server `MAX_BODY_SIZE` |
| All results of one image (389 files, JUnit and logs) take 1198 MB, or 17 MB after `zstd -19` | The rock results of 2026-11-19 |
| A push by an org member creates an internal GHCR package; anonymous pulls are refused; a token pull works; GHCR does not accept fine-grained PATs | Probe package `ghcr.io/canonical/sonic-ci-probe` (deleted after the test); GitHub documentation |
| On a reserved machine: nested KVM is enabled; MAAS configures the apt proxy `http://10.239.8.11:8000/`; GitHub, download.docker.com, azurecr.io, ghcr.io, PyPI and Testflinger are reachable directly; downloads from GitHub run at about 5.9 MB/s | Probe job on romano, 2026-11-20 |
| A queue added in the C3 "Customized queues" field reaches the agent only after the certification bot syncs `testflinger-agent-charm-configs`, and the sync has no fixed schedule | Commit history of `server-cert/data-tor3-dh1` |
| `author_association` in event payloads shows private org members as `CONTRIBUTOR` | 3 of 4 active members of this repository have private membership |
| `get_test_scripts.py --features "" --location <tests>` run in the docker-sonic-mgmt image gives the same 392-file `t0_checker` list | Run at `a88d1d5f93`, compared with the list of 2026-11-19 |
| sonic-mgmt uses a local image tagged `ceosimage:4.32.5M-1` and then skips downloading, importing and building cEOS | `ansible/roles/vm_set/tasks/add_ceos_list.yml` |
| Until sonic-buildimage PR #30 merges, the run has dozens of loganalyzer teardown errors whose only matched line is `nss_tacplus: /etc/tacplus_nss.conf fopen failed`, on different cases each time | 36 such errors on 2026-11-19; PR #30 is open |
| JUnit test cases have `classname="tests.<module path in dots>[.<class>]"`; `run_tests.sh -m individual` writes one JUnit file per test file, at the test file's path | The results of 2026-11-19 |

## 4. Architecture

```
trigger (schedule / workflow_run / issue_comment / workflow_dispatch)
  │
  ▼
resolute-t0.yml, one job on the small runner, timeout 1440 min
  1. resolve the build → (commit, build run id); authorise a comment trigger
  2. set commit status "resolute-t0" = pending
  3. download sonic-vs-img → publish it as a release asset
  4. pack the harness, the known-failures list, durations.json and the sonic-mgmt pin
  5. canonical/testflinger submit action (poll: true, retries: 2) ──► Testflinger
                                                                        │
     reserved machine, queue sonic-ci-large, Ubuntu 26.04 ◄─────────────┘
       host setup → testbeds in LXD VMs → chunked t0 run → reruns → results.tar.zst
                                                                        │
  6. download the Testflinger artifacts ◄───────────────────────────────┘
  7. verdict against known-failures.yaml
  8. job summary, workflow artifact, commit status, sticky PR comment
```

Trust boundary: every script that runs on the machine comes from the default branch (`202605_resolute` at the time of the run), because `schedule`, `workflow_run` and `issue_comment` all run the workflow file from the default branch. Only two things come from the commit under test: the vs image, and `known-failures.yaml`, which is data. Only users with write access can start a run from a comment.

## 5. Workflow `.github/workflows/resolute-t0.yml`

### 5.1 Resolving the build

| Trigger | Condition | Build under test |
|---|---|---|
| `schedule` | Daily at 15:00 UTC | The latest successful `resolute-build` run of event `push` on `202605_resolute` |
| `workflow_run` | `resolute-build` completed with `success`, event `push`, on `202605_resolute` or a `v*` tag | The triggering run |
| `issue_comment` | Comment on a pull request whose body starts with `/test-t0` | The latest successful `resolute-build` run whose head SHA equals the PR head SHA |
| `workflow_dispatch` | Manual; input `run_id` (a `resolute-build` run); input `scope` = `full` or `smoke` | The given run |
| `push` | A branch named `ci-workflow/t0-*`; development only. Always `smoke`, no commit status, and the known-failures list comes from the pushed commit | The latest successful `resolute-build` run of event `push` on `202605_resolute` |

For a comment trigger, the workflow first checks `GET /repos/{repo}/collaborators/{user}/permission` and stops unless the result is `admin`, `maintain` or `write`. Next it adds an "eyes" reaction to the comment. If no successful build exists for the head SHA, or its artifact has expired (7 days), it replies on the pull request and stops.

### 5.2 Steps

1. Resolve the build (5.1). The output is the commit SHA and the build run id.
2. Set the commit status `resolute-t0` to `pending`, with a link to this run.
3. Download `sonic-vs-img` from the build run. Upload `sonic-vs-<sha12>.img.gz` and its `.sha256` to the prerelease `t0-images`, and delete all but the 10 newest image assets.
4. Fetch `durations.json` from the artifact of the latest successful scheduled run. If there is none, the chunker uses its default.
5. Build `t0-harness.tar.gz`: the contents of `.github/testflinger/t0/` from the default branch, `known-failures.yaml` from the commit under test, and `durations.json`.
6. Run the unit tests of the harness Python code (7.6) before using the machine.
7. Render the Testflinger job (6.1) and submit it with `canonical/testflinger/.github/actions/submit` pinned to a commit: `poll: true`, `retries: 2`, `attachments-relative-to` the work directory, and the client id and secret from repository secrets.
8. Download the Testflinger artifacts (`testflinger-cli artifacts <job>`), even if the test phase failed.
9. Run the verdict (7.3) and write the job summary.
10. Upload a workflow artifact `resolute-t0-<sha12>-<attempt>` (results, `summary.json`, `durations.json`), kept for 30 days.
11. Set the final commit status. For a comment trigger, create or update the single PR comment marked `<!-- resolute-t0 -->`.

Job settings: `timeout-minutes: 1440`; concurrency group `resolute-t0-<sha>` with `cancel-in-progress: false`; permissions `contents: write` (release assets), `statuses: write`, `pull-requests: write`, `issues: write` (reactions and comments), and `actions: read` (artifacts of other runs). When the job times out, a final step cancels the Testflinger job and reports `error` (infrastructure).

## 6. Testflinger job and harness

### 6.1 Job file

```yaml
job_queue: sonic-ci-large
global_timeout: 43200
output_timeout: 7200
tags: [sonic-buildimage-t0, "sha:<sha12>", "gh-run:<run id>"]
provision_data:
  distro: resolute
test_data:
  attachments:
    - local: t0-harness.tar.gz
  secrets:
    GHCR_TOKEN: sonic-buildimage/ghcr-read-token
  test_cmds: |
    <agent side, 6.2>
```

### 6.2 Agent side (`test_cmds`)

The agent side does as little as possible:

1. Copy the attachment to the machine (`ubuntu@$DEVICE_IP`, `BatchMode=yes`).
2. Start `run-t0.sh` there, detached (`setsid nohup`), with the image URL, its SHA-256 and the run scope. `GHCR_TOKEN` goes over the SSH session's stdin into the environment of the detached process, never onto a command line. A dropped SSH connection therefore does not stop the run.
3. Every minute, fetch the new lines of the machine's `progress.log` and print them, until the harness writes its `EXIT` file.
4. Copy `results.tar.zst`, `run-meta.json` and the harness logs into `artifacts/`, whatever the exit status.

### 6.3 Harness on the machine (`run-t0.sh`)

1. **Host setup.** These fixes come from the 2026-11-10/11-19 runs:
   - growpart the root filesystem of each LXD VM;
   - let `lxdbr0` through the `DOCKER-USER` chain;
   - keep the MAAS apt proxy and copy it into the VMs;
   - install docker-ce from download.docker.com;
   - after the first install of openvswitch-switch, run `reset-failed` and restart it;
   - pull `publicmirror.azurecr.io/debian:trixie` before add-topo;
   - disable `apt-daily*` and `unattended-upgrades` in the VMs;
   - put the VMs on a zfs pool built from the spare SSDs of at least 200 GB when the machine has any, otherwise on the LXD `default` dir pool on the root SSD; rotational disks are never used.
2. **Sizing.** Testbeds T = min(⌊(RAM GiB − 16) / 18⌋, ⌊threads / 8⌋, ⌊free pool GB / 40⌋). Each VM gets ⌊threads / T⌋ vCPUs, 18 GiB of RAM and a 140 GiB sparse disk. In `scope=smoke`, T is at most 2. T is printed and recorded in `run-meta.json`.
3. **Payload.**
   - Download the vs image from the release and check its SHA-256.
   - `docker pull` the cEOS image with `GHCR_TOKEN`, using a docker config directory in `/dev/shm` that is deleted right after the pull, so the token is never written to disk and never enters a VM. Tag the image `ceosimage:4.32.5M-1` and save it to the share that the VMs mount read-only.
   - Download sonic-mgmt as a GitHub tarball of the pinned commit into the share. Apply the testbed settings of the upstream KVM guide with `configure_sonic_mgmt.py`: the VM host user and password, `ansible_python_interpreter`, and the git-ignored `ansible/password.txt`. The VMs copy the tree with `cp -a`, which keeps every symlink.
4. **Test list.** Run `get_test_scripts.py --features ""` in the docker-sonic-mgmt image at the pinned commit and take its `t0_checker` list. In `scope=smoke` the list is `smoke.txt`: 4 short files; `run_tests.sh` adds pretest and posttest itself.
5. **Chunks.** Pack the files into chunks of about 50 minutes, longest first, using `durations.json` (480 s for a file with no entry). In `scope=smoke` every file is its own chunk. Chunks go into a shared queue; each testbed takes the next chunk with an atomic rename.
6. **Execution.** Each testbed runs add-topo and deploy-mg once, then runs its chunks with `run_tests.sh -m individual`. After a chunk, `verdict.py rerun-files` lists the files with failures or errors that the known-failures list does not cover; the testbed restores the DUT configuration with deploy-mg and reruns those files once. The final result of a case is the result of its last run. The first result is kept for the report. If a testbed dies in the middle of a chunk, the chunk goes back to the queue once.
7. **Time guard.** 10.5 hours after the harness starts, no new chunks are handed out. The files that were never started are recorded as "not run".
8. **Progress.** Every 5 minutes, append one line with the chunks pending, running and done, and the testbeds finished, to `progress.log`. The agent prints these lines, which also keeps `output_timeout` from firing.
9. **Output.**
   - `results.tar.zst`: every JUnit file and log, per testbed and chunk, plus the start and end time of each chunk;
   - `run-meta.json`: the machine, T, the image SHA-256, the sonic-mgmt commit, the scope, the full file list, phase times, whether the time guard fired, and the harness exit code.

The runner, not the machine, parses the JUnit files: `verdict.py report` writes `summary.json` (outcome and per-case results) and `durations.json` (per-file times of this run).

### 6.4 Files

```
.github/workflows/resolute-t0.yml
.github/testflinger/t0/
  job.yaml.in            job template (6.1)
  render_job.py          renders job.yaml.in
  agent.sh               agent side (6.2)
  run-t0.sh              entry on the machine (6.3)
  host-setup.sh          host fixes, storage pool, sizing
  configure_sonic_mgmt.py  testbed settings for the sonic-mgmt tree
  tb-run.sh              per-testbed worker: add-topo, deploy-mg, chunk loop, rerun
  make_chunks.py         chunk packing
  verdict.py             rerun selection, verdict and report rendering (7)
  tests/                 pytest unit tests for the Python files
  known-failures.yaml    reviewed known failures (7.1)
  sonic-mgmt.ref         pinned canonical/sonic-mgmt commit SHA
  smoke.txt              the smoke list
```

## 7. Verdict and reporting

### 7.1 `known-failures.yaml`

```yaml
known:
  - id: "snmp/test_snmp_v2mib.py::test_snmp_v2mib[vlab-01]"
    kind: fail
    reason: "sysDescr names Debian; product issue, see sonic-mgmt PR #4"
  - id: "generic_hash/test_generic_hash.py::*"
    kind: flaky
    reason: "Random parameter sets; the same cases are unstable on upstream vs"
loganalyzer_noise:
  - pattern: 'nss_tacplus: (/etc/tacplus_nss\.conf fopen failed|bad config or server line)'
    reason: "AppArmor stops unix_chkpwd reading tacplus_nss.conf; fixed by sonic-buildimage PR #30"
```

- `id`: pytest node id relative to `tests/`, as built from the JUnit file path, class name and test name. `*` matches any text; every other character, including `[` and `]`, matches itself.
- `kind`: `fail` (test failure), `error` (setup or teardown error), or `flaky` (any outcome is accepted, and passing produces no notice).
- `reason`: required, written in English.
- `loganalyzer_noise`: regular expressions for syslog lines. A loganalyzer teardown error whose matched lines all match one of these patterns is ignored. Any other matched line keeps the error.
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
| Provision failed after the retries, the job timed out, no `run-meta.json` came back, or the harness exited non-zero | `error` | Infrastructure |
| Otherwise | `success` | Pass |

"Now passing" and "stale" entries never change the outcome; they are listed so that the list can be cleaned up.

### 7.4 Report

The job summary and the PR comment show:

- the outcome, with totals of passed, skipped, failed, errored and not run;
- new failures, with the first line of each message and the file log name;
- covered failures, collapsed;
- "now passing" and "stale" entries;
- cases that passed only on the rerun;
- the machine, testbed count, image commit, sonic-mgmt commit and phase times.

### 7.5 First version of the list

The first list is built from the M3 full run (9). Every difference from the rock run of 2026-11-19 (1219 passed / 2654 skipped / 31 failed / 17 setup errors, at sonic-mgmt `a88d1d5f93` and image `7a081af43c`) gets a written reason, or it is fixed before the list is committed.

### 7.6 Unit tests

pytest with small JUnit fixtures covers:

- `id` matching with and without `*`;
- the four outcomes in 7.3;
- "now passing" and "stale";
- final results after a rerun;
- `make_chunks.py`: no chunk exceeds the target unless a single file does, and every file appears exactly once.

## 8. One-time setup

| # | Step | Owner |
|---|---|---|
| 1 | Push the local `ceosimage:4.32.5M-1` to `ghcr.io/canonical/sonic-ceos:4.32.5M-1` (internal) | Agent |
| 2 | Create a classic PAT with only `read:packages`, set to expire in one year; prove that `docker pull` works with it | User creates it; agent tests it |
| 3 | Write the PAT to Testflinger secret `sonic-buildimage/ghcr-read-token` with the CI client id | Agent |
| 4 | Add repository secrets `TESTFLINGER_CLIENT_ID` and `TESTFLINGER_SECRET_KEY` | User (needs repository admin) |
| 5 | Confirm that `testflinger-cli list-agents --filter-queues sonic-ci-large` lists the 10 machines. If it does not, ask the certification team to sync TOR3-DH1 | Agent checks; user asks |

The 10 machines in `sonic-ci-large`: fleetroc (20 testbeds); alarmmonkey, alienbunny, kroop, vlacq, cajal, parakarry (16 each); smilax, jasperoid, hoodin (13 each). The rule for membership is "at least 13 testbeds". Provision reliability is not part of the rule, because the submit action retries provisioning.

## 9. Verification

Until the workflow is on the default branch, the `schedule`, `workflow_run` and `issue_comment` triggers cannot fire. Before the merge, runs are started by pushing to a `ci-workflow/*` branch whose commit also removes `resolute-build.yml`, so that the push does not start a build.

| Stage | What | Accepted when |
|---|---|---|
| M1 | `run-t0.sh` by hand on one `sonic-ci-large` machine, `scope=smoke` | Every smoke file has a JUnit result, each of the 2 testbeds ran at least one chunk, and `verdict.py report` on the results gives the expected outcome |
| M2 | Full workflow on a `ci-workflow/*` branch, `scope=smoke` | Commit status, job summary, workflow artifact and the Testflinger artifact all appear, and agree with each other |
| M3 | Full workflow, `scope=full` | The run finishes within 6 hours on a 16-testbed machine; the first `known-failures.yaml` is written (7.5) |
| M4 | Pull request to `202605_resolute`, then after the merge | One nightly run, one `workflow_run` run after a merge, and one run from a `/test-t0` comment each finish with a report |

## 10. Risks

| Risk | Mitigation |
|---|---|
| The `sonic-ci-large` queue has not been synced to the agents | Step 5 of section 8 checks before M1; ask the certification team to sync |
| The canonical org blocks classic PATs | Found in step 2 of section 8; fall back to a machine account or a GitHub App |
| The machines are shared and the queue wait has no bound | `timeout-minutes: 1440` caps the wait; the run ends as "Infrastructure", not as a regression |
| Provisioning fails often on some members (parakarry 50 %, mostly from kernel-team jobs) | `retries: 2`; drop a member if its failures repeat on our jobs |
| A sonic-mgmt upgrade brings new environment traps or new failures | The pin changes only through a pull request, which also updates the list and is checked with `/test-t0` |
| A pull request image runs on lab hardware | Only users with write access can trigger; the GHCR token is used on the host before any VM starts and never enters a VM |
| The PAT belongs to one person | Expiry reminder from GitHub; move to a machine account when one is available |
| Capacity or start delay of the small runners | About 9 minutes measured; the job has no deadline tighter than 24 hours |
