# SONiC Resolute Migration Code Review

**Repo:** `/home/sheldon-qi/sonic-buildimage-resolute` (branch `resolute`)
**Range:** `77cfa809d` (merge-base with `origin/202605`) .. `92b24de74` (HEAD) = 62 committed commits + uncommitted working-tree changes + uncommitted changes inside multiple submodules
**Date:** 2026-07-05
**Baseline:** [design spec](specs/2026-07-03-sonic-202605-resolute-migration-design-en.md) / [implementation plan](plans/2026-07-03-sonic-202605-resolute-migration-plan-en.md) / [migration report](resolute-vs-migration-report.md)

> This review was produced by an independent read-only subagent: it cross-verified the correspondence among diffs, submodules, the report, and the code (not merely reading the report).

---

## 1. Goal Achievement

**5 Phases (committed HEAD `92b24de74`):**

| Phase | Status | Evidence |
|---|---|---|
| P0 pipeline + spikes | ✅ | `760e09cc3`/`e16c4d8b8`/`8f4fc81ed`; docker `5:29.6.1-1~ubuntu.26.04~resolute`; kernel via R2 fallback (source-build, not procure) |
| P1 sonic-slave-resolute | ✅ | `5e29f4bcd`+`f40481279`+`c1dfdf0a3`; `fips-status.txt` records FIPS=ON (trixie reuse) |
| P2 host OS | ✅ | `a4874681d`/`41bec4fdb`/`92b24de74`; **k8s/cri skipped, not implemented per plan** (see I5) |
| P3 container base | ✅ but using trixie naming | `3d265d73b` `docker-base-trixie FROM ubuntu:resolute` |
| P4 vs container | ⚠️ committed points at the trixie-naming chain; WT repoints to resolute naming (uncommitted, see C2) |
| P5 assemble+boot | ⚠️ Partial | `sonic-vs.bin` 2.4GB + os-release=Ubuntu 26.04 asserted; **no SONiC smoke evidence**; `done-bar-status.txt` does not exist |

- **Goal 1 (source-swap): achieved, but the spec underestimated the workload.** The spec claims "almost just a source swap" / "no source-build changes" — resolute's GCC15/boost1.88/SWIG4.4/doxygen1.15/py3.14 inevitably break existing SONiC submodule source, so submodule patches are unavoidable. This is a spec problem, not an implementation problem.
- **Goal 2 (Category-C catalog): ✅ delivered and complete** (`93f1fe2a2`, 15/15 packages have a verdict, not stubs).

**Strengths worth acknowledging:** the 62 infrastructure commits are internally self-consistent; several root-cause fixes are precise — `SAI/meta/Doxyfile:312` `AUTOLINK_SUPPORT=NO` zeroes out 2199 errors in one shot (correct layer, autolink has no downstream dependency), `swss-common/common/boolean.h` removes `operator bool&()` (true root cause, semantics preserved), the `gnmi` `$function→$action` sed is version-independent, the `libnl3` linker version-script registers the symbol correctly, the `Dh_Lib.pm` single-point patch replaces the scattered `mv` band-aids; the FIPS decision is locked in and documented; the variant-naming design doc correctly diagnoses the architectural constraint.

---

## 2. Issues

### Critical (Must Fix)

**C1. A fresh clone cannot reproduce the build — all submodule source patches + multiple parent WT patches are uncommitted, and the parent pointers are not bumped.**
- Evidence: `git status --short` shows `m src/sonic-swss src/sonic-sairedis src/sonic-gnmi src/linkmgrd src/sonic-stp src/sonic-redfish src/dhcprelay src/wpasupplicant/sonic-wpa-supplicant` (lowercase m = submodule working tree dirty, pointer unchanged).
- Key uncommitted patches: `swss` c++17 + `directory.h` typedefs + tests removal; `sairedis`+`SAI` `Doxyfile`+`configure.ac`+`pyext` (the nested SAI requires 4 steps: commit SAI Doxyfile → sairedis updates the SAI gitlink → sairedis commit → parent updates the sairedis gitlink, none satisfied); `gnmi` Makefile sed + unrecorded `go.mod`/`go.sum`; `linkmgrd` 49 files; `libnl3` `Makefile`+untracked `patch/add-nh_id-aliases.sh`; `sonic_debian_extension.j2` all pip fixes; `build_debian.sh` g++/swig; variant-naming refactor 118 files.
- Impact: cloning HEAD → missing c++17/Doxyfile/boolean.h/io_context/libnl3 alias/pkgutil sed → fails all the way after the slave. Report §3 preface and §5 transparently acknowledge this, but it means "done" is not reproducible.
- Fix: commit patches inside each submodule → bump the parent gitlink → commit the parent WT. This is a prerequisite for delivery.

