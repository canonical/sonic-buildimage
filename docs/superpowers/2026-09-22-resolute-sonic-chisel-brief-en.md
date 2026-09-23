# Chisel work for resolute SONiC: a brief

**Date**: 2026-09-22
**Audience**: anyone who needs the picture in two minutes. Full evidence, per-package lists and operational detail are in the [work blueprint](2026-09-21-resolute-sonic-chisel-blueprint-en.md)
**In one line**: slice the Ubuntu packages SONiC containers use. About 68 packages, batched by who needs them; authoring slices and merging them upstream are separate concerns and should not share a schedule.
**Premise**: chiselling is a direction already set above this team. This document plans how, not whether.

---

## Where it stands

**Already in progress.** jy5275 has opened 20 PRs against `canonical/chisel-releases` covering 15 packages. **Nineteen are open and none has merged**, the oldest after 53 days.

The fork exists too: [github.com/jy5275/chisel-releases](https://github.com/jy5275/chisel-releases), still being pushed to today. Recipes can consume slices from it without waiting for upstream.

---

## Size

The 30 containers use 475 debs, of which **416** are in the Ubuntu archive and therefore within chisel's reach. Upstream has already sliced about 64% (209 of the 328 that can reach a rock).

**That leaves roughly 68 for us to write.**

---

## Five epics

The first three are batched by who needs the package, which is also the order to work in: the lower layers first, so the ones above have something to use.

| # | Epic | Scope | Person-weeks |
|--:|---|---|--:|
| 1 | **core** | The 14 packages the four core rocks depend on (database, eventd, mgmt-framework, router-advertiser) | 2 |
| 2 | **common** | The 22 packages the two common layers depend on (docker-config-engine, docker-swss-layer), needed by every leaf container | 2 |
| 3 | **leaf** | The remaining ~32 packages the other leaf containers depend on | 2 |
| 4 | **Adjust recipes** | Make rockcraft consume chisel-release instead of the Ubuntu archive; create the Linux users the rocks need | 1 |
| 5 | **Upstream** | Merge our PRs into upstream. Until they land, recipes consume our own fork so upstream review does not block us | 1 |

### Why this order

- **core first**, because those four rocks are already migrated, so their `install-unchiselled-packages` is a measured requirement rather than an estimate. Completing it validates one whole rock end to end.
- **common second**, because it hits every leaf container. Leave it incomplete and every container afterwards stalls on the same set of packages.
- **leaf last**: the largest group, but each package affects only its own container, so the work parallelises or splits freely.

### Three scheduling notes

**Dependencies set the order within a batch.** Chisel resolves `essential:`, so a dependency must merge before whatever needs it. Typically: `rsyslog` waits on `libestr0` and `libfastjson4`, and `rsyslog-relp` waits on `librelp0`. Ordering by name will trip over this.

**Epics 1 and 2 overlap by about four packages** (`libpython3.14`, `python3-yaml`, `python3-redis` and `python3-cffi-backend` sit in the common layer and are also used directly by the four core rocks). Whichever epic does one first owns it; do not count the effort twice.

**Epic 5's duration is not ours to set.** `ubuntu-26.04` merges 1.9 PRs a week against a backlog of 39. The one person-week is our own effort, not the calendar time upstream needs to merge.

---

## Keep these two apart

**Authoring slices** (epics 1 to 3) has no external dependency. An official skill covers the whole workflow, an AI can run it autonomously, and the order of magnitude is **weeks**.

**Merging upstream** (epic 5) is set by upstream review throughput, runs in **months**, and **blocks no delivery** — epic 4 points the recipes at our fork, so rocks build regardless.

Putting the two on one schedule produces the false conclusion that this takes the better part of a year.

---

## Still to decide

**How to get upstream moving.** Nineteen PRs with nothing merged says submitting more will not help. This can wait until epic 5, but it needs an answer by then: push the existing ones through, negotiate a review arrangement, or accept that some packages stay in the fork. Measured, established contributors see one sixth the merge latency of occasional ones, so the first few PRs should be small and clean.

**Explicitly out of this roadmap item**: the 53 self-built and 6 third-party packages that chisel cannot touch. Whether they move to a PPA or a superdistro is tracked elsewhere.
