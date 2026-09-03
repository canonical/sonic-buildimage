# Reviewing PR #10 "re-enable resolute package tests": a three-way cross-check, and a real regression hidden behind nocheck

**Date**: 2026-09-03
**Subject**: `canonical/sonic-buildimage#10` — `build(resolute): re-enable package test suites`
**base / head**: `canonical/202605_resolute` → `canonical/202605_resolute_enable_tests` (merge-base `c037019737`)
**Files changed**: `.gitignore`, `AGENTS.md`, `rules/config`, `rules/swss.mk`, `slave.mk`, `src/sonic-snmpagent` (gitlink), `src/sonic-yang-models/tests/yang_model_tests/test_yang_model.py`
**Upstream baseline**: `sonic-net/202605`

---

## 1. Summary

Recommend **merge after changes**. The direction is right: `rules/config:404`'s `BUILD_SKIP_TEST ?= n` restores upstream `sonic-net/202605:rules/config:398` exactly, which is a clean de-fork. Three classes of problem remain:

1. **`nocheck` is masking a real regression**: Ubuntu's default link flag `-Wl,-Bsymbolic-functions` breaks the symbol-interposition mechanism the swss unit tests rely on. That is a direct product of the Debian→Ubuntu migration — precisely the class of defect this migration exists to find. See §3.2.
2. **`AGENTS.md` carries two statements that are the opposite of the tree state**, and the file's own Scope section forbids exactly the kind of content this PR adds to it. See §3.3, §3.4.
3. **There is a gap between "tests are enabled" and "tests actually ran"**: swss gets a package-wide `nocheck`, the chassisd suite is skipped wholesale, and some packages are silently served from cache when caching is enabled.

§3.3 (the `AGENTS.md` factual inversions) was reached **independently by three reviewers**. §3.2 (the real regression) has since been settled by a controlled A/B experiment: with the same test binary and only the `.so` swapped, the flagged build throws the redis exception and exits 134, while the stripped build passes **all 770 cases** — with no redis in the container at any point. The fix is one line, and it is verified.