**C2. Variant-naming status is contradictory: report §4.5 is stale, the WT implements the coexistence scheme it claims was "rolled back", and it is unverified.**
- Evidence: report §4.5 "current status" claims "rolled back to the committed scheme (`docker-base-trixie FROM ubuntu:resolute`), the resolute variant directory is not used by the vs build". But the actual WT:
  - `dockers/docker-base-trixie/Dockerfile.j2` is **staged** changed back to `FROM debian:trixie` (reverts `3d265d73b`).
  - 118 leaf `.j2`/`.mk` change `ARG BASE`/`_LOAD_DOCKERS` from trixie to resolute (unstaged), e.g. `dockers/docker-database/Dockerfile.j2:2` → `docker-config-engine-resolute-...`, `rules/docker-database.mk` → `DOCKER_CONFIG_ENGINE_RESOLUTE`.
  - `slave.mk` WT adds a new resolute block (`filter-out $(DOCKER_BASE_TRIXIE) ...`).
  - untracked `dockers/docker-{base,config-engine,swss-layer}-resolute/` + `rules/docker-*-resolute.{mk,dep}` (FROM chain and `_LOAD_DOCKERS` self-consistent) + `docs/superpowers/specs/2026-07-05-resolute-variant-naming-design.md` design doc.
- i.e. the WT is implementing the design doc's "coexistence variant" scheme (revert trixie base to pristine + filter-out + leaf repoint to resolute), directly contradicting report §4.5 "rolled back, variant directory unused".
- Risk: (a) the report is materially inaccurate; (b) the WT refactor is unverified (build evidence Jul 4 predates WT Jul 5); (c) **the staged `docker-base-trixie` revert, if committed alone, breaks the build** (trixie libc6 2.41 < the 2.42+ required by the resolute deb, exactly the failure `3d265d73b` resolved) — it is part of an atomic refactor and cannot be committed alone.
- Fix: either revert the WT variant refactor (back to the committed "trixie name, resolute content"), or fully verify and then atomically commit the whole thing (staged+unstaged+untracked) and update report §4.5. The current half-staged state is a hazard.

**C3. The `sonic-package-manager` pkgutil sed has an off-by-one runtime bug.**
- Evidence: `files/build_templates/sonic_debian_extension.j2:1057-1061` (WT). The sed replaces `pkgutil.get_loader(f'{command}.plugins')` with `importlib.util.find_spec(...)`, and sets `pkg_loader.path = spec.submodule_search_locations[0]` (= the package directory). But the original `pkgutil.get_loader(...).path` returns `spec.origin` (= `__init__.py`). Downstream `os.path.dirname(pkg_loader.path)` therefore returns the **parent** of the plugin directory → `get_cli_plugin_directory('show')` returns `.../show` instead of `.../show/plugins`, so CLI plugin files are placed in the wrong location.
- Also `|| true` masks the sed non-match at build time (if upstream renames `pkg_loader` or changes the f-string → the broken `pkgutil.get_loader` is kept → runtime crash); the path hardcodes `python3.14/dist-packages/...` → breaks on a py3.15 upgrade.
- Fix: `pkg_loader.path = spec.origin`; a better approach is to patch the `src/sonic-utilities` source + bump the pointer (reviewable, upgrade-resistant).

