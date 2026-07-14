# sonic-mgmt resolute VS Testbed — Implementation Plan (v2, standard testbed-cli flow)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a standard sonic-mgmt KVM testbed with a cEOS-neighbor T0 topology, boot the resolute `sonic-vs` as the DUT, and run the full T0 test suite against it to validate the resolute (Ubuntu 26.04) migration.

**Architecture:** Follow the sonic-mgmt official `README.testbed.VsSetup.md` flow exactly. The DUT is a KVM VM (`vlab-01`) created automatically by `testbed-cli.sh add-topo`; cEOS neighbors are Docker containers; the PTF is a Docker container; all connect over a host `br` management bridge. No manual `virsh`/XML (the `platform/vs/sonic.xml` template is obsolete — its machine type `pc-i440fx-1.5` and `-redir` hostfwd are unsupported by modern QEMU/libvirt).

**Tech Stack:** KVM/QEMU + libvirt (DUT), Docker CE (cEOS + PTF containers), sonic-mgmt ansible framework @ branch `202605`, `docker-sonic-mgmt` as the test executor container.

## Global Constraints

- Build repo: `~/sonic-buildimage-resolute`, branch `202605_resolute`. The resolute `sonic-vs.img` lives at `~/sonic-buildimage-resolute/sonic-vs.img` (5.5GB, root-owned) and **also** must be copied to `~/sonic-vm/images/` and `~/veos-vm/images/` for the testbed flow.
- sonic-mgmt repo: `~/sonic-mgmt`, branch `20260605` (HEAD `00c4dac`). All testbed-cli/ansible commands run from `~/sonic-mgmt/ansible/` unless noted.
- Doc branch `202605_resolute_doc` holds spec/plan docs.
- Proxy for network ops (git clone, image download, pip, docker pull): `https_proxy=http://192.168.1.210:6152`, `no_proxy=archive.ubuntu.com,security.ubuntu.com,10.211.55.9,localhost,127.0.0.1`.
- DUT credentials: bare image `admin`/`YourPaSsWoRd` (rules/config DEFAULT_PASSWORD); after `deploy-mg` the minigraph sets `admin`/`password`. Use `password` for test access.
- Local add-host/proxy edits in `Makefile.work`/`slave.mk`/`rules/config.user` are NOT committed (local acceleration).
- Test-related code fixes may be committed but NOT pushed.
- Bilingual deliverables: every doc this plan produces is two files (`-en.md` + `-zh.md`).
- Host: 47GB RAM, ~74GB free disk after cleanup. T0 needs ≥20GB RAM (doc requirement met).

## File Structure

| File / Artifact | Responsibility | Create/Modify |
|---|---|---|
| `~/veos-vm/images/` + `~/sonic-vm/images/` | image store for sonic-vs.img + cEOS tar | Create (host) |
| `br` OVS/linux bridge | management network connecting DUT + PTF + cEOS mgmt | Created by setup-management-network.sh |
| `~/sonic-mgmt/ansible/veos_vtb` | ansible inventory: `STR-ACS-VSERV-01` ansible_user = host user | Modify |
| `~/sonic-mgmt/ansible/group_vars/vm_host/creds.yml` | vm_host_user/password = host user/sudo | Modify |
| `~/sonic-mgmt/ansible/password.txt` | dummy ansible-vault password file | Create |
| `~/sonic-mgmt/ansible/vtestbed.yaml` | testbed row `vms-kvm-t0` (already shipped; verify/edit) | Verify/Edit |
| `/etc/sudoers` (host) | `<user> ALL=(ALL) NOPASSWD:ALL` for ansible | Modify (visudo) |
| `docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-{en,zh}.md` | this plan | Create |

No buildimage source files are modified by this plan (test-only). Inventory/creds edits live in the cloned `~/sonic-mgmt`.

---

## Task 1: Prepare testbed host (bridge + docker + images)

**Files:**
- Modify (host): bridge `br` via `setup-management-network.sh`
- Create: `~/veos-vm/images/`, `~/sonic-vm/images/`

**Interfaces:**
- Consumes: `~/sonic-mgmt/ansible/setup-management-network.sh`, the resolute `sonic-vs.img`, a cEOS tar image
- Produces: host with `br` management bridge, Docker CE usable without sudo, images in place

- [ ] **Step 1: Run the host setup script (builds the `br` management bridge + installs deps)**

```bash
cd ~/sonic-mgmt/ansible
sudo -H ./setup-management-network.sh 2>&1 | tail -20
```
Expected: script completes, `br` bridge exists. Verify: `ip link show br` shows an interface. If it errors on a package install, fix and re-run.

