# Chisel work for resolute SONiC: a brief

**Date**: 2026-09-22
**Audience**: anyone who needs the picture in two minutes. Full evidence, per-package lists and operational detail are in the [work blueprint](2026-09-21-resolute-sonic-chisel-blueprint-en.md)
**In one line**: slice the Ubuntu packages SONiC containers use so the rock migration can land. Sixty-six slice definitions to write, which takes weeks; merging them upstream takes months; the two run in parallel.

---

## Where it stands

**This is already under way, and it is stalled.** jy5275 has opened 20 PRs against `canonical/chisel-releases` covering 15 packages. **Nineteen are open and none has merged**, the oldest after 53 days.

Every one of those packages falls inside our backlog with no divergence, which independently confirms that the backlog's criterion is right.

---

## Size

| | |
|---|---|
| debs used across the 30 containers | 475 |
| within chisel's reach | **416** (the rest are 53 self-built and 6 third-party, which chisel cannot fetch) |
| already sliced upstream | 209 of 328, about **64%**. The heaviest base-layer packages are all done |
| **for us to write** | **66** |

Of those 66, **10 are blocking the four already-migrated containers** and are the urgent ones. The other 54 are an **upper bound** derived from Docker images rather than a commitment, and will shrink once the recipes exist.

---

## Two tasks, fully parallel

### Task one: author 66 SDFs in the fork

- **Deliverable**: 66 slice definitions plus tests, on our chisel-releases fork
- **Bottleneck**: none external. An official skill covers the whole workflow and **an AI can run it autonomously**. Order of magnitude: **weeks**
- **What it blocks**: rockification. This is the critical path for delivery
- **What is missing now**: `chisel` and `spread` are not installed on this machine

### Task two: push the SDFs upstream

- **Deliverable**: merged into `canonical/chisel-releases`
- **Bottleneck**: upstream review throughput, which **we do not control**. `ubuntu-26.04` merges 1.9 PRs a week and already has 39 open
- **How long**: **11 to 32 weeks** for the first 22, and 35 to 55 for all 66. The range is that wide because it depends on how much reviewer attention we obtain
- **What it blocks**: **nothing in rock delivery**. It decides how long we carry the fork

**The key point: rock delivery does not wait for upstream merges.** A recipe can consume a slice from our fork first and switch to the standard reference after it lands. Treating the two as one piece of work produces the false conclusion that this takes eight months.

---

## Three things that need a decision

**One, who owns the fork.** This is the largest risk today. A fork is not free: it means tracking upstream renames, following security updates, testing across architectures, rebasing continuously, handling collisions and eventually migrating everything back. It needs an owner, a pinned revision, CI and an update SLA, **none of which exist**. The moment task one delivers, the fork becomes a production dependency.

**Two, what happens to the 59 packages chisel cannot touch.** Fifty-three self-built plus six third-party, twelve percent of the total. Moving them to a PPA, staging them whole, or leaving them out is a product decision, but **somebody has to make it** or "chisel everything" is unreachable.

**Three, how to get upstream moving.** Nineteen PRs with nothing merged says that submitting more will not help. Three directions that might: push the existing ones to completion first, negotiate a review arrangement, or accept that some packages stay in the fork indefinitely. Measured, established contributors see one sixth the merge latency of occasional ones, so the first few PRs need to be small and clean.

---

## Suggested next steps

1. **Install `chisel` and `spread`** so task one can start.
2. **Ask why #1104 has been open 53 days** — worth more than opening another 51 PRs.
3. **Assign an owner and a budget to the fork** before task one delivers.
4. Check whether anyone upstream is already slicing each of the remaining 51 packages; one PR has already been closed as a collision.