**C4. The done-bar is unmet: no SONiC smoke evidence, and the build evidence predates the WT refactor.**
- Evidence: report §4 only shows `os-release` + `sonic login:`; spec §8 Phase 5 requires `config load_minigraph -y`/`show version`/`show ip intf`/containers healthy, none with output evidence. The `docs/superpowers/plans/done-bar-status.txt` required by plan Task 18 Step 5 does not exist. The `target/sonic-vs.bin` timestamp Jul 4 22:58 predates the WT variant refactor (Jul 5), so the WT state's build is unverified.
- Fix: rerun one-image + KVM in the final (post-commit) state, and record the actual smoke command output into `done-bar-status.txt`.

### Important (Should Fix)

**I5. k8s/cri skipped, not implemented per spec/plan.** `build_debian.sh:238-282` k8s block is byte-identical to trixie, with no `IMAGE_DISTRO==resolute` guard; the skip relies solely on the existing `INCLUDE_KUBERNETES=n` (`rules/config` default, not resolute-specific). The spec-promised "cleanly guarded on `IMAGE_DISTRO==resolute` (reversible for backlog)" is not delivered. `build_debian.sh:278` cri-dockerd URL `cri-dockerd_${MASTER_CRI_DOCKERD}.3-0.debian-${IMAGE_DISTRO}_amd64.deb` → under resolute produces `debian-resolute` (404 once enabled, latent backlog bug).

**I6. Kernel not procured, `config.user` dead knob.** `rules/linux-kernel.mk` unchanged (source-build); `eac57a2d5` bumps the sonic-linux-kernel submodule (libbpf const cast). `rules/config.user:26` `KERNEL_PROCURE_METHOD = download` is read by no code (dead knob), yet the comment says "download prebuilt" — doc/code mismatch. The spec main path is not implemented; the R2 fallback (source-build) was taken, but the ABI keeps `+deb13` (R2 suggested `+resolute`). Acceptable, but the misleading config.user comment should be removed/corrected.

**I7. 10 resolute platform Dockerfiles missing `--exclude=/etc/hosts` (rsync EBUSY).** The `dockers/dockerfile-macros.j2:49` macro is fixed (WT), but 10 inline-rsync `.j2` were missed: broadcom (`docker-syncd-brcm-dnx:35`, `-legacy-th:35`, `-rpc:70`, `dnx-rpc:70`), marvell-teralynx (`saiserver:47`, `syncd:39`, `rpc:59`), marvell-prestera (`saiserver:39`, `syncd:32`, `rpc:58`). Building these platform images will hit EBUSY. Report §3.1.D claims "12 Dockerfiles previously changed [committed]" — **wrong**, `git diff 77cfa809d..HEAD` shows no committed rsync/hosts changes under dockers/, all are WT. Also `/etc/hostname` is bind-mounted by buildkit and not excluded (latent).

**I8. 3 resolute Dockerfiles missing `libxml2`→`libxml2-16`.** `platform/mellanox/docker-saiserver-mlnx/Dockerfile.j2:46`, `platform/mellanox/docker-syncd-mlnx/Dockerfile.j2:36`, `platform/nvidia-bluefield/docker-syncd-bluefield/Dockerfile.j2:35` ARG BASE is switched to resolute but `libxml2` is not converted → apt-get fails on resolute.

**I9. bash plugin not ported — functional regression.** `src/bash/Makefile:15-18` `quilt push -a` is commented out, TODO "port 0001 plugin patch to 5.3". The patch file `src/bash/patches/0001-Add-plugin-support-to-bash.patch` exists and is byte-identical to trixie, but its application is disabled. The plugin = custom `plugin.c`/`plugin.h` + `load_plugins()` + `on_shell_execve` hook (used by the SONiC mgmt framework). Report §5 claims "~7 hunks" — **actually 32 hunks/8 files/583 lines**, the porting effort is severely underestimated.