- [ ] **Step 2: Confirm Docker CE works without sudo**

```bash
docker info >/dev/null 2>&1 && echo "docker ok (no sudo)" || echo "docker needs sudo — run post-install: sudo usermod -aG docker $USER && re-login"
```
Expected: `docker ok (no sudo)`. If not, do the post-install group step and re-login (or `newgrp docker`), then re-check.

- [ ] **Step 3: Place the resolute sonic-vs image into both image dirs**

```bash
mkdir -p ~/sonic-vm/images ~/veos-vm/images
sudo cp ~/sonic-buildimage-resolute/sonic-vs.img ~/sonic-vm/images/
sudo cp ~/sonic-buildimage-resolute/sonic-vs.img ~/veos-vm/images/
sudo chown $USER:$USER ~/sonic-vm/images/sonic-vs.img ~/veos-vm/images/sonic-vs.img
ls -la ~/sonic-vm/images/sonic-vs.img ~/veos-vm/images/sonic-vs.img
```
Expected: both copies present, owned by current user (add-topo needs read access).

- [ ] **Step 4: Obtain and place the cEOS image**

Get `cEOS64-lab-*.tar.xz` from the Arista software-download page (free guest account), `unxz` it, place the `.tar` in `~/veos-vm/images/`. Confirm the version matches `ansible/group_vars/vm_host/ceos.yml` (note: 4.35.0F does NOT work per the doc).

```bash
# After manually obtaining the tar (adjust version to what you got):
ls -la ~/veos-vm/images/cEOS*.tar 2>/dev/null
cat ~/sonic-mgmt/ansible/group_vars/vm_host/ceos.yml | grep -iE 'image|version' | head
```
Expected: a cEOS tar is present, and `ceos.yml` references a matching version. If version differs, edit `ceos.yml` to match the obtained image.

**BLOCKER flag:** Step 4 requires a cEOS image from Arista. If the user has not provided one and there is no way to obtain it, STOP and report — the with-neighbor T0 cannot proceed without it.

- [ ] **Step 5: No commit** (host setup; lives outside repos). Record `br` is up and images are placed in the task report.

---

## Task 2: Configure the sonic-mgmt container + inventory/creds

**Files:**
- Modify: `~/sonic-mgmt/ansible/veos_vtb` (set ansible_user)
- Modify: `~/sonic-mgmt/ansible/group_vars/vm_host/creds.yml` (set vm_host_user/password)
- Create: `~/sonic-mgmt/ansible/password.txt`
- Modify (host): `/etc/sudoers` via visudo

**Interfaces:**
- Consumes: `docker-sonic-mgmt:latest` (self-built, pytest 9.1.1) OR the official sonic-mgmt image; `setup-container.sh`
- Produces: a running `sonic-mgmt` container with `/data/sonic-mgmt` mounted, host reachable over SSH without password, sudo NOPASSWD on host

- [ ] **Step 1: Start the sonic-mgmt container using setup-container.sh (reuse self-built image if possible)**

```bash
cd ~/sonic-mgmt
./setup-container.sh -h 2>&1 | head -40   # find the image-reuse flag
```
Expected: usage listing options. Identify the flag that reuses an existing image (so our self-built `docker-sonic-mgmt:latest` is used, not an official pull). If setup-container insists on pulling the official image, that is acceptable too (it still provides a working executor) — note which path was taken.

- [ ] **Step 2: Run setup-container.sh**

```bash
cd ~/sonic-mgmt
./setup-container.sh -n sonic-mgmt -d /data <image-reuse-flag-if-any> 2>&1 | tail -20
docker exec sonic-mgmt bash -c 'ls /data/sonic-mgmt && pytest --version'
```
Expected: container `sonic-mgmt` running, `/data/sonic-mgmt` mounted, pytest available.

- [ ] **Step 3: Edit veos_vtb — set the host login user**

In `~/sonic-mgmt/ansible/veos_vtb`, find the `STR-ACS-VSERV-01` host under `vm_host_1` and set `ansible_user` to the host username (e.g. `sheldon-qi`):

```bash
# set ansible_user to your host user (here sheldon-qi)
sed -i "/STR-ACS-VSERV-01:/{n;s/ansible_user: .*/ansible_user: sheldon-qi/}" ~/sonic-mgmt/ansible/veos_vtb
grep -A3 'STR-ACS-VSERV-01' ~/sonic-mgmt/ansible/veos_vtb | head
```
Expected: `ansible_user: sheldon-qi` (replace with actual host user).

