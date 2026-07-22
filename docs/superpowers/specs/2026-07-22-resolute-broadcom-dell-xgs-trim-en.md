# Design: trim resolute Broadcom platform to dell / XGS-only

**Branch:** `202605_resolute_doc` (this document)
**Build repo:** `/home/sheldon-qi/sonic-buildimage-resolute` (`202605_resolute_sheldon` branch) + worktree `sonic-buildimage-resolute-reorg` (formalization stack `202605_resolute_pr01..pr08`)
**Date:** 2026-07-22
**Status:** design confirmed, pending implementation

---

## 1. Context and goal

During formalization review, the reviewer asked that the resolute delta be kept
focused. The current Broadcom PR (`pr08` in the stack) carries the **entire**
Broadcom platform: XGS kmod + SAI, the DNX/Jericho variant, the legacy-Tomahawk
variant, saiserver, and **18 vendor** kmod patch series.

**Decision: narrow the resolute Broadcom deliverable to the only platform family
Canonical validates on Ubuntu 26.04 — dell, which is entirely XGS** (TD2/TD3/TD4,
TH/TH2/TH3/TH4/TH5).

Consequently:
- **DNX/Jericho + legacy-Tomahawk** are other ASIC families the unified image
  `sonic-broadcom.bin` happens to bundle; **no dell platform uses them at
  runtime** and they are **unvalidated** on 26.04 → remove.
- The 17 non-dell vendor kmod patches were added **speculatively** during the
  Linux-7.0 adaptation sweep (10 of those vendors are already commented out in
  `rules.mk`, so their patches never applied) → remove.

**Result:** `pr08` shrinks from 19 commits to 2; the resolute Broadcom delta
becomes pure XGS/dell.

---

## 2. Established facts (verified before implementation)

These facts fix the boundary and the mechanics of the trim:

1. **`rules.mk`, `sai-modules.mk`, `one-image.mk`, `one-aboot.mk`, `sai-dnx.mk`,
   `sai-legacy-th.mk` are all byte-identical to `sonic-net/202605`** — resolute
   never touched them; the commented `#include`s (disabled vendors) and the
   `# TODO(trixie)` line are inherited from the trixie migration. Resolute's real
   Broadcom delta lives only in the `*.patch/` overlay dirs + 5 modified files
   (4 docker `*.mk`, 3 `Dockerfile.j2`, `sswsyncd/debian/rules`, plus one trailing
   newline in `rules.mk`).

2. **`sai-modules.mk` builds all three kmods in one file**: XGS
   (`BRCM_OPENNSL_KERNEL`, lines 1–9), DNX (`BRCM_DNX_OPENNSL_KERNEL`, lines
   11–20), legacy-TH (`BRCM_LEGACY_TH_OPENNSL_KERNEL`, lines 22–31). The
   `saibcm-modules-dnx.patch/` and `saibcm-modules-legacy-th.patch/` dirs are
   consumed here, **not** by `sai-dnx.mk` / `sai-legacy-th.mk` (those only fetch
   the SAI **library** online debs).

3. **`one-image.mk:5` and `one-aboot.mk:5` set
   `DEPENDENT_MACHINE = broadcom-dnx broadcom-legacy-th`** — the trigger that
   makes the unified image also build the DNX/legacy-TH machine fsroots. Leaving
   it would drive a build of those variants (whose kmod sources we deleted) → fail.

4. **File counts**: non-dell vendor patch dirs = 81 files; dnx + legacy-th kmod
   patches = 24 files; dell = 4 files (kept).

5. The `canonical/202605_resolute` remote ref is deleted; the content still lives
   in the local `pr08` tip and the local backup `202605_resolute` (`aa7fc4f76d`),
   so the rebuild does not need that remote.

---

## 3. Target delta (vs `sonic-net/202605`, exactly this — nothing more)

### 3.1 Kept resolute changes
- `platform/broadcom/rules.mk` — edited to a dell/XGS-only include list (§4.1)
- `platform/broadcom/sai-modules.mk` — edited to XGS kmod only (§4.2)
- `platform/broadcom/one-image.mk` — edited `DEPENDENT_MACHINE` + `LAZY_BUILD_INSTALLS` (§4.3)
- `platform/broadcom/saibcm-modules.patch/**` (10 files, XGS kmod Linux-7.0 series)
- `platform/broadcom/sswsyncd/debian/rules` (1)
- `platform/broadcom/docker-syncd-brcm/Dockerfile.j2` (1)
- `platform/broadcom/sonic-platform-modules-dell.patch/**` (4)

### 3.2 Deleted (resolute-added)
- `platform/broadcom/saibcm-modules-dnx.patch/**`
- `platform/broadcom/saibcm-modules-legacy-th.patch/**`
- 17 non-dell vendor dirs: `sonic-platform-modules-{accton,alphanetworks,arista,cel,delta,ingrasys,inventec,juniper,micas,mitac,nexthop,nokia,quanta,ragile,ruijie,tencent,ufispace}.patch/**`

