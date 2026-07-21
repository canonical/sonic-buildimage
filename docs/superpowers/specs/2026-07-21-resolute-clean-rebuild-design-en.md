# Resolute Fully-Clean From-Scratch Build — Design

- Date: 2026-07-21
- Acting repository: `/home/sheldon-qi/sonic-buildimage-resolute` (branch `202605_resolute`)
- Build host: Ubuntu 26.04 (ext4 root, kernel 7.0.0-27, docker-ce 29.6.1, default DinD `--privileged`)
- Goal: end-to-end from-scratch reproducible build (vs first → broadcom second), verifying the full build chain reproduces and reclaiming disk held by accumulated build artifacts
- Related: [Broadcom platform build support design](2026-07-20-broadcom-platform-build-support-design-en.md), [Migration design](2026-07-03-sonic-202605-resolute-migration-design-en.md)
- This is the English version and the single source of truth.

## 1. Goal and Scope

Execute one **fully clean** from-scratch build: clean all build artifacts while preserving only necessary config and upstream base images; then build `sonic-vs.img.gz` from scratch, and on success build `sonic-broadcom.bin` from scratch.

Cleanup depth, per user decision: remove slave images, ccache, and the shared dpkg cache (`/var/cache/sonic/artifacts`) too — the literal meaning of "from-scratch reproducibility." Testbed containers and all SONiC slave images are removed; upstream base images (debian/ubuntu/ceosimage/multiarch, etc., which we did not build) are preserved.

**Out of scope:** this design does not modify any source or build rule. If a build error genuinely requires a modification, see the fix-loop policy in Section 7.

## 2. Preserve List (do not touch)

| Category | Contents | Reason preserved |
|---|---|---|
| Repo config | `rules/config.user`, `AGENTS.md`, `.gitmodules`, all source, git history and branches | All git-tracked; `make reset`'s `git clean` / `git reset --hard` do not touch tracked files |
| Host fixes | AppArmor `gs` local override (`/etc/apparmor.d/local/gs`), `ip_tables` module (`/etc/modules-load.d/ip_tables.conf`) | On the host, untouched by reset; required for rebuild (bash.pdf write and iptables-legacy respectively) |
| Upstream base images | `ubuntu:resolute`/`:noble`, all `debian:*`, `ceosimage:*`, `multiarch/qemu-user-static`, `alpine`, `publicmirror.azurecr.io/debian:*`, `p4lang/behavioral-model`, `sonicdev-microsoft.azurecr.io:443/docker-ptf` | Not SONiC build outputs; a true from-scratch rebuild re-pulls as needed; preserved per user decision |
| Backups | `sonic-config.user` backup in the memory directory | Stored outside the repo, unaffected by any cleanup |

## 3. Pre-flight Safety Checks (hard gate before deleting anything)

Before running the Section 4 cleanup, all must pass:

1. **Git cleanliness** — `git status` confirms no uncommitted tracked changes would be discarded by `reset --hard`. Current worktree has only rebuildable extracted `src/*/` and fsroot artifacts (safe). If uncommitted tracked changes exist, resolve them first (stash or commit) before proceeding.
2. **`git clean -xfdf -n` dry run** — lists untracked/ignored files that would be deleted; human-confirms nothing wanted is caught.
3. **Submodule health** — spot-check `git submodule status`; object store intact (recent vs/broadcom builds succeeded → expected healthy; if missing-blob errors appear, fix via deinit + re-clone per [[sonic-resolute-submodule-object-store-corruption]] before continuing).
4. **Submodule gitlink reachability** — confirm gitlink commits for submodules Canonical modified are pushed to `canonical/<sub>:202605_resolute` (otherwise `git submodule update --init` fails).
5. **Host fixes in place** — `lsmod | grep ip_tables` shows output AND `/etc/apparmor.d/local/gs` exists; if missing, restore first (otherwise rebuild breaks).
6. **Passwordless sudo** — `sudo -n true` succeeds (`make reset`'s `sudo rm -rf fsroot*` needs it).

## 4. Cleanup Procedure

### 4a. Official reset (repo-level deep clean)

```
make BLDENV=resolute UNATTENDED=y reset
```

Effect: `sudo rm -rf fsroot*` (including 68G `fsroot.docker.resolute` and `fsroot-broadcom*` / `-dnx` / `-legacy-th` / `-vs`) → `git clean -xfdf` (clears `target/` incl. ccache/vcache, extracted `src/*/`, `.pytest_cache`) → `git reset --hard` → submodules `clean` + `reset --hard` + `remote update` + `update --init --recursive`. **All git-tracked files are preserved.**

### 4b. Root-owned residual fallback

The reset's `fsroot*` glob does not match root-owned large files without the fsroot prefix; delete explicitly and verify:

```
sudo rm -f dockerfs.tar.gz fs.squashfs fs.zip
sudo rm -rf fsroot*                  # fallback, in case reset's sudo glob missed any
ls -la | grep -E 'fsroot|\.tar\.gz|\.squashfs|\.zip'    # expect no output
```

### 4c. Docker cleanup (stop/remove testbed + remove SONiC build images, preserve upstream base images)

First stop and remove the 10 testbed containers, then remove SONiC build-output images (slaves + local testbed images + build-produced runtime images), preserving upstream base images:

```
# Stop and remove testbed containers (10)
docker rm -f ptf_vms6-1 sonic-mgmt \
  ceos_vms6-1_VM0100 ceos_vms6-1_VM0101 ceos_vms6-1_VM0102 ceos_vms6-1_VM0103 \
  net_vms6-1_VM0100 net_vms6-1_VM0101 net_vms6-1_VM0102 net_vms6-1_VM0103

# Remove SONiC build-output images (11 slaves + 5 testbed/runtime)
docker rmi -f \
  sonic-slave-resolute-sheldon-qi:d4568f6ea37 \
  sonic-slave-resolute:eee7031281d tmp-sonic-slave-resolute:eee7031281d \
  sonic-slave-trixie:0a98d89ae3c tmp-sonic-slave-trixie:0a98d89ae3c \
  sonic-slave-trixie-sheldon-qi:92fdf9e0a2c sonic-slave-trixie-sheldon-qi:3bf70d08d22 \
  sonic-slave-bookworm:edc8bd76260 tmp-sonic-slave-bookworm:edc8bd76260 \
  sonic-slave-bookworm-sheldon-qi:82749adf7f6 sonic-slave-bookworm-sheldon-qi:db5f4be378a \
  docker-sonic-mgmt:latest docker-ptf:latest \
  docker-database:latest docker-macsec:latest docker-dhcp-relay:latest

# build cache + dangling
docker builder prune -af
docker image prune -f
```

**Not removed:** `sonicdev-microsoft.azurecr.io:443/docker-ptf`, `ceosimage:*`, `debian:*`, `ubuntu:*`, `multiarch/*`, `alpine`, `p4lang/*`, `publicmirror.azurecr.io/debian:*`.

### 4d. Shared dpkg cache full clear

```
sudo rm -rf /var/cache/sonic/artifacts/*
sudo chown root:root /var/cache/sonic/artifacts && sudo chmod 777 /var/cache/sonic/artifacts   # restore perms for build to rewrite
```

Note: the dpkg cache is keyed by commit hash; filenames carry no branch label, so it **cannot be reliably selectively cleaned by resolute/trixie** — hence full clear. This directory is shared with the sibling trixie clone (`sonic-buildimage-202605-clone`); clearing it also drops the trixie dpkg cache — the next trixie build repopulates it, costing time once, causing no breakage.

### 4e. Verify cleanup

```
du -sh target/ fsroot* /var/cache/sonic/artifacts   # target/ and fsroot* absent or empty; artifacts empty
docker images | grep -E 'sonic-slave|docker-(sonic-mgmt|ptf|database|macsec|dhcp)'   # expect no output
df -h                                                # confirm ~114G reclaimed
```

## 5. Build Procedure (vs → broadcom, background + periodic polling)

A from-scratch build is lengthy (slave re-derivation + full submodule recompile). Run in the background, capture logs, poll periodically.

```
# vs (run the chain end-to-end first)
sg docker -c 'make init'
sg docker -c 'make PLATFORM=vs configure'
sg docker -c 'make PLATFORM=vs target/sonic-vs.img.gz' > target/build-vs.log 2>&1 &   # background

# after vs succeeds → broadcom (real hardware image)
sg docker -c 'make PLATFORM=broadcom configure'
sg docker -c 'make PLATFORM=broadcom target/sonic-broadcom.bin' > target/build-broadcom.log 2>&1 &
```

The exact broadcom make target/flags are confirmed at execution time against the broadcom build-success memory and the [Broadcom platform build support design](2026-07-20-broadcom-platform-build-support-design-en.md) (TH3/standard bin). Poll by `tail`-ing both logs periodically for progress and errors.

## 6. Verification

- **vs:** `ls -lh target/sonic-vs.img.gz` (~2G) + extract and check os-release confirms Ubuntu 26.04.
- **broadcom:** `ls -lh target/sonic-broadcom.bin` (~2.3G ONIE installer).
- Both build logs end with no ERROR and exit code 0.

## 7. Fix-Loop Policy (hard policy)

If a build error is encountered that **genuinely requires modifying source or build rules**, follow the loop below. This policy applies to both the vs and broadcom builds — the reproducibility rationale is identical.

### 7.1 Why commit is mandatory (technical necessity, not style)

`make reset` includes `git reset --hard` + `git clean -xfdf` + `git submodule foreach 'git reset --hard'` + `git submodule update --init --recursive`. Therefore:

- **Any uncommitted change is wiped by reset** — a fix not committed is itself cleaned away on the next cleanup.
- **A submodule fix requires the full gitlink flow** — `git submodule update --init` checks the submodule out at the commit the parent's gitlink points to. Committing inside the submodule without bumping the parent gitlink → `update --init` checks out the old gitlink, discarding the fix.

### 7.2 The fix loop

1. **Locate and fix** — on a build error, first locate the root cause via systematic-debugging; the modification follows AGENTS.md Editing Rules (minimal scope, patch files rather than direct edits to external sources, preserve pins, etc.).
2. **Commit the fix** (two cases):
   - **Parent-repo change** (`rules/*.mk`, `*.j2` templates, Dockerfiles, etc.): commit directly to `202605_resolute`.
   - **Submodule change**: per AGENTS.md Submodules — commit in the submodule to its `202605_resolute` branch → push `canonical/<sub>:202605_resolute` (**never push to `sonic-net/`**) → in the parent `git add <sub>` to bump the gitlink → commit the parent. **Only when the parent gitlink points at the new commit does the post-reset rebuild actually carry the fix.**
3. **Run the full cleanup** — re-run all of Section 4 (4a–4e), skipping nothing. Step 4c (docker cleanup) is non-skippable: if the fix touches the slave Dockerfile or a submodule that feeds the slave, the stale slave image must be removed or it will not re-derive and the fix will not take effect.
4. **Rebuild from scratch** — re-run the Section 5 build.

Modify → commit → full clean → rebuild is the hard guarantee of from-scratch reproducibility: commit puts the fix in git, reset does not lose it, and the clean rebuild verifies it truly works in a clean environment.

## 8. Risks and Rollback

- **`make reset`'s `reset --hard` is irreversible** — Section 3 pre-flight is the hard gate; if git is not clean, abort and do not clean.
- **slave-derivation stage crash (bash.pdf / iptables)** — first verify the host fix (Section 3 item 5) is actually in place.
- **`git submodule update --init` reports missing blob** — fix via deinit + re-clone per [[sonic-resolute-submodule-object-store-corruption]].
- **dpkg cache full clear affects the sibling trixie clone** — costs one extra build only, no breakage (see 4d).