- [ ] **Step 4: Edit creds.yml — set vm_host user/password**

```bash
sed -i -e 's/^vm_host_user: .*/vm_host_user: sheldon-qi/' \
       -e 's/^vm_host_password: .*/vm_host_password: <host-sudo-password>/' \
       -e 's/^vm_host_become_password: .*/vm_host_become_password: <host-sudo-password>/' \
       ~/sonic-mgmt/ansible/group_vars/vm_host/creds.yml
```
Expected: creds set to the host user + sudo password. (If host uses passwordless sudo, the password values can be left empty-ish; the visudo step below guarantees NOPASSWD.)

- [ ] **Step 5: Create the dummy vault password file**

```bash
echo 'abc' > ~/sonic-mgmt/ansible/password.txt
```
Expected: file created.

- [ ] **Step 6: Grant NOPASSWD sudo on the host**

```bash
echo "sheldon-qi ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/sonic-mgmt
sudo visudo -c   # validate syntax
```
Expected: `parsed OK`. (Replace `sheldon-qi` with the actual host user.)

- [ ] **Step 7: Verify the container can SSH to the host without a password**

```bash
docker exec sonic-mgmt bash -c 'ssh -o StrictHostKeyChecking=no sheldon-qi@172.17.0.1 "echo HOST_OK; sudo whoami"'
```
Expected: `HOST_OK` and `root` (NOPASSWD sudo works). If SSH asks for a password, the setup-container SSH key step needs re-running; report as DONE_WITH_CONCERNS and fix the key.

- [ ] **Step 8: Fix host home-dir perms (doc requires 755)**

```bash
sudo chmod 755 /home/sheldon-qi
```
Expected: no output (success).

- [ ] **Step 9: No commit** (inventory/creds are local artifacts in the clone).

---

## Task 3: Deploy the cEOS T0 topology (add-topo)

**Files:**
- Verify/Edit: `~/sonic-mgmt/ansible/vtestbed.yaml` (ensure a `vms-kvm-t0` row exists)

**Interfaces:**
- Consumes: host bridge (Task 1), sonic-mgmt container + inventory (Task 2), sonic-vs.img + cEOS image (Task 1)
- Produces: KVM DUT `vlab-01` running, 4 cEOS neighbor containers, PTF container, topology cabled via OVS bridges

- [ ] **Step 1: Verify/define the testbed row**

```bash
grep -A12 'vms-kvm-t0' ~/sonic-mgmt/ansible/vtestbed.yaml | head -15
```
Expected: a `vms-kvm-t0` entry with `topo: t0`, `dut: [vlab-01]`, `group-name`, `vm_base`, `ptf`, `ptf_image_name`. If absent, add one matching the VsSetup doc example (see `README.testbed.VsSetup.md` "KVM based SONiC DUT" section).

- [ ] **Step 2: Deploy the topology (cEOS default, no start-vms needed)**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb add-topo vms-kvm-t0 password.txt' 2>&1 | tail -30
```
Expected: playbook completes, KVM DUT `vlab-01` + 4 cEOS pairs (`net_*`/`ceos_*`) + PTF created. `cached_topologies_path file content is empty` is OK.

- [ ] **Step 3: Verify the topology containers + DUT**

```bash
docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'ceos_|net_|ptf_'
sudo virsh list --name | grep vlab-01
```
Expected: 8 cEOS/net containers + 1 ptf container running, and `vlab-01` listed.

- [ ] **Step 4: No commit.** Record the topology is up in the report.

---

## Task 4: Deploy minigraph on the DUT (deploy-mg)

**Files:**
- (no file changes — pushes config to the running DUT)

**Interfaces:**
- Consumes: running topology (Task 3), the `veos_vtb` minigraph templates
- Produces: DUT with full t0 config loaded, mgmt IP 10.250.0.101, admin/password SSH working, BGP neighbors configured

- [ ] **Step 1: Deploy the minigraph**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/ansible && ./testbed-cli.sh -t vtestbed.yaml -m veos_vtb deploy-mg vms-kvm-t0 veos_vtb password.txt' 2>&1 | tail -25
```
Expected: playbook completes, config loaded on `vlab-01`.

- [ ] **Step 2: Verify SSH to the DUT (password is now `password`)**