**I10. swss tests removal loses ~9 test binaries (beyond the claimed root cause).** `src/sonic-swss/Makefile.am:2,4` removing `tests` from SUBDIRS discards `swssnet_ut`/`request_parser_ut`/`quoted_ut`/`aclorch_ut`/`dashtunnelorch_ut`/flex_counter/p4orch etc. ~9 binaries. The claimed root cause was only the protobuf failure in `dashtunnelorch_ut.cpp`. Acceptable for vs (runtime doesn't need tests), but a potential coverage regression for non-vs builds. More precise: remove only `dashtunnelorch_ut.cpp` from `tests_SOURCES` in `mock_tests/Makefile.am`.

**I11. linkmgrd `test/` did not finish the io_context migration.** `src/` 49 files are migrated (sound), but `test/` remains: `test/FakeLinkProber.cpp:46,73,156,168,196` 5 `ioService.post(...)` member calls not converted to free functions; `test/MuxPortTest.h:44`, `test/LinkManagerStateMachineTest.h:65` still use `io_context::work` (removed in 1.88, **kept in 1.83** — slave already switched to 1.83, so this item is a non-issue under 1.83); `test/MuxManagerTest.cpp:339` `mWork.~work()` destructor name mismatches the new `executor_work_guard` type. `make all` (vs) doesn't compile test/ so the vs build passes, but `make test` will break.

> **Note (2026-07-06):** after the slave switched to 1.83, `io_context::work` is restored, but the `ioService.post` member-call and `~work()` destructor-name issues are migration incompleteness (boost-version-independent), and `make test` is unverified under 1.83.

**I12. `slave.mk` resolute block does not filter bookworm/bullseye etc.** The WT resolute block only does `filter-out $(DOCKER_BASE_TRIXIE) $(DOCKER_CONFIG_ENGINE_TRIXIE) $(DOCKER_SWSS_LAYER_TRIXIE)`, while the default `else` branch filters all of `JESSIE..BOOKWORM`. `docker-sonic-vs` is registered in `SONIC_BOOKWORM_DOCKERS` (`platform/vs/docker-sonic-vs.mk:53`) + `SONIC_DOCKER_IMAGES`, whose `_LOAD_DOCKERS=DOCKER_SWSS_LAYER_BOOKWORM` (not built). It is blocked by the `platform/vs/syncd-vs.mk:7 findstring(BLDENV, bookworm trixie)` + installer double guard, so it is latent-inactive under vs, but should be filtered to be consistent with the default branch and avoid future surprises.

**I13. The `Dh_Lib.pm` patch is non-idempotent and fragile.** `sonic-slave-resolute/Dockerfile.j2:862-864` (commit `c1dfdf0a3`): `grep -q "DBGSYM_PACKAGE_TYPE' => 'ddeb'" ... && sed ...`. When rerun on an already-patched layer the first `grep -q ddeb` fails → the `&&` chain short-circuits → RUN exits 1 → build fails. It only actually works because the slave always rebuilds from a fresh `FROM ubuntu:resolute`. It should be `grep -q deb || sed ...`. A debhelper upgrade could hard-fail (base is pinned, low risk).

**I14. The global `-std=gnu17` is the wrong layer.** `sonic-slave-resolute/Dockerfile.j2:884` (commit `f40481279`) writes `APPEND CFLAGS -std=gnu17 ...` to `/etc/dpkg/buildflags.conf`. Only CFLAGS (no CXXFLAGS), so standard C++ compilation is safe; but `wpasupplicant` `build.rules:85-94` uses `%.c*` to glob `.cpp` through `$(CC) $(CFLAGS)` → `cc1plus: -std=gnu17 valid for C/ObjC but not C++`, requiring the §3.7 WT separate `DEB_CFLAGS_MAINT_STRIP` remedy. Cleaner: drop the global C standard and fix bash's K&R issue per-package with `DEB_CFLAGS_MAINT_APPEND`.

**I15. `libnl3` silently drops 4 patches + dead code + wrong version-number advice.** `src/libnl3/Makefile:32-33` uses `bash ../patch/add-nh_id-aliases.sh` to replace `stg import -s ../patch/series`, orphaning `switch-to-debhelper.patch`, `keep-symbol-versions-in-libraries.patch`, `update-changelog.patch`, `skip-tests-when-having-no-private-netns.patch` — report §3.1.E does not mention this. The awk in `debian/libnl-route-3-200.symbols` is **dead code** (the file is only a 16-line template, the regex `^rtnl_route_get_nhid;$` never matches, the report's claim that "symbols file updated" is misleading). `patch/0004-rtnl_route_get_nh_id-alias-for-3.12.patch` is orphaned and unreferenced. Report §6 lesson 2's advice to bump the version to `3.12.0-2~sonic1` is a **regression** — `~` sorts before the empty string in dpkg comparison, making it older than `3.12.0-2`, so apt won't overwrite; it should be `3.12.0-2+sonic1` or `3.12.0-2.1`. The alias script is non-idempotent (no grep guard, mitigated by `rm -rf ./libnl3-3.12.0`).

**I16. `gnmi` `go.mod`/`go.sum` unrecorded changes.** go-redis `v7.0.0-beta`→`v7.4.1`, adding `cncf/xds`, `envoyproxy/go-control-plane`, `protoc-gen-validate`, `genproto`. Report §3.5 does not mention it. Likely the result of the new Go toolchain's `go mod tidy`, but should be recorded or reverted.

**I17. The trixie control path is partially broken.** `Makefile:53-74` catch-all has removed trixie dispatch (resolute only), `make <target> BLDENV=trixie` via the catch-all does not work; trixie only works via `make_work` (`Makefile:120` `$(if $(BUILD_TRIXIE),...)`, used for `sonic-slave-build` etc.) or directly `make -f Makefile.work BLDENV=trixie <target>`. spec §8 requires trixie to remain available as a control throughout — slave build works, but one-image via the top-level catch-all does not. And after the WT variant refactor the leaves point at the resolute base, so `BLDENV=trixie` would pull the resolute base (not a pure trixie control); under the committed state trixie control is intact.

**I18. `dget -u` via HTTP skips GPG + future 404 risk.** bash/socat/libnl3/libyang3/grub2 + lldpd/openssh/makedumpfile/kdump-tools all use `dget -u` (skip GPG) over HTTP. Integrity gap (consistent with existing SONiC convention); Ubuntu pool deletes the .dsc when a version is superseded → future build 404 risk.

### Minor (Nice to Have)

- **M19.** `dockers/docker-swss-layer-resolute.mk:1` comment still says "trixie-based docker image" (copied, not updated).
- **M20.** The catalog libnl3 row claims "RTA_NH_ID NOT in resolute libnl3 3.12.0" — imprecise: the feature is already implemented upstream (`rtnl_route_get_nhid` without underscore, field `rt_nhid`, attr `ROUTE_ATTR_NHID`); only the SONiC legacy name (with underscore) is missing.
- **M21.** Report §3.7 classifies `sonic-eventd`/`sonic-sysmgr` as submodules — they are actually parent-repo tracked trees; `sonic-dbus-bridge` is a subdirectory inside `sonic-redfish`, not a submodule.
- **M22.** Report §3.1.B attributes M2Crypto `CFLAGS=-D__fds_bits=fds_bits` and `systemctl disable resolvconf.service || true` to `build_debian.sh` — they are actually in `sonic_debian_extension.j2:87,545` (§3.1.C is correct, §3.1.B is internally inconsistent). "glibc 2.43 renamed `__fds_bits`" is also inaccurate — the split has long existed; the real trigger is M2Crypto SWIG hardcoding `__fds_bits` while `Python.h` defines `_GNU_SOURCE`→`__USE_XOPEN`→`__fds_bits` hidden. M2Crypto is installed via apt (`j2:265`), and the `install_pip_package` macro's CFLAGS doesn't apply to it at all.
- **M23.** Report §3.4's "2199 unrecognized-tag" label is slightly off — it is actually `invalid type tag value` (`ProcessTagType` anchored regex mismatch), not an unrecognized tag name.
- **M24.** `sonic_debian_extension.j2:231` comment "regex by pyangbind transitive" is stale (regex is pulled in via sonic-utilities).
- **M25.** `sonic-slave-resolute/Dockerfile.j2:734-735` cross-build path still installs unversioned `libboost-dev:$arch` — same as the amd64 fix's 1.90 header-only trap, reappears on armhf/arm64 (latent).
- **M26.** Report §3.1.A says gcc-multilib is for openssh — commit `e3a75d22f` says it is for building grub2 i386 modules (libwtmpdb-dev is the one for openssh).
- **M27.** The working tree has residual build artifacts (`database-chassis.service`, `installer/platforms*`, `*.egg-info`, `src/*/build`) that should be gitignored/cleaned; only `docker-base-trixie` is staged while the rest are unstaged — inconsistent staging.

---

## 3. Recommendations

1. **Commit before declaring done.** Commit source patches inside each submodule → bump the parent gitlink → commit the parent WT (`sonic_debian_extension.j2`/`build_debian.sh`/`slave.mk` resolute block/`libnl3` alias/`dockerfile-macros.j2`/12 Dockerfile rsync/variant refactor or its revert). Before committing, rerun a fresh-clone build to verify reproducibility (C1).

2. **Resolve the variant-naming either-or.** Either revert the WT variant refactor (back to the committed "trixie name, resolute content", making report §4.5 accurate), or fully verify per the design doc and atomically commit (staged docker-base-trixie revert + 118 leaves + slave.mk block + variant directories) and update report §4.5. Never keep the current half-staged state (C2). The design-doc scheme itself is sound (revert trixie base to pristine + filter-out + leaf repoint to resolute), but the slave.mk resolute block should also filter `SONIC_BOOKWORM_DOCKERS` etc. to be consistent with the default `else` (I12).

3. **Fix the `pkgutil` sed off-by-one.** `pkg_loader.path = spec.origin` (not `submodule_search_locations[0]`); or patch the `sonic-utilities` source + bump the pointer (C3). Remove the hardcoded `python3.14` in the path.

4. **Provide done-bar evidence.** Rerun `make PLATFORM=vs BLDENV=resolute` + KVM boot in the final (post-commit) state, and record the actual output of `config load_minigraph -y`/`show version`/`show ip intf`/`docker ps` into `docs/superpowers/plans/done-bar-status.txt` (C4).

5. **Fill in the 13 missing Dockerfiles.** 10 inline-rsync add `--exclude=/etc/hosts` (I7); 3 add `libxml2-16` (I8). Cross-check the whole tree with `grep -rn 'rsync -axAX' platform/ dockers/` + `grep -rn 'libxml2\b' platform/ dockers/`.

6. **Make the k8s/cri guard explicit.** Even if continuing to use `INCLUDE_KUBERNETES=n`, change the cri-dockerd URL at `build_debian.sh:278` to a form not depending on `debian-${IMAGE_DISTRO}`, or state explicitly in the spec "skipped via existing flag" and update plan Task 12 (I5).

7. **Align kernel docs.** Remove the `config.user` `KERNEL_PROCURE_METHOD=download` dead knob and its misleading comment, or implement the procure path (I6).

8. **Harden sed patches.** The `pkgutil` sed, the `hsflowd`/`sonic-stp` Maintainer sed, the `gnmi` `$function` sed — prefer patching source + bumping the pointer over sed'ing generated/imported files; when sed is necessary, use a stable anchor (function signature rather than line number/variable name), and add a `grep -q` idempotency guard (same for C3, I13, I15).

9. **Wrap up `libnl3`.** Decide alias wrapper vs version bump (use `+sonic1` not `~sonic1`); delete the 4 orphaned patches or explicitly port them; delete the dead-code symbols awk + the orphaned 0004 patch + the stg git init dead overhead; add a grep guard to make the script idempotent (I15).

10. **Make `-std=gnu17` per-package.** Drop the global `APPEND CFLAGS -std=gnu17`, use `DEB_CFLAGS_MAINT_APPEND=-std=gnu17` for bash, avoiding the wpasupplicant-style `$(CC)$(CFLAGS)`-on-.cpp chain remedy (I14).

11. **Decide on the bash plugin.** Port the 32 hunks to 5.3, or explicitly mark "plugin functionality not provided on resolute" as a known regression in the catalog/report (I9).

12. **Wrap up swss tests / linkmgrd test/.** swss: remove only `dashtunnelorch_ut.cpp` (keep the rest of the tests); linkmgrd: finish the `test/` migration (5 `ioService.post` + `io_context::work` + `~work()`), so `make test` doesn't break (I10, I11).

13. **Correct the report.** Fix §3.1.B/§3.1.D attribution and "committed" misstatements, §3.1.E symbols misleading, §3.5 unrecorded go.mod, §3.6 unmigrated test/, §4.5 variant status, §5 bash hunks count (M19-M27).

---

## 4. Assessment

**Ready to declare done?** **No / With fixes.**

**Reasoning:** The infrastructure layer (62 commits: slave/FIPS/grub2 split/dbgsym single-point/dget swap/pipeline) and the Goal 2 catalog (15/15 complete) are solid, several root-cause fixes are precise (Doxyfile/boolean.h/gnmi sed/libnl3 version-script), and the FIPS decision is locked in with rationale. But it is currently not deliverable due to four hard blockers:

1. **Build not reproducible:** a fresh clone of HEAD is missing all submodule source patches + parent pointers not bumped (C1);
2. **Report contradicts code:** report §4.5 directly contradicts the actual WT state, the WT is an unverified variant refactor and the staged revert alone breaks the build if committed (C2);
3. **Runtime bug:** the `pkgutil` sed off-by-one is a real runtime bug (C3);
4. **Done-bar lacks evidence:** no SONiC smoke evidence and the build evidence predates the WT refactor (C4).

Only after filling in the 13 Dockerfiles of I7/I8, committing all submodule patches + pointers, resolving the variant naming either-or, fixing C3, and providing smoke evidence can done be declared.

> **Follow-up update (2026-07-05, see §5):** The above four hard blockers (C1-C4) **have all been resolved** — C1 submodule patches + pointers committed, C2 variant-naming committed per the design doc, C3 pkgutil sed fixed, C4 build + KVM smoke verified (the two smoke "failures" were investigated via systematic-debugging and neither is a build defect). Current status: **deliverable**, with only Important/Minor leftovers remaining (I7-I15, none affecting the vs build).

---

## 5. Follow-up Status

Items handled after the review (resolute repo `resolute` branch):

| Issue | Status | Evidence |
|---|---|---|
| **C1** submodule patches uncommitted + parent pointers not bumped | ✅ Fixed | 14 submodules committed patches on their respective `resolute` branches + parent gitlink bump (`5e4f25d43`); 3 corrupted object stores (mgmt-framework/swss/sairedis) fixed by re-cloning from origin; fresh clone reproducible |
| **C2** variant-naming report contradicts code | ✅ Fixed | variant-naming refactor committed per the design doc (`a8fee77a4`, 113 files); report §4.5 updated to reflect the committed state; C4 verified docker image `resolute.0-e938608` tag |
| **C3** pkgutil sed off-by-one | ✅ Fixed | `sonic_debian_extension.j2` changed `spec.submodule_search_locations[0]` → `spec.origin` (`e93860839`); after the C4 build, manager.py in fsroot-vs/squashfs confirmed to contain `spec.origin` |
| **C4** done-bar smoke no evidence | ✅ Passed | post-commit state build succeeded + KVM boot + `show version` (build commit e938608) + `docker ps` (containers healthy) + os-release=Ubuntu 26.04 ✅. Two smoke commands "failed" but investigation confirmed neither is a build defect (see below). See `done-bar-status.txt` for details |
| **boost 1.83 landed** (2026-07-06) | ✅ Landed | `sonic-slave-resolute/Dockerfile.j2` 18 lines `1.88-dev`→`1.83-dev` (resolute working tree, uncommitted). Reason: resolute default boost 1.90 (main, `boost_system` header-only with no `libboost_system.so`), 1.83/1.88 are in universe; choosing **1.83** aligns with the trixie/bookworm upstream (trixie `libboost-dev` default is 1.83, the bookworm slave also pins 1.83), and 1.83 keeps `io_service`/`io_context::work`/`extension`/`std::hash<uuid>` that 1.88 removed. Experimentally verified slave rebuild + libswsscommon/sonic-eventd/ssg/linkmgrd (four packages) compile successfully; submodules with migrated io_context code are 1.83-compatible and kept without revert. The cross-build path's unversioned `libboost-dev:$arch` (→1.90, M25) was not fixed at the same time |
| **I19** iproute2 missing in docker-base-resolute (2026-07-15) | ✅ Fixed | Root cause: `docker-base-resolute/Dockerfile.j2` was copied from trixie, which omits `iproute2` from apt (trixie installs it as a locally-built deb via `rules/iproute2.mk`). But `rules/iproute2.mk` guards `IPROUTE2` with `ifeq ($(BLDENV),trixie)` — under resolute the variable is empty, and `docker-base-resolute.mk`'s `$(IPROUTE2)` dependency silently expands to nothing → the `ip` command was absent from all resolute containers. Fix: add `iproute2` to apt install list in `docker-base-resolute/Dockerfile.j2`; remove `$(IPROUTE2)` dependency from `rules/docker-base-resolute.mk`. EVPN Multihoming protocol field patch is dropped (not needed for current scope). Same BLDENV-guard pattern also affects `sonic-redfish` (`BMCWEB`/`SONIC_DBUS_BRIDGE` empty, bmcweb/sonic-dbus-bridge silently missing) and `platform/vpp` (`VPPINFRA` not built) — known, not yet fixed |

**C4 investigation conclusions (systematic-debugging):**
- **`failed to import plugin show.plugins.dhcp-relay/macsec`** — not a squashfs packaging loss (previously misdiagnosed, because the non-real intermediate artifact `target/sonic-vs.bin__vs__rfs.squashfs` was inspected, which only contains the requests dependency tree). Inspecting the **real runtime rootfs** (qcow2 `part3/image-resolute.0-e938608/fs.squashfs`) confirmed `show/plugins/` has the full 18 .py including `dhcp-relay.py`/`macsec.py`, sonic-utilities complete. Real cause: Python module names cannot contain hyphens — `util_base.py:23` `pkgutil.iter_modules` returns the on-disk name `dhcp-relay`, `:31` `importlib.import_module` inevitably raises `ModuleNotFoundError`. **upstream master is unfixed** (also uses `import_module`), commits `f36ac95a`/`8647356d` downgraded to `log_warning` (non-fatal); tri/202605 fail the same way → not a resolute regression, not C1-C3.
- **`show ip intf`/`show ip bgp sum` "No such command"** — real cause: `Db()` fails to connect to configdb (during smoke the database container had just come Up + vs has no minigraph → configdb empty/not ready) → click doesn't register the `ip` subcommand tree. A runtime/timing issue, not a build defect.
- **`config load_minigraph -y`** — the vs image does not preinstall `minigraph.xml` by default (`OSError`), expected behavior, needs to be generated/imported separately.
- **3 submodule object stores corrupted** (during C1): the `--reference` clone's alternates were lost + `git gc` left missing blobs/trees. Fixed by re-cloning. Worth recording in the build-restore docs.
- **Investigation lesson:** when investigating vs rootfs issues, inspect the **real runtime squashfs** (qcow2 `part3/image-*/fs.squashfs`, via qemu-nbd + squashfs mount), not the build intermediate artifact `target/*.squashfs` — the latter may be an incomplete stale snapshot.

**Still unhandled (review Important/Minor, by priority, none affecting the vs build):**
- I7/I8: 13 platform Dockerfiles missing `--exclude=/etc/hosts` / `libxml2-16` (non-vs platforms)
- I9: bash plugin not ported (32 hunks/8 files/583 lines)
- I10/I11: swss tests removal / linkmgrd test/ unfinished io_context migration (`make test` breaks, vs build doesn't compile test/)
- I13/I14/I15: `Dh_Lib.pm` non-idempotent / global `-std=gnu17` / libnl3 dead code and version-number advice (`+sonic1` not `~sonic1`)