### 3.3 Reverted to upstream (resolute-modified, now unreferenced)
- `docker-pde.mk`, `docker-saiserver-brcm.mk`, `docker-syncd-brcm-dnx.mk`, `docker-syncd-brcm-legacy-th.mk`
- `docker-syncd-brcm-dnx/Dockerfile.j2`, `docker-syncd-brcm-legacy-th/Dockerfile.j2`, `docker-saiserver-brcm/Dockerfile.j2`

---

## 4. The three `.mk` edits

### 4.1 `rules.mk` (comment style follows the file's existing `#include` idiom; one resolute rationale line above each group)

**Keep active:** `sai-modules.mk`, `sai-xgs.mk`, `sswsyncd.mk`,
`platform-modules-dell.mk`, `docker-syncd-brcm.mk`, `one-image.mk`,
`raw-image.mk`, `libsaithrift-dev.mk`, and the `INCLUDE_PDE` / `INCLUDE_GBSYNCD`
guarded blocks (left as-is; their files revert to upstream per §3.3).

**Comment out:**
- `sai-dnx.mk`, `sai-legacy-th.mk` (DNX / legacy-TH ASIC families)
- the 8 currently-active non-dell vendors: `nokia, arista, nexthop, accton, cel, supermicro, ufispace, micas`
- `docker-syncd-brcm-rpc.mk`, `docker-saiserver-brcm.mk`,
  `docker-syncd-brcm-legacy-th.mk`, `docker-syncd-brcm-legacy-th-rpc.mk`,
  `docker-syncd-brcm-dnx.mk`, `docker-syncd-brcm-dnx-rpc.mk`, `one-aboot.mk`
  (`one-aboot` is the Arista Aboot image format — not needed for dell, and it
  itself re-pulls the dropped machines via `DEPENDENT_MACHINE`, so it must go)
- drop `$(SONIC_ONE_ABOOT_IMAGE)` from the `SONIC_ALL +=` line

> Note: `rpc` / `saiserver` / `pde` are test/dev containers a dell production
> image does not need; this is consistent with the confirmed "XGS-only closure".

### 4.2 `sai-modules.mk`
Delete the `BRCM_DNX_OPENNSL_KERNEL` (11–20) and `BRCM_LEGACY_TH_OPENNSL_KERNEL`
(22–31) blocks; keep the XGS block (1–9) with a one-line resolute note above it.

### 4.3 `one-image.mk`
- Line 5: empty the `DEPENDENT_MACHINE` value + resolute comment noting XGS-only.
- Line 148: `LAZY_BUILD_INSTALLS = $(BRCM_OPENNSL_KERNEL)` (drop `$(BRCM_DNX_OPENNSL_KERNEL)`).
- Leave the large `LAZY_INSTALLS` vendor list **untouched** — non-included vendor
  vars expand to empty and no-op; editing it would add 100+ diff lines for zero
  effect.

---

## 5. Two-target execution (user decision: trim commit on sheldon + sync-rewrite pr08)

The file operations in §3/§4 (delete + revert-to-upstream + 3 `.mk` edits) are
identical for both branches. Write the 3 edited `.mk` once, reuse.

### 5.1 Target A — `202605_resolute_sheldon` (main build tree, the real branch)
Add **one commit on top** (sheldon: 129 → 130), additive-style:
`build(broadcom): scope resolute broadcom to dell/XGS — drop DNX/legacy-TH + non-dell vendor kmods`
Body: dell platforms are all XGS; the DNX/Jericho + legacy-TH the unified image
bundles are unused and unvalidated on 26.04, so `DEPENDENT_MACHINE`, the two
`sai-modules.mk` kmod defs, and the 17 non-dell vendor overlays are removed.

### 5.2 Target B — `202605_resolute_pr08` (reorg worktree, review stack)
Rewrite pr08 = `202605_resolute_pr07` + 2 GPG-signed commits so its final tree
**equals the trimmed sheldon tree** (minus `rules/config.user`, which the stack
never carried):
1. `build(broadcom): saibcm-modules XGS Linux 7.0 kmod series + dell-only build wiring`
   — `rules.mk`, `sai-modules.mk`, `one-image.mk`, `saibcm-modules.patch`, `sswsyncd`, `docker-syncd-brcm`.
2. `build(broadcom): dell platform kmods Linux 7.0 API-drift patch series`
   — `sonic-platform-modules-dell.patch`.

Mechanics: branch fresh from `pr07`; `git checkout <old pr08> -- <kept patch
dirs>`; drop the 3 edited `.mk` from their upstream base; two commits. Old pr08
tip stays in reflog + local `202605_resolute` backup. **No push until reviewed.**

### 5.3 Consistency check
`git diff 202605_resolute_pr08 202605_resolute_sheldon` → only `rules/config.user`
(same invariant as before the trim).

---

## 6. Verification (in the main build tree, on trimmed sheldon — the build env lives there)