```bash
sshpass -p password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@10.250.0.101 'show version; show ip bgp sum' 2>&1 | tail -25
```
Expected: SONiC version + BGP summary with 4 ARISTA neighbors (State/PfxRcd populated once sessions come up). If BGP shows 0/Idle, wait 60s and re-check.

- [ ] **Step 3: Confirm resolute identity on the live DUT**

```bash
sshpass -p password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@10.250.0.101 'cat /etc/os-release | grep -E "PRETTY|CODENAME|ID="; uname -r'
```
Expected: `Ubuntu 26.04 LTS`, `resolute`, `ID=ubuntu`, `7.0.0-1002-sonic`.

- [ ] **Step 4: No commit.** Record the DUT is configured + resolute identity confirmed.

---

## Task 5: Run the full T0 test suite

**Files:**
- (test execution only; report is the output)

**Interfaces:**
- Consumes: fully-deployed T0 testbed (Task 4)
- Produces: PASS/FAIL for the T0 test suite

- [ ] **Step 1: Run a single sanity test first (link-layer gate)**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -c bgp/test_bgp_fact.py -f vtestbed.yaml -i ../ansible/veos_vtb' 2>&1 | tail -30
```
Expected: `test_bgp_fact` PASS (the doc's canonical "it works" test). If this fails, the testbed is not healthy — debug before running the full suite.

- [ ] **Step 2: Enumerate the T0 test set**

```bash
# discover which tests are tagged for t0 topology
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/tests && grep -rl --include="test_*.py" "topology.*t0\|t0" . | head -40'
```
Expected: a list of test files runnable under t0. Capture this list for the full run.

- [ ] **Step 3: Run the full T0 suite (log to a file; this is long)**

```bash
docker exec sonic-mgmt bash -c 'cd /data/sonic-mgmt/tests && ./run_tests.sh -n vms-kvm-t0 -d vlab-01 -c <t0-test-list> -f vtestbed.yaml -i ../ansible/veos_vtb' > ~/t0-full-run.log 2>&1 &
# (the test list from Step 2; run in background, monitor)
```
Expected: run completes with a summary of PASS/FAIL per module.

- [ ] **Step 4: On any FAIL, apply systematic-debugging** — distinguish resolute regression vs testbed/test issue; A/B against the 202605-clone non-resolute sonic-vs if root cause is unclear.

- [ ] **Step 5: No commit unless a resolute-specific fix was needed.**

---

## Task 6: Produce the bilingual test report

**Files:**
- Create: `docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-en.md`
- Create: `docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-zh.md`

**Interfaces:**
- Consumes: Tasks 1–5 results
- Produces: a bilingual report committed on `202605_resolute_doc`

- [ ] **Step 1: Write the English report** — host prep outcome, container/inventory approach, add-topo result, deploy-mg result (resolute identity), per-test PASS/FAIL for the T0 suite, root-cause notes for any FAIL, overall verdict on the resolute migration.

- [ ] **Step 2: Write the Chinese report** — full translation, same structure (two files, not one mixed).

- [ ] **Step 3: Commit on the doc branch**

```bash
cd ~/sonic-buildimage
git add docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-en.md docs/superpowers/plans/2026-07-14-sonic-mgmt-resolute-vs-testbed-report-zh.md
git commit -m "docs: add sonic-mgmt resolute vs T0 testbed test report (zh + en)"
```
Expected: commit with two files.

---

## Self-Review Notes

- **Spec coverage:** spec Phase 1 (sanity) + the user's `/goal` extension (with-neighbor T0 + full T0 suite) are both covered: Task 1–2 setup, Task 3 topology, Task 4 config, Task 5 tests, Task 6 report.
- **v1 plan superseded:** the v1 plan (manual virsh + user-mode port-fwd) is removed — it was based on the obsolete `platform/vs/sonic.xml` template (machine type `pc-i440fx-1.5` unsupported, `-redir` removed, libvirt `<protocol>` hostfwd silently dropped). v2 uses the official `testbed-cli.sh` flow verbatim from `README.testbed.VsSetup.md`.
- **Credential correction:** bare sonic-vs admin password is `YourPaSsWoRd` (rules/config DEFAULT_PASSWORD), NOT `admin`. After `deploy-mg` it becomes `password`. v1 plan's `admin/admin` assumption was wrong.
- **Open dependency:** Task 1 Step 4 (cEOS image) requires an Arista-provided image. If unavailable, Task 3 (add-topo) cannot create neighbors — escalate to the user.
- **disk/memory:** host has 74GB free + 47GB RAM (40 available). T0 needs ≥20GB RAM (met). Disk is sufficient for one testbed.