**One significant downgrade**: the chassisd item was initially judged by all three reviewers as "the code contradicts the description", but checking upstream showed that **upstream never runs this suite either** (the `sonic_chassisd` wheel is only built under `BLDENV=trixie`, and upstream's skip covers exactly trixie), so this PR's code matches upstream and needs no change; running the suite also confirmed the description's "216 passed / 2 multiprocessing failures" numbers are accurate. Only the wording needs fixing. See §3.1 — which is also this review's example of how "multiple reviewers agree" can agree on the wrong thing.

---

## 2. Method and confidence levels

Four mutually independent review passes were run. Every conclusion below was re-verified by me against the original files or build artifacts before being accepted:

| Pass | Reviewer | Role |
|---|---|---|
| 1 | `code-review` skill (max) | First full sweep, 14 findings |
| 2 | Codex `gpt-5.6-sol`, effort=low | Independent re-review (effort defaulted by mistake, output visibly thin — see §9) |
| 3 | Codex `gpt-5.6-sol`, effort=xhigh | Independent re-review |
| 4a | fable | Targeted verification of three high-priority conclusions (given the propositions, so anchoring risk) |
| 4b | fable | Fully independent full review (told nothing about any prior conclusion) |

Markers used below:

- **[three-way]** — multiple reviewers converged without knowledge of each other; highest confidence
- **[measured]** — I ran the verification in the real build environment or on the artifact
- **[inferred]** — derived from code semantics, not directly observed
- **[unverified]** — cannot be settled from the repository; recorded as claimed

**One method note**: a conclusion must not be accepted just because it came from a stronger model or a higher effort setting. §3.2 and the third row of §7 are a case where the *same* model gave opposite answers on two runs; the tie was broken by going back to the source and checking which link unit the definition lives in, not by comparing the authority of the sources.

---

## 3. Must be addressed before merge

### 3.1 The whole `sonic_chassisd` suite is skipped — behaviour matches upstream, but the description's wording misleads [three-way + measured]

> **This item was downgraded on re-check.** All three first-pass reviewers treated it as "the code contradicts the description", but after checking upstream and actually running the tests: **upstream `sonic-net/202605` never runs this suite either**, and this PR merely carries the same behaviour over to resolute, so the code is correct. What remains is a wording problem in the PR description. The original derivation is kept below; the grounds for the downgrade are in §3.1.3 and §3.1.4.

#### 3.1.1 Mechanism

`slave.mk:35` is `PYTHON_WHEELS_PATH = $(TARGET_PATH)/python-wheels/$(BLDENV)`, so with `BLDENV=resolute` the wheel target path necessarily contains `resolute`, and the branch this PR adds matches:

```make
if case "$@" in *trixie*sonic_chassisd*|*resolute*sonic_chassisd*) true;; *) false;; esac; then \
    echo "Skipping tests for sonic_chassisd on $(BLDENV) ($@)"; \
elif [ ! "$($*_TEST)" = "n" ] && [ ! "$(BUILD_SKIP_TEST)" = "y" ]; then \
    ... python -m pytest; \
```

Once it matches, only the `echo` runs; the pytest branch starting at `slave.mk:1107` is never reached. Alternative paths were exhaustively ruled out:

- `rules/sonic-chassisd.mk` is 6 lines total, with no `_TEST` and no test hook
- `dockers/*/cli-plugin-tests` exists only for dhcp-relay, dhcp-server, gnmi-sidecar, macsec, restapi-sidecar and telemetry-sidecar — none is chassisd
- there is no other chassisd pytest invocation anywhere in `slave.mk`, `rules/` or `dockers/`

→ **The chassisd test count in this PR's builds is definitively 0.**

The skip was already present in the PR's **first commit** `45c3d0ef7f`, so no build in this PR's history ever ran it.

#### 3.1.2 The numbers in the PR description are accurate — reproduced by running them

Inside the `sonic-slave-resolute` image, after installing the `_DEBS_DEPENDS` (`libyang3`, `libnl-*`, `libswsscommon`, `python3-swsscommon`) and all wheels, `python3 -m pytest` gives:

```text
FAILED tests/test_chassisd.py::test_daemon_run_smartswitch - AssertionError: ...
FAILED tests/test_chassisd.py::test_daemon_run_supervisor  - AssertionError: ...
=================== 2 failed, 216 passed, 1 warning in 6.64s ===================
```

**216 passed / 2 failed, and those two are genuinely multiprocessing failures** — so the numbers in the description are not invented; the author did run them by hand.

The failure stack:

```text
scripts/chassisd:1858: in run  →  self.config_manager.task_stop()
sonic_py_common/task_base.py:47: in task_stop  →  self._task_process.join(...)
/usr/lib/python3.14/multiprocessing/process.py:155: AssertionError:
    can only join a started process
```

(I had earlier questioned these two failures on the grounds that grepping the chassisd directory for `multiprocessing` gives zero hits — that was looking in the wrong place: the multiprocessing comes from the shared `sonic_py_common`, not from chassisd's own source. Correction in §8.)

#### 3.1.3 Upstream never runs this suite

The chain closes, and every link is checkable:

1. the only consumer of the `sonic_chassisd` wheel is `$(DOCKER_PLATFORM_MONITOR)_PYTHON_WHEELS` at `rules/docker-platform-monitor.mk:24`
2. and `rules/docker-platform-monitor.mk:79` is `SONIC_TRIXIE_DOCKERS += $(DOCKER_PLATFORM_MONITOR)` — it appears in no legacy docker list (grepping `SONIC_BOOKWORM_DOCKERS` and friends gives zero hits)
3. → upstream builds this wheel only in the `BLDENV=trixie` pass (in the dispatch at `Makefile:48-68`, the bookworm pass's make target is the literal `bookworm`; only the trixie pass builds the actual `$@`)
4. → upstream's `*trixie*sonic_chassisd*` at `slave.mk:1098` therefore covers **every** situation in which the wheel is built

**So the chassisd tests are entirely off on upstream `sonic-net/202605`** — there is no "upstream runs them on bookworm and only skips on trixie" partial enablement. This PR carries the same policy to resolute, which is behaviourally consistent with upstream.

#### 3.1.4 Why upstream does not enable it: what is known and what is not

**Known:**

- The skip was introduced upstream by `bc13e6afa5` (PR #26002, "Support for BMC cards based on Aspeed 2720 - Phase 2", merged 2026-04-30, Chandrasekaran Swaminathan / chander-nexthop)
- That is a 58-file, +1724/−484 BMC platform PR that **does not touch `src/sonic-platform-daemons`**, so it did not introduce the failure
- **It left no rationale whatsoever**: the commit message is entirely about BMC and never mentions the test skip; searching PR #26002's body and its 33 comments for `chassisd`, `skip.*test` or `pytest` gives zero hits
- The root cause is a missing guard in `sonic-py-common`: `task_base.py`'s `task_run()` returns early when `task_stopping_event` is already set, while `task_stop()` unconditionally calls `self._task_process.join(...)`, which hits CPython's assertion for a `Process` that was constructed but never `start()`ed. `src/sonic-py-common` is an in-tree directory (not a submodule) and its tree hash is **identical** on upstream 202605 and on this PR's branch (`1f1ce57acd`); upstream's copy of the file has no guard either
- The two tests were added on 2024-12-16 by sonic-platform-daemons `3fe8841` (#467, "Added SmartSwitch support in chassisd and enabling chassisd") — roughly 16 months before the upstream skip, so this is not a case of a new test breaking immediately

**Not known [inferred]:** why the failure starts exactly on trixie. Upstream's trixie slave is python3.13, bookworm is 3.11, resolute is 3.14; the code is byte-identical yet the outcome differs, which points at a Python-version-dependent `multiprocessing`/mock interaction, but the specific change was not pinned down (no py3.11/3.13 control environment available locally).

#### 3.1.5 Action

**No code change needed** — upstream does not enable it, so neither must we, and this PR already matches upstream.

**The description does need two wording fixes:**

1. "the 2 multiprocessing failures **excluded by the skip**" — the skip excludes all 218 cases, not those 2. It should read "suite skipped, mirroring upstream's trixie skip (`slave.mk:1098`)"
2. The Verification section should not present "216 passed" as a product of this build; it came from a manual run and should be labelled as such

**Optional follow-up**: if the coverage is genuinely wanted back, the right entry point is adding a "was it started" guard to `sonic-py-common`'s `task_stop()` — that is the only thing blocking 218 cases, and fixing it in the shared library would benefit upstream too. This is out of scope for this PR; a separate issue is recommended.

### 3.2 The stated reason for `rules/swss.mk`'s `nocheck` does not hold; the real cause is an Ubuntu default link flag [measured]

The PR argues that "`p4orch_tests` requires redis-server, which the slave container doesn't install, so the check can never pass", that "this is **not** introduced by Debian→Ubuntu migration", and that "the redis dependency is upstream design". Three counter-checks:

| Check | Result |
|---|---|
| Does upstream `sonic-slave-trixie/Dockerfile.j2` have redis-server? | **No.** Only `:137` `libhiredis-dev`, the pip `redis` client, and `mockredispy` — identical to resolute line for line |
| Does upstream `rules/swss.mk` have `nocheck`? | No, nor any `_DEB_BUILD_PROFILES` |
| Upstream `rules/config:398` | `BUILD_SKIP_TEST ?= n` |
| Does upstream CI override it? | `git grep BUILD_SKIP_TEST -- .azure-pipelines/` gives **zero hits** |

So upstream trixie runs the very same p4orch check in a slave that likewise has no redis. The real cause, verified step by step on the build artifact:

1. **The dpkg vendor difference between Ubuntu and Debian**
   `/usr/share/perl5/Dpkg/Vendor/Ubuntu.pm:243` contains `$flags->prepend('LDFLAGS', '-Wl,-Bsymbolic-functions')`; `Debian.pm` has **zero** occurrences of that string.

2. **The flag really reaches the link command**
   `target/debs/resolute/libswsscommon_1.0.0_amd64.deb.log:583` (the libtool link line for the `.so`) carries it; 16 occurrences across the log.

3. **Consequence: intra-library calls can no longer be interposed**
   Extracting `libswsscommon.so.0.0.0` from the deb, `readelf -rW` shows 294 `JUMP_SLOT` relocations, of which the number naming a `swss::` symbol is **0** (they are all external symbols such as `_Znam`, `freeReplyObject`, `__errno_location`). Every intra-library `swss::` function call is therefore bound to the library's own definition at link time, with no PLT indirection.

   > Pitfall in the check: `readelf -r` truncates the type name to `R_X86_64_JUMP_SLO` (no trailing `T`), so `grep JUMP_SLOT` returns a false zero. The correct criterion is "zero `swss` symbols *among* the JUMP_SLOT entries", not "zero JUMP_SLOT entries".

4. **The trigger path**
   `orchagent/p4orch/tests/test_main.cpp:211` calls `swss::Logger::linkToDb` → `logger.cpp:159` → `:161 linkToDbWithOutput` → `:126 DBConnector db("CONFIG_DB", 0)` (the real constructor) → `dbconnector.cpp:606` throws `"Unable to connect to redis (unix-socket) - "`, which matches the error text reported in the PR **verbatim**.

5. **Why the fake fails**
   `fake_dbconnector.cpp:38` defines exactly `DBConnector(const std::string&, unsigned int, bool)`, but it relies on PLT interposition for that **library-internal** call, and `-Bsymbolic-functions` closes that route.

This is a **general breakage**, not a p4orch quirk: `tests/mock_tests/mock_dbconnector.cpp` uses the same interposition trick and would be broken the same way.

#### 3.2.1 A controlled A/B experiment: the fix is verified, and redis is not needed at all

Step 5 above started as an inference. It has since been turned into a single-variable experiment and run — **the test binary is compiled once, and only the `.so` is swapped** (stripping the flag changes neither the ABI nor the SONAME, so the libraries are interchangeable).

Insert one line into swss-common's `debian/rules`, **before** `include /usr/share/dpkg/default.mk` (it must precede the include, otherwise `dpkg-buildflags` has already computed the flags):

```make
export DEB_LDFLAGS_MAINT_STRIP = -Wl,-Bsymbolic-functions
```

First, what changes at the link level after the rebuild:

| Metric | Original | Flag stripped |
|---|---|---|
| `Bsymbolic-functions` hits in the build log | 16 | **0** |
| `JUMP_SLOT` slots for `swss::` symbols in the `.so` | **0** | **351** |
| of which `DBConnector` constructors | 0 | **7** |

Then, using the same `p4orch_tests` binary, in the **same container with no redis service running at any point**, switching only `LD_LIBRARY_PATH`:

```text
── A, control (original .so, with -Bsymbolic-functions)
terminate called after throwing an instance of 'std::system_error'
  what():  Unable to connect to redis (unix-socket) - No such file or directory(1): Cannot assign requested address
exit code: 134   (SIGABRT)

── B, treatment (.so with the flag stripped)
[==========] 770 tests from 16 test suites ran. (70 ms total)
[  PASSED  ] 770 tests.
  YOU HAVE 3 DISABLED TESTS
exit code: 0
```

**This settles three things:**

1. **The link flag is the cause.** Single variable, same binary, same container; only the `.so` differs, and the outcome goes from SIGABRT to all green.
2. **redis is not needed anywhere.** All 770 cases pass in group B with no redis-server and no socket in the container. Both "requires redis-server to run" and "The redis dependency is upstream design" in the PR description are wrong.
3. **The fix works and costs one line.** The case count is self-consistent too: the earlier static count of 773 `TEST_F`/`TEST(` occurrences minus the 3 `DISABLED` ones is exactly 770.

This also retroactively supports "it passes on the upstream Debian side": `Debian.pm` does not add the flag, so the fake works there. (Still not directly observed on a Debian-built artifact [inferred], but the A/B has pinned the causation on the flag.)

#### 3.2.2 Action

**Preferred: one line, super-repo only, net zero lines — it can go into this very PR.**

`DEB_LDFLAGS_MAINT_STRIP` is read by `dpkg-buildflags` **from the environment**; the `export` in `debian/rules` is merely one way of getting it there. And `slave.mk:938/939` (the `SONIC_DPKG_DEBS` recipe) already prefixes `${$*_BUILD_ENV}` to the `dpkg-buildpackage` command line — and swss-common is exactly a `SONIC_DPKG_DEBS` package (`rules/swss-common.mk:16`). So the submodule need not be touched at all:

```diff
  # rules/swss-common.mk
+ $(LIBSWSSCOMMON)_BUILD_ENV = DEB_LDFLAGS_MAINT_STRIP="-Wl,-Bsymbolic-functions"

  # rules/swss.mk — delete the line this PR adds
- $(SWSS)_DEB_BUILD_OPTIONS = nocheck
```

**Net zero lines** (one traded for another), **no submodule commit**, **no gitlink bump**. `_BUILD_ENV` is an existing mechanism with 10+ precedents in the repository (`platform/*/libsaithrift-dev.mk`, `platform/broadcom/sai-modules.mk`, and others).

Verified: with `debian/rules` left byte-identical to the repository (confirmed by `diff -q`), rebuilding swss-common with the environment variable alone produces **exactly** the same result as the `debian/rules` route — zero `Bsymbolic` hits in the build log, 351 `swss::` `JUMP_SLOT` slots, 7 DBConnector constructors — and `hardening=+all` is unaffected (the `.so` still carries `BIND_NOW`).

> Choice of variant: `DEB_LDFLAGS_STRIP` (the builder channel) fits our position — we are the builder, not the upstream maintainer — better than `DEB_LDFLAGS_MAINT_STRIP` (the maintainer channel), and the two produce identical output at the `dpkg-buildflags --get LDFLAGS` level. But the full rebuild was only run with `MAINT_STRIP`, so that is the recommendation for now; switching to `STRIP` would want one more verification run.

**Second choice (if the fix must live inside the package)**: add the line to swss-common's `debian/rules`, before `include /usr/share/dpkg/default.mk`. That route has to follow the AGENTS.md Submodules rule — commit to `canonical/sonic-swss-common:202605_resolute` first, then bump the gitlink, in its own PR. Its advantage is that it is also valuable upstream (every C++ unit test on Ubuntu that relies on symbol interposition is affected the same way; `tests/mock_tests/mock_dbconnector.cpp` uses the identical trick); its cost is a far heavier process. **Recommendation: unlock the tests with the one super-repo line now, and pursue the in-package fix separately as an upstream contribution.**

**If this PR does not do it**: at minimum remove the two causal assertions from the description and replace them with a pointer to this section plus a TODO. Keeping `nocheck` itself is acceptable, but it must not stay in the repository with a wrong justification attached.

**What the fix costs, and why that is acceptable.** `DEB_LDFLAGS_MAINT_STRIP` applies to the whole package, so **the shipped `libswsscommon.so` also loses the flag**, not just the test build. Two consequences:

- Intra-library calls to the library's own functions gain a level of PLT indirection. There is a theoretical cost; in practice it is negligible — this is the normal state of most distribution libraries.
- `swss::` symbols become interposable at runtime. That is what the tests need, and it is a genuine behavioural change.

The key point: **this removes a divergence rather than introducing one.** Debian's `Dpkg/Vendor/Debian.pm` never adds the flag, so the `libswsscommon.so` that upstream Debian trixie ships has always had the PLT slots and has always been interposable. Stripping it makes resolute's library match upstream Debian's on this point; *keeping* it is the resolute-only deviation — one that Ubuntu's vendor default introduced quietly, without anyone choosing it.

By the same logic the line could instead go into the slave image's global build flags (see the existing practice recorded in [the slave image's global build-flag override](2026-08-24-resolute-port-final-state-and-pitfalls-en.md)), restoring Debian semantics for every self-built C++ package. But that has a much larger blast radius, needs separate evaluation, and should not ride along on this PR or on the swss-common fix.

### 3.3 Two `AGENTS.md` "known deviations" are the opposite of the tree state [three-way]

`AGENTS.md:36-38`, newly added (absent from base):

> libnl3 uses injected API aliases instead of upstream's `rtnl_route_get_nhid`; flashrom and sedutil were de-forked to stock Ubuntu debs

| Statement | Tree state |
|---|---|
| libnl3 uses injected API aliases | **Inverted.** `rules/libnl3.mk:3-5` says the opposite in its own comment: fetch stock Ubuntu 3.12.0-2 via `SONIC_ONLINE_DEBS`, because "SONiC's only patch (nh-id alias) is obsolete — sonic-swss now uses the stock `rtnl_route_get_nhid` spelling"; `:61` goes through ONLINE_DEBS; swss gitlink `5328b765`'s `fpmsyncd/routesync.cpp:2201` does use the stock spelling. `src/libnl3/patch/0003-Adding-support-for-RTA_NH_ID-attribute.patch` is a dead file with no consumer |
| flashrom was de-forked to a stock deb | **False.** `rules/flashrom.mk:10` is `SONIC_MAKE_DEBS += $(FLASHROM)`, a 0.9.7 source build, with 3 patches in `src/flashrom/patch/series`. **This PR's own `.gitignore:141 src/flashrom/flashrom-*/` proves the source build** |
| sedutil was de-forked | True (`rules/sedutil.mk:8`, `SONIC_ONLINE_DEBS`) |

`AGENTS.md` is the instruction file for subsequent agents and humans; a wrong statement there directly misleads the next change.

### 3.4 What the `AGENTS.md` Scope section forbids is exactly what this PR adds to it

`AGENTS.md:5-7` (carried over from the old file's `:3-8`) states plainly:

> limited to durable build, editing, and review practices; do not duplicate plans, **progress tracking**, design rationale, or migration reports here

Yet `:22-43` newly adds precisely that: "the migration is complete", "Platform enablement is limited to `vs` … and `broadcom`", "FIPS is unsupported", and the whole known-deviations block. These status assertions cannot be grepped out of the old file — they are introduced by this PR.

The two errors in §3.3 are exactly this kind of status content. Status written into a "durable rules" file inevitably rots; here it was wrong on arrival. **Deleting the whole known-deviations block fits the file's own rule better than correcting the bullets one by one.**

**Collapse this into one action**: delete the status block at `:22-43` (which also disposes of §3.3's two factual errors), then restore the gitlink diagnostic per §3.5. One deletion and one addition, and `AGENTS.md` holds nothing but durable rules.

### 3.5 `AGENTS.md` dropped one gitlink diagnostic [both versions compared line by line]

The rewrite is tighter overall, and it adds two good rules (sync by rebase rather than fast-forward, plus `scripts/submodule-ff-audit.sh`; `.gitmodules` must be `https` and edited in place). The real loss is a single sentence.

Base `:79-94` enumerated the three states a gitlink commit can be in — ① upstream commit with an upstream URL (canonical never modified that submodule); ② a Canonical commit already pushed to `canonical/<sub>:202605_resolute` (absent from `sonic-net/`, so the URL must name canonical); ③ a Canonical commit **not yet pushed** (present only in the local worktree, so no clone can initialize the submodule) — and it gave the diagnostic: **"The state is not determined by the URL alone."**

The new `:71-74` keeps *where to push* (non-upstream commits → canonical, never `sonic-net/`) but loses *how to tell which state you are in*. The difference is operational: a `sonic-net/` URL does not imply the gitlink is an upstream commit — both ② and ③ can sit behind an upstream URL, and ③ makes clones fail outright. This trap has already been hit once (see the submodule section of [four resolute defects and a full-state comparison with upstream](2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-en.md)).

**Action**: restore that one diagnostic sentence; the three-state enumeration can be omitted. This is the same move as §3.4 — the file should carry durable diagnostics like this one, not a status list that rots.

(Three guards unrelated to gitlinks were also dropped: the kernel-ABI protection, the instruction to consult the Bookworm→Noble migration in `feature_noble_build` when a migration question is uncertain, and "The English documents are the source of truth" plus five authoritative doc links. Whether to restore those can be decided independently.)

---

## 4. Cheap and worth doing

### 4.1 The per-package options gap at `slave.mk:889` — **upstream has it too; this PR is not to blame** [upstream checked]

> **Downgraded on re-check.** I originally wrote this up as "a landmine, and this PR moves it closer", asserting that "p4lang-pi's check is known to fail in this environment". After checking upstream and the build artifacts: the gap is **word-for-word identical** upstream, upstream's default is the same, and the p4lang-pi assertion had **no supporting evidence and is withdrawn**.

**The gap itself is real.** The two deb recipes differ in capability:

| Path | Our line | Upstream line | `DEB_BUILD_OPTIONS` passed |
|---|---|---|---|
| `SONIC_DPKG_DEBS` | `slave.mk:938/939` | `:932/933` | `"${DEB_BUILD_OPTIONS_GENERIC} ${$*_DEB_BUILD_OPTIONS}"` |
| `SONIC_MAKE_DEBS` | `slave.mk:889` | `:883` | `"${DEB_BUILD_OPTIONS_GENERIC}"` — **no per-package part** |

So the `$(PKG)_DEB_BUILD_OPTIONS = nocheck` idiom that `rules/swss.mk` uses is **silently ignored** on any of the 53 `SONIC_MAKE_DEBS` packages — no error, no effect. That silence is the main reason it is worth fixing.

**But upstream is in exactly the same position, and this PR did not cause it:**

- upstream `slave.mk:883` **also lacks** `${$*_DEB_BUILD_OPTIONS}`, identically to our `:889`
- upstream `rules/config:398` is also `BUILD_SKIP_TEST ?= n` — **upstream has no global `nocheck` blanket either**
- this PR's `slave.mk` change is only 3 lines (`bookworm trixie` → adding `resolute`, and the chassisd skip); it **does not touch `:889`**

In other words, upstream runs the checks of all 53 of its MAKE_DEBS packages with the same gap and the same default. This PR merely returns resolute to upstream's default.

**The withdrawn assertion.** I had claimed "p4lang-pi's check is known to fail in this environment" and built the landmine framing on it. In fact `target/debs/resolute/` contains **no** `p4lang*`, `dash-sai*` or `libpi*` at all — they have **never been built on resolute**, so there is no evidence of a failing check. Meanwhile on upstream trixie the `bookworm trixie` filter at `syncd-vs.mk:7` *does* match, so `DASH_SAI` (`rules/dash-sai.mk:13` — itself a `SONIC_MAKE_DEBS` package) and p4lang-pi have been in upstream's build graph with checks enabled all along, and upstream passes.

**The half that still stands**: the `bookworm trixie` filter at `syncd-vs.mk:7` is the same pattern this PR edits at `slave.mk:1102`. If someone later adds `resolute` there for consistency, the DASH_SAI family enters resolute's build graph — and if any of those packages' checks then fail on Ubuntu (as swss's did in §3.2), **no per-package escape hatch will be available**. That is "may bite later", not "is broken now".

**Action**: still worth adding the line, to remove the silent-ignore and match `:938/939` — one line, zero behavioural change today (no MAKE_DEBS package sets the variable). But **this is a pre-existing gap shared with upstream, so it belongs in the optional-improvement bucket rather than being a merge condition for this PR** — and fixing it upstream would be the better venue.

### 4.2 `.gitignore` coverage is incomplete [measured]

This PR adds `sonic-slave*/files/` at `.gitignore:59` to ignore apt configuration rendered at build time. But **the script that generates those files covers three image classes, and this rule covers one.**

The guard at `scripts/prepare_docker_buildinfo.sh:46`:

```sh
if [[ "$IMAGENAME" == sonic-slave-* ]] || [[ "$IMAGENAME" == docker-base-* ]] || [[ "$IMAGENAME" == docker-ptf ]]; then
    ...
    mkdir -p "${DOCKERFILE_PATH}/files/apt/apt.conf.d"
```

All three branches create `files/apt/apt.conf.d/` under their own `${DOCKERFILE_PATH}`. `sonic-slave*` is only one of them — `docker-base-*` and `docker-ptf` both live under `dockers/`, so neither matches `sonic-slave*/files/`.

Measured with `git check-ignore -v --no-index` against this PR's `.gitignore`:

| Path | Result |
|---|---|
| `sonic-slave-resolute/files/apt/apt.conf.d/apt-clean` | matches `.gitignore:59` ✓ |
| `dockers/docker-base-resolute/files/apt/apt.conf.d/apt-clean` | **NOT IGNORED** |
| `dockers/docker-ptf/files/apt/apt.conf.d/apt-clean` | **NOT IGNORED** |

**Consequence**: building either of those image classes leaves untracked files behind, dirtying `git status`; and anyone running `git add -A` commits rendered artifacts into the repository. That is exactly the problem this PR set out to fix — it just covers a third of it.

**Fix**: extend the rule to all three classes, e.g. add

```
dockers/docker-base-*/files/
dockers/docker-ptf/files/
```

**One detail to get right**: `docker-ptf-sai` is **not** affected. The script tests exact equality (`== docker-ptf`, not `docker-ptf*`), so `docker-ptf-sai` never reaches that branch and never gets the directory — the rule should therefore *not* use a `docker-ptf*` glob, which would mask unrelated things.

### 4.3 `src/sonic-bmpcfgd/.gitignore` should be created instead of adding root entries

The repository has **40** `src/<pkg>/.gitignore` files. Walking every `src/*` directory that has a `setup.py` confirms: **`src/sonic-bmpcfgd` is the only in-tree Python package in the whole repo without a `.gitignore`.** The template is `src/sonic-py-common/.gitignore` (`*.egg-info/`, `build/`, `dist/`, `.eggs/`, …).

```diff
 # remove from the root .gitignore
-src/sonic-bmpcfgd/build/
-src/sonic-bmpcfgd/*.egg-info

 # create src/sonic-bmpcfgd/.gitignore, mirroring src/sonic-py-common/.gitignore
+*.egg-info/
+build/
+dist/
```

The other four named directories (`src/flashrom/flashrom-*/`, `src/libyang3-py3/libyang-python/`, `src/rdb-cli/librdb/`, `src/sonic-eventd/eventdb`) can stay in the root file — they are extraction residue from pulled sources, a different class from in-package build output.

> I got this one wrong in the first pass; the reasoning and correction are in §8.

### 4.4 `src/sonic-eventd/Makefile:114`'s `clean` omits `$(EVENTDB_TARGET)`

That line lists `EVENTD_TARGET`, `OBJS`, `EVENTD_TOOL`, `TOOL_OBJS`, `RSYSLOG-PLUGIN_*`, `EVENTD_TEST`, `TEST_OBJS`, `EVENTDB_TEST`, `EVENTDB_TEST_OBJS`, `RSYSLOG-PLUGIN_TEST` and `C_DEPS` — but **not `EVENTDB_TARGET`** (defined at `:11` as `eventdb`, linked at `:50`). `dpkg-buildpackage -tc` runs clean, so adding one variable removes the residue. Upstream `sonic-net/202605` has the same omission.

**This is the correct fix rather than a `.gitignore` entry**, which merely hides an uncleaned binary.

---

## 5. Build cache (medium-low, conditional) [three-way]

`BUILD_SKIP_TEST` participates in no cache key:

- `Makefile.cache:110`'s `SONIC_COMMON_FILES_LIST` is only `.platform rules/functions Makefile.cache` — **`rules/config` is not in it**
- `Makefile.cache:112`'s `SONIC_COMMON_FLAGS_LIST` is `RECIPE_VER / PLATFORM / ARCH / BLDENV / MIRROR_URLS / MIRROR_SECURITY_URLS / DEBUGGING_ON / PROFILING_ON / ENABLE_SYNCD_RPC` — **`BUILD_SKIP_TEST` is not in it**

The full chain was traced: the cache filename is `<pkg>-<DEP_MOD_SHA>-<MOD_HASH>.tgz` (`:280`/`:329`) ← `MOD_HASH` hashes `.flags` + `.dep.sha` + `.smdep.smsha` (`:205-211`) ← `_DEP_FLAGS := $(SONIC_COMMON_FLAGS_LIST)` (`:456`) written into `<pkg>.flags` (`:466`, `:553-554`). The on-disk artifact confirms it:

```console
$ cat target/python-wheels/resolute/sonic_chassisd-1.0-py3-none-any.whl.flags
1 broadcom amd64 resolute
```

`rules/sonic-utilities.dep` and `rules/swss.dep` corroborate the same conclusion line by line.

**Three qualifications, none of them purely negative:**

1. **The default path is unaffected.** `rules/config:156` is `SONIC_DPKG_CACHE_METHOD ?= none`, so this only bites when caching is explicitly enabled. (The untracked local `rules/config.user` happens to set `rwcache`, so the scenario is live in the local dev environment — see §9.)
2. **It is not a no-op.** The PR does invalidate three groups of packages, whose tests genuinely ran: swss (`rules/swss.dep:3`'s `DEP_FILES` includes `rules/swss.mk`), sonic-yang-models (its `.dep` has `SMDEP_FILES := $(addprefix $(SPATH)/,$(shell cd $(SPATH) && git ls-files))`, which covers the edited test file, and propagates through `DEP_MOD_SHA` to sonic-yang-mgmt, sonic-utilities and libswsscommon), and asyncsnmp (the gitlink changed). What is silently skipped is only packages whose inputs did not change: sonic-platform-common, sonic-host-services, sonic-py-common, sonic-config-engine, plus the deb check phases of libyang3 / lldpd / sonic-fib and the cli-plugin-tests of unchanged dockers.
3. **`Makefile.cache` is byte-identical to `sonic-net/202605`** (`git diff` produces no output). Upstream's own `SONIC_CACHE_RECIPE_VER_BASELINE := 348388b6…` already differs from upstream's `slave.mk` blob `7048fd87`, so the stale guard is a pre-existing condition shared with upstream and should not be charged to this PR.

**Revised recommendation: settle the goal first, then pick the mechanism.**

| Goal | Mechanism | Cost |
|---|---|---|
| Artifacts must have gone through tests | Add `BUILD_SKIP_TEST` to `SONIC_COMMON_FLAGS_LIST` | `=y` and `=n` builds no longer share a cache; deviates from the deliberate design in `Makefile.cache:71-80` |
| Only silence the guard | Per the file's own rule (`:90-92`), update the baseline to `a7de9659ce` and do **not** bump `RECIPE_VER` | none |

Either way, the PR's Verification section should state which suites genuinely ran and which may have come from cache.

---

## 6. Low priority / needs a note in the description

### 6.1 The resolute wheel backend silently moved from `setup.py bdist_wheel` to `python -m build -n` [measured]

This is a side effect of adding `resolute` to `$(filter bookworm trixie,$(BLDENV))` at `slave.mk:1102`, not just a test switch. Before the PR, resolute fell into the `else` branch and used `setup.py bdist_wheel` (the on-disk log `sonic_chassisd-*.whl.log:51` shows `running bdist_wheel`); after it, `slave.mk:1112`'s `python3 -m build -n` runs. In the slave image, `build 1.4.0`'s own help states the default is to build an sdist first and then the wheel from that sdist.

**But the risk measured as zero.** Rebuilding with `python3 -m build -n` inside the real slave image and diffing the wheel file lists:

| Package | Old (bdist_wheel) | New (-m build) | Missing | Extra |
|---|---|---|---|---|
| sonic-chassisd | 15 | 15 | 0 | 0 |
| sonic-config-engine | 15 | 15 | 0 | 0 |
| sonic-host-services | 33 | 33 | 0 | 0 |
| sonic-platform-common | 186 | 186 | 0 | 0 |
| sonic-utilities | 1049 | 1049 | 0 | 0 |

The sdist round-trip is lossless. **A sentence in the description acknowledging the side effect is all that is needed**; this is not a risk.

### 6.2 Version sensitivity in the yang negative tests — **not a defect; closed per maintainer decision** [both versions measured]

> **Closed by maintainer decision.** I originally filed this as a low-priority "brittle + diverges from upstream" item. The maintainer's position is explicit: **the resolute branch no longer maintains compatibility with upstream's libyang version.** On that basis neither of my two reasons holds (see "Why neither reason holds" below). The mechanism write-up is kept, because *why the error text changed* is useful reference material in its own right.

**The change** is two dictionary entries:

```diff
-            'DateTime': ['Invalid date-and-time'],
-            'IPv4': ['Failed to convert IPv4 address'],
+            'DateTime': ['Unsatisfied pattern', r'\d{4}-\d{2}-\d{2}T'],
+            'IPv4': ['Unsatisfied pattern', r'25[0-5])\.){3}'],
```

`test_yang_model.py` feeds deliberately invalid data to a YANG model and checks the error text against expectations; the matcher at `:234` is a plain-substring AND:

```python
elif (sum(1 for str in eStr if str not in s) == 0):
```

**Why the error text changed.** Feeding an invalid timestamp to `yanglint 3.13.6` gives:

```text
libyang err : Unsatisfied pattern - "not-a-date" does not conform to
"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[\+\-]\d{2}:\d{2})". (/demo:c/ts)
```

**libyang echoes the pattern itself into the error.** In 3.13.6 the type plugins validate the pattern *before* attempting conversion (`src/plugins_types/date_and_time.c:112` calls `lyplg_type_validate_patterns`), so the message changes from "failed to parse as date-and-time" to "doesn't match this pattern, and here it is". The old assertions are no longer substrings — so **this PR's change is both necessary and correct.**

The two versions side by side (measured against libyang's own source):

| | `lyplg_type_validate_patterns` | Error text |
|---|---|---|
| **v3.12.2** (what upstream SONiC pins) | `date_and_time.c` 0, `ipv4_address_no_zone.c` 0 | `ipv4_address_no_zone.c:97` = `"Failed to convert IPv4 address \"%s\"."` |
| **v3.13.6** (what `rules/libyang3.mk:13` pins) | `date_and_time.c:112` — 1 | `Unsatisfied pattern - ... does not conform to ...` |

Note that **3.12.2's error text is precisely the old assertion this PR removes** — the behavioural difference between the versions is established.

#### Why neither original reason holds

1. **"Diverges from upstream, so the shared file will fail there"** — not applicable. resolute does not maintain compatibility with upstream's libyang version, so failing on 3.12.2 is expected rather than defective; a deliberate two-line divergence is noise against this branch's total divergence.
2. **"The assertion couples to a third-party model's regex text, making 26 cases brittle"** — overstated. The DateTime fragment does come from libyang's bundled `models/ietf-yang-types@2013-07-15.yang:302` (all 144 files under our `yang-models/` are `sonic-*`, zero `ietf-*`), but `rules/libyang3.mk:13` pins **3.13.6 explicitly** via `SONIC_MAKE_DEBS`, so that text can only change when we deliberately bump libyang. That is a controlled event, and tests going red at that point is exactly what they are for — this is a version-sensitive assertion, not brittleness.

#### The only residue (not worth acting on)

`r'25[0-5])\.){3}'` has unbalanced parentheses and reads like a broken regex. It is only ever used as a plain substring, and the pattern echoed from `yang-models/sonic-types.yang:30` does contain that exact run, so it is functionally correct. Purely a readability nit; leave it.

### 6.3 The `src/sonic-snmpagent` submodule: the leak *is* introduced by this commit [commit diff checked]

**Direct answer: yes, we introduced it.** It is not an inherited upstream problem.

The gitlink itself is compliant: `.gitmodules` uses the canonical HTTPS URL, `955facf` is reachable only on `canonical/sonic-snmpagent:202605_resolute`, and `529cd5d..955facf` is a strict fast-forward (one commit).

That commit, `955facf fix(tests): use new_event_loop() for py3.14 compatibility`, is 2 lines across 2 files — the same mechanical substitution `get_event_loop()` → `new_event_loop()` in both:

| File | Before | Had a `close()` before? | State after |
|---|---|---|---|
| `tests/test_rfc1213.py` | `:71` `get_event_loop()` | **Yes**, `loop.close()` at `:73` | Correct — owns and closes |
| `tests/test_agent.py` | `:20` `get_event_loop()` | **No** (zero `close()` in the file) | **Leaks** |

**The semantic change is the source of the leak.** `get_event_loop()` returns the loop the interpreter created implicitly; the caller does not own it, and not closing it is conventional. `new_event_loop()` **transfers ownership to the caller** — not closing it leaks the loop and emits an unclosed-event-loop `ResourceWarning`. So:

- **before** the change, `test_agent.py` owned no loop, had nothing to close, and was fine
- **after** it, the file owns a fresh loop and never closes it → **a newly introduced resource leak**

This is an asymmetry *inside* the same two-line commit: `test_rfc1213.py` happened to already have the `close()` (its `:71-73` brackets the call site), so the substitution left it correct; `test_agent.py` did not, so the substitution broke it. The same mechanical edit was applied to both files, but only one had the prerequisite in place.

**Impact is limited but non-zero**: under `-W error` or pytest's `filterwarnings = error`, the `ResourceWarning` becomes a failure — and because GC timing is non-deterministic, **the failure is attributed to whichever test happens to be running**, which is painful to diagnose. Under the current configuration it is only a warning.

**Fix**: add an `event_loop.close()` (or a `try/finally`) to `test_agent.py`, matching the `test_rfc1213.py` in the same commit.

**Separately, the commit message is inaccurate.** The submodule commit says "Python 3.12 removed the implicit creation" — 3.12 only added a deprecation warning; **3.14 is where it raises**. The parent-repo commit message says 3.14 and is correct; the submodule one should be fixed.

This also disproves a worry stated in that commit message — that "code reached from `Agent` still calls `get_event_loop()`". Measured: `get_event_loop` has **zero** hits in the two production directories `ax_interface/` and `sonic_ax_impl/` (across the whole repo, `get_event_loop`/`new_event_loop` appear only in those two test files). So there is no functional impact; it is purely a resource leak.

### 6.4 Scope creep

`64aae6026d docs: update AGENTS.md` (+82 / −163, a full rewrite, with an empty commit body) is unrelated to "re-enable tests" and violates this PR's own `AGENTS.md` rule "Keep changes minimal and scoped". It should be split out.

### 6.5 Verification covers broadcom only

`BUILD_SKIP_TEST` is a global switch, while `AGENTS.md:31-33` declares `vs` an equally supported platform. The check phases on the vs side are unverified.

### 6.6 The force-rewrite statement

`AGENTS.md:16-18` carries over the claim that upstream date-named branches "can be force-rewritten with an identical tree, so confirm with `git merge-base` before assuming a bad rebase". This contradicts the closed investigation (see [the 2026-08-31 workflow forensics](2026-08-31-sonic-202605-workflow-forensics-en.md): upstream's Activity API shows 194 `pr_merge` + 1 `branch_creation` with `force_push` at 0; the divergence came from our own in-place `git filter-repo --force` on 2026-07-06). It is not introduced by this PR (the old file's `:171` already had it), but a full rewrite is the best opportunity to correct it.

### 6.7 Trivia

- `AGENTS.md:10-11`: the `## Branches` heading directly follows body text with no blank line
- `.gitignore:52`'s old entry `installer/x86_64/platforms/` no longer matches the `./installer/platforms/` path actually used by `build_image.sh:78-83` (same upstream; a pre-existing dead entry that could be replaced rather than kept alongside the new one)

---

## 7. Explicitly ruled out

The following were raised across the review passes and confirmed **not** to be problems. Recorded here so they are not re-litigated.

| Raised claim | Why it is ruled out |
|---|---|
| `nocheck` disables ten test binaries | `tests` left SUBDIRS in swss `296b9cc7` (confirmed both by the comment at `Makefile.am:1` and by that commit's diff); `tests/mock_tests` is gated off by `configure.ac:175`'s `AM_COND_IF([HAVE_SAI],[],[AC_CONFIG_FILES([tests/mock_tests/Makefile])])` — the deb build always has libsai. The only reachable target is `orchagent/Makefile.am:11`'s `p4orch/tests` (16 `*_test.cpp` files, 773 `TEST_F`/`TEST(` occurrences) |
| `nocheck` also hides compile breaks in test code | Disproven by the build log: `Making all in p4orch/tests` once, `-o p4orch_tests` linked twice, `make check` **zero** times. `p4orch_tests` is `noinst_PROGRAMS`, built by `dh_auto_build`; `nocheck` only skips `dh_auto_test` (`debian/rules` has no `override_dh_auto_test`) |
| The p4orch tests' own `DBConnector("APPL_DB", 0)` needs redis | `p4orch_test.cpp:200` resolves to `fake_dbconnector.cpp:38`, and that file is in `p4orch_tests_SOURCES` at `Makefile.am:62` — a call from the test's own translation unit to a definition in the same executable is bound at static link time, with no PLT and no redis. `ZmqServer("endpoint")` likewise (`fake_zmqserver.cpp` at `:70`). **The problem is only the library-internal call; see §3.2** |
| `tests/` and `mock_tests` need real redis | `tests/mock_tests/mock_dbconnector.cpp:18-40` fabricates a `redisContext` with `calloc` and `socket(AF_UNIX, SOCK_DGRAM, 0)`, never connecting; the three root `tests/` programs (`swssnet_ut`, `request_parser_ut`, `quoted_ut`) have zero `DBConnector` references. Why the sonic-swss standalone CI (`.azure-pipelines/build-template.yml:120-125`) installs redis is [unverified], but it is not for the deb check |
| `?= n` can still be overridden from the command line or environment, so it is a defect | That is what `?=` means, and it matches upstream `rules/config:398` word for word |
| "only enabled build environment" contradicts the `Makefile` | The sentence itself names `NOTRIXIE=1` and `NOBOOKWORM=1`, which is exactly what `Makefile:7-8`'s `?= 1` expresses; no contradiction |
| The cross-build path is affected | `Makefile.work:176-178` requires `CROSS_BLDENV` to be set explicitly; resolute enables only `vs` and `broadcom`, both amd64, so nobody takes that path, and this PR does not touch it |
| The gitlink is non-compliant | See §6.3 |
| The missing blank line in `AGENTS.md` trips markdownlint MD022 | There is no markdownlint config or workflow anywhere in the repo, so no linter reports it |
| Package-specific artifacts in the root `.gitignore` follow repo convention | **I got this wrong in the first pass**; see §4.3 and §8 |
| Other debs' check phases will break needing redis under `=n` | swss-common's `tests/Makefile.am:1` is `bin_PROGRAMS += tests/tests` with no `TESTS`; sonic-eventd's `debian/rules` is a bare `dh`, and its `Makefile:38` `test` target only links the test binaries without running them |

---

## 8. Self-corrections made during the review

Recorded because how these errors arose is more instructive than the conclusions themselves.

1. **Wrongly rejected "package artifacts belong in per-package `.gitignore`".** My basis was the presence of `src/sonic-frr/.sonic-frr-patch-*.sha1` and `src/**/debian/*` in the root file — but those are a cross-package glob and one special case, not the dominant pattern for this class of artifact. There are in fact 40 per-package `.gitignore` files, with `sonic-bmpcfgd` the only exception in the repo. **Lesson: to establish a "convention", count the samples; do not pick one or two examples.**
2. **Wrongly stated that `tests/` and `mock_tests` do need redis.** Both are pure mocks. That correction actually strengthens §3.2's root cause: what is broken is the general interposition mechanism.
3. **Reported a false "zero JUMP_SLOT" mid-check.** `readelf -r` truncates the type name to `R_X86_64_JUMP_SLO`. **Lesson: before grep-counting a tool's output, look at what the raw output actually says.**
4. **Got the p4orch suite size wrong.** I said "24 `*_test.cpp` files"; it is 16 files and 773 cases — 24 was the line count from `grep ^TEST(` mistaken for a file count.
5. **Waffled twice on §4.1's severity.** First "active bug" (having missed that `INCLUDE_VS_DASH_SAI ?= y` is on by default), then "latent" (having missed that `syncd-vs.mk:7` blocks it), finally settled as "landmine".
6. **Asserted then disproved the `python -m build` file-loss risk.** The mechanism is real, the impact measured as zero; the inference that "setuptools_scm's failing git file-finder is exactly the condition for dropping files" had no supporting evidence and was withdrawn. **Lesson: a valid mechanism is not a realised consequence — measure it when you can.**
7. **Overstated the chassisd item, and questioned it the wrong way.** Three reviewers independently converged on "the code contradicts the description" and I accepted that, without asking the one prior question: does upstream enable it? It does not (§3.1.3), so the code needs no change at all. Separately, I challenged the "2 multiprocessing failures" by grepping the chassisd directory for `multiprocessing` and finding nothing — the wrong place to look, since the multiprocessing comes from the shared `sonic_py_common/task_base.py`, not from the package under test; an actual run matched the description exactly. **Two lessons: (i) "multiple reviewers agree" is not evidence of correctness — three can miss the same prerequisite; (ii) before faulting behaviour a fork inherited from upstream, establish what upstream's state actually is.**

---

## 9. Operational notes

**A local `rules/config.user` silently overrides this PR's default.** The file is covered by `.gitignore:8` and is untracked, but it is `-include`d **after** `rules/config` at `Makefile.work:154` and `slave.mk:165`, and it sets `BUILD_SKIP_TEST = y` with a hard `=`. After the merge, `?= n` has no effect in such an environment, so "merged means tests run" does not hold automatically. The same file sets `SONIC_DPKG_CACHE_METHOD = rwcache`, which means the scenario described in §5 is live in the local dev environment.

**Specify the effort explicitly when invoking Codex.** `~/.codex/config.toml`'s `model_reasoning_effort = "low"` is inherited by `codex exec`. Pass 2 therefore ran at low effort and produced visibly thin output (3 findings, one of them an over-read). What was intended is `codex exec -m gpt-5.6-sol -c model_reasoning_effort="xhigh"`; the run log header prints `reasoning effort:` so this can be confirmed. Separately, the `humanize` plugin's `ask-codex.sh` wrapper passes `--full-auto`, which codex-cli 0.149.1 does not recognise and exits on (exit 2); bypass the wrapper and call `codex exec` directly.

---

## 10. Appendix

### 10.1 The minimal set to send to the author

If only three items are raised, choose these:

1. **§3.2** the `nocheck` rationale does not hold; the real cause is Ubuntu's `-Wl,-Bsymbolic-functions`, and an A/B experiment has proven the fix — **one super-repo line, net zero diff** — restoring 770 cases with no redis needed
2. **§3.3** the two inverted `AGENTS.md` statements about libnl3 and flashrom (three-way convergence, and the PR's own `.gitignore` proves the flashrom one)
3. **§4.1** add one line, `${$*_DEB_BUILD_OPTIONS}`, to `slave.mk:889` (one line of cost, defuses a landmine)

§3.1 (chassisd) needs only a wording fix in the description and can be folded into the same comment rather than raised separately.

### 10.2 Key verification commands

```sh
R=/home/sheldon-qi/sonic-buildimage-resolute

# §3.1.3 upstream builds the chassisd wheel only under trixie, so its skip covers every case
git -C $R grep -n SONIC_CHASSISD_PY3 sonic-net/202605 -- rules/ platform/ dockers/
git -C $R show sonic-net/202605:rules/docker-platform-monitor.mk | grep -nE 'TRIXIE_DOCKERS|PYTHON_WHEELS'

# §3.1.2 actually run the chassisd suite (needs root inside the container to install debs)
#   install libyang3 / libnl-* / libswsscommon / python3-swsscommon, then ldconfig;
#   pip install target/python-wheels/resolute/*.whl and ".[testing]"; then python3 -m pytest -q
#   expected: 2 failed, 216 passed

# §3.2 the vendor difference in link flags
grep -n Bsymbolic /usr/share/perl5/Dpkg/Vendor/Ubuntu.pm
grep -c Bsymbolic /usr/share/perl5/Dpkg/Vendor/Debian.pm     # expect 0

# §3.2 consequence: no library-own symbols among the JUMP_SLOT entries
dpkg-deb -x $R/target/debs/resolute/libswsscommon_1.0.0_amd64.deb /tmp/swsc
readelf -rW /tmp/swsc/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0 \
  | grep JUMP_SLO | grep -c 4swss                             # expect 0

# §3.2.1 controlled A/B: rebuild swss-common with the flag stripped, then swap the .so
#   under the same test binary. Insert before `include /usr/share/dpkg/default.mk`:
#       export DEB_LDFLAGS_MAINT_STRIP = -Wl,-Bsymbolic-functions
#   DEB_BUILD_OPTIONS=nocheck DEB_BUILD_PROFILES=nopython2 \
#     dpkg-buildpackage -rfakeroot -b -Pnopython2 -us -uc
#   readelf -rW common/.libs/libswsscommon.so.0.0.0 | grep JUMP_SLO | grep -c 4swss   # expect 351
#   LD_LIBRARY_PATH=<orig|fixed> ./orchagent/p4orch/tests/p4orch_tests
#   expect: orig throws the redis exception and exits 134; fixed prints 770 tests PASSED, exits 0
#   equivalent super-repo route (debian/rules untouched; measured to give the same 351 slots):
#     DEB_LDFLAGS_MAINT_STRIP="-Wl,-Bsymbolic-functions" dpkg-buildpackage ...
#     i.e. $(LIBSWSSCOMMON)_BUILD_ENV = DEB_LDFLAGS_MAINT_STRIP=... in rules/swss-common.mk

# §5 the cache key on disk
cat $R/target/python-wheels/resolute/sonic_chassisd-1.0-py3-none-any.whl.flags

# §4.2 gitignore coverage
git -C $R show canonical/202605_resolute_enable_tests:.gitignore > /tmp/g
cd $R && git -c core.excludesFile=/tmp/g check-ignore -v --no-index \
  dockers/docker-base-resolute/files/apt/apt.conf.d/apt-clean

# §4.3 the per-package gitignore convention
git -C $R ls-files | grep -cE '^src/[^/]+/\.gitignore$'
for p in $(ls $R/src); do [ -f "$R/src/$p/setup.py" ] && \
  [ ! -f "$R/src/$p/.gitignore" ] && echo "missing: src/$p"; done

# §6.1 wheel content comparison (run python3 -m build -n in the slave image, then diff namelists)
```

### 10.3 Related documents

- [Porting SONiC 202605 to Ubuntu 26.04: final state and pitfalls](2026-08-24-resolute-port-final-state-and-pitfalls-en.md)
- [Four resolute defects found by auditing a live switch, and a full-state comparison with upstream](2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-en.md)
- [`202605` workflow determination and forensics on a false "history was rewritten" call](2026-08-31-sonic-202605-workflow-forensics-en.md) (cited in §6.6)
- [SONiC Resolute migration code review](resolute-migration-code-review-en.md)