1. **Structural (fast, no real build):** `BLDENV=resolute make -f Makefile.work
   target/sonic-broadcom.bin SONIC_CONFIG_PRINT_DEPENDENCIES=y` — confirm the dep
   tree has **no** `broadcom-dnx` / `broadcom-legacy-th` / non-dell vendor targets.
2. **XGS kmod builds on Linux 7.0:** `target/debs/resolute/opennsl-modules_15.2.0.0.0.0.0.0_amd64.deb`.
3. **dell platform debs build** (dell.patch applies).
4. **Optional**: full `target/sonic-broadcom.bin` (long) as final confirmation.

pr08 shares the identical Broadcom subtree, so verifying sheldon covers both.

---

## 7. Risks and rollback

- **Rollback**: old pr08 tip is in reflog; local `202605_resolute` (`aa7fc4f76d`)
  is a full backup of the old state; the sheldon trim is an additive commit —
  `git reset --hard HEAD^` undoes it.
- **Primary risk**: over-trimming `rules.mk` (accidentally commenting an include
  `sonic-broadcom.bin` actually needs). The §6.1 dependency-tree print catches
  such a broken link **without** a real build.
- **Product semantics change**: the trimmed `sonic-broadcom.bin` no longer
  supports DNX/Jericho and legacy-TH ASICs. This is **intentional**
  (dell/XGS-only) and must be stated in the commit message and release notes.

---

## 8. Out of scope (YAGNI)

- Do not edit the `one-image.mk` `LAZY_INSTALLS` vendor list (empty-var no-op; pure diff churn).
- Do not touch `sai-xgs.mk` or the XGS `docker-syncd-brcm` content.
- Do not touch `AGENTS.md`, and do not touch formalization scripts beyond the
  `/tmp/g3` group lists (unless a later step needs to regenerate the stack from
  trimmed sheldon).
- No push, no PR — pending review.

---

## 9. Appendix: kernel root cause — why dell (and every vendor) needs kmod patches while Noble did not

(5-agent workflow investigation; adversarial verify verdict **confirmed**; high confidence.)

**Conclusion:** Noble (Linux 6.8) needed no patches purely because **6.8 predates the relevant kernel-API changes**. The dell driver source is **byte-identical** in the patched regions across both branches; Noble compiles it as-is with zero patches. resolute switches to Ubuntu linux-sonic **7.0** (mainline base ≥6.16/6.17), which crosses the change boundary, so the same source no longer compiles — hence the overlay. The difference is the **kernel**, not the source.

The dell overlay's 3 real drifts (all 2024–2025 mainline work, strictly newer than 6.8):
- `gpio_chip.set` callback **void → int** (`z9864f/modules/fpga_gpio.c`, ~v6.17; same as Ubuntu LP#2120461)
- sysfs **`bin_attribute` constification**: `.read` arg becomes `const` (`mc24lc64t.c` ×4: s5448f/z9332f/z9432f/z9664f, ~v6.16)
- **`irq_linear_revmap()` removed** → `irq_find_mapping()` (`z9332f/modules/cls-i2c-mux-pca954x.c`, ~v6.16)
- plus a `debian/control` kernel package-name retarget (`6.12.41+deb13` → `linux-sonic 7.0.0-1002`) — not an API change, driven by the kernel swap.

**Key subtlety: it is not "6.8 → 7.0" but "≤6.12 → 7.0".** The upstream sonic-net/202605 base uses the Debian trixie **6.12** kernel, and 6.12 is also < 6.16, so **even upstream dell needs none of these patches**. The overlay exists purely because Canonical swaps in the Ubuntu 7.0 kernel — it is not a resolute mistake, it is the inevitable consequence of a cross-major kernel API drift.

**Confounders ruled out (high confidence):**
- **Not** GCC/compiler: these are C kmods built by kernel kbuild against kernel headers, unrelated to the GCC15/C++17/boost userspace issues elsewhere; a newer GCC against 6.12 headers still builds. The compiler is the messenger; the kernel is the cause.
- **Not** a dell source version bump: package version is 1.1 on both; resolute in-tree dell == upstream 202605 (empty diff); the patched lines are byte-identical to Noble's.
- **Not** dpkg/kbuild tooling: no `debian/rules` and no Kbuild Makefile changes in the patch set.

**Honest caveats (do not change the verdict):** ① `z9864f`/`s5448f`/`z9664f` are new 202605 platforms absent from Noble, so the gpio case rests on API history rather than a same-file byte match; ② the exact merge window (6.16 vs 6.17) is medium-confidence, but ">6.8" is high-confidence; ③ resolute's mainline base "≥6.17" is inferred (the kernel is a prebuilt Launchpad deb; source not in-tree) — what is solid is that the build **succeeds** with the const `.read`, int `.set`, and absent `irq_linear_revmap`, which only holds on ≥6.16/6.17.

**Implication for this trim:** dell's 3 patches are **kernel-forced and required**, and dell is the only validated platform — so they are firm keepers, not speculative overlays. The other 17 vendor overlays are the **same kind** of kernel-forced fix but for **unvalidated platforms** — so "keep them?" reduces to "do we support/validate those platforms on 7.0?"
