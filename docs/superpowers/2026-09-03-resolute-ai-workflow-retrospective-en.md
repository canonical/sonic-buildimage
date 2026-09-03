# Working with AI on the resolute port: method, mechanisms, evidence

This document is about **how the work was done**, not **what was done**. What was done is covered in `2026-08-24-resolute-port-final-state-and-pitfalls-en.md` (final state and pitfalls), `resolute-modification-catalog-en.md` (change catalog), and the `specs/` and `plans/` directories. Technical root causes are not restated here; pointers are given where needed.

The reason to write it: this port was carried out end to end by one person working with AI — two months, 190 build commits, both platforms building from scratch, one in-service switch validated on real hardware, and the two PRs splitting mechanical renames from real changes (#7, #8) merged into `canonical/202605_resolute` on 2026-08-31. The team has more work of the same shape ahead (other distributions, other platforms, other upstream branches), so it is worth recording the concrete shape of the human/AI division of labour — which parts can be handed to the AI to run on its own, which parts a human has to gate, and what to say when gating them.

The primary evidence is the Claude Code session record. The extraction and classification script, its raw output, and a **serious caveat about the corpus itself** are all in `data/2026-09-03-prompt-corpus/`. Every quoted prompt has been normalized for tone — interjections, exclamations and emotional phrasing removed, meaning unchanged; paraphrases rather than verbatim quotes are marked *(paraphrase)*. All quotes were originally written in Chinese and are translated here.

---

## 1. The corpus, and why it is not clean

The caveat comes first, because it conditions every number that follows.

`cleanupPeriodDays` defaults to 30 days. On 2026-08-24 we discovered that session records from before 2026-07-24 had already been swept — precisely the main body of the migration — and raised the setting to 3650, too late. On 2026-09-03 the missing sessions were **reconstructed from the LLM API gateway's request log, keyed on timestamps. They were not restored from a backup.**

The consequences are directly verifiable from the files: 52 of the 75 top-level `*.jsonl` carry `"recovered": true`, and the 23 native files start only at 2026-07-25; **none of those 52 contains a single record with a non-null `toolUseResult`**, which is exactly the field step 1 of the pipeline filters on, so that step is a no-op for them; and fidelity cannot be checked against the originals, because the originals are gone.

So: any count covering 2026-07-02 → 2026-07-24 is an **estimate over a reconstructed corpus**, not an exact total. Regenerating `prompts-dedup.tsv` gives a per-row `recovered` column, so any claim can be re-checked against the 236 native inputs alone; that file is not committed, since it holds the verbatim prompts.

| Item | Value |
|---|---|
| Top-level session records | 75 (52 reconstructed / 23 native) |
| Subagent records | 56 files across 10 session subdirectories |
| Sidechain user records dropped by the structural filter | 5,820 |
| Human inputs: raw / (timestamp, text) dedup / text dedup | 1,014 / 969 / **747** |
| Of which from reconstructed / native files | 511 / 236 |
| Sessions carrying human input | 68 |
| Span | 2026-07-02 04:20 → 2026-09-03 06:27, 32 active days |
| Total characters | 48,140 |
| Mean / median / P90 | 64 / 28 / 126 characters |
| ≤10 / ≤30 / ≤100 characters | 143 (19%) / 401 (53%) / 647 (86%) |
| ≥300 characters | 14 (1%) |

Half the human inputs are under 30 characters and 86% under 100; the whole project's human-side input totals about 48,000 characters. That is not an efficiency metric. What it describes is the shape of human intervention in this workflow: nearly all of it is short, and only 14 inputs are long.

**First thing on a new project: raise the session-record retention period.** Commit history records what changed; *why* it changed exists only in the session record, and by default that is gone in 30 days.

---

## 2. Prerequisites

None of what follows ran on a bare Claude Code. Align these before copying the method, or the tool and skill names will simply not exist.

| Item | Value in this project | Where |
|---|---|---|
| Model and effort | `claude-opus-5[1m]`, effort `xhigh` | `~/.claude/settings.json` |
| Session-record retention | `cleanupPeriodDays: 3650` (default 30) | same |
| Plugins | `superpowers`, `humanize` | same |
| Skills used | `superpowers:brainstorming`, `subagent-driven-development`, `executing-plans`, `systematic-debugging`; `humanize:ask-codex` | from plugins |
| Self-written hooks | **none**. There is no `hooks` configuration in `settings.json` | — |
| Long-task adjudication | the built-in `/goal` command, which ships its own Stop hook judge | built in |
| Scheduled tasks | `CronCreate` / `CronDelete` tools, session-scoped | built in |
| Subagents | the `Agent` tool | built in |

Two repositories: the docs repository `~/sonic-buildimage` (branch `202605_resolute_doc`, upstream plus `docs/` and nothing else) and the build repository `~/sonic-buildimage-resolute` (a personal working branch, no `docs/` at all). The benefits and the cost of this layout are in 6.1.

---

## 3. Three mechanisms for letting the AI run on its own

A full SONiC build takes hours, failure points are scattered across a thousand-odd packages, and no human can watch the whole thing.

### 3.1 `/goal`: hand over the acceptance condition, not the steps

The method is to state an externally verifiable end state and let the AI loop on its own — build, fail, diagnose, fix, commit, clean, retry — until the condition holds. Adjudication is done by the Stop hook judge that `/goal` ships with; **you do not configure a hook for this.** This project has no `hooks` configuration at all.

The judge actually attached nine times. This table was extracted from the `A session-scoped Stop hook is now active with condition: …` confirmation message in the record, which is the hard evidence that a judge was live:

| Time | Condition |
|---|---|
| 07-04 15:52 | build successfully on a host using ubuntu as the vs target, and boot far enough to read os-release |
| 07-13 07:01 | after sonic kvm boots it shows ubuntu 26.04 and a 7.0 kernel; the docker containers are all running normally |
| 07-20 06:00 | after writing the plan, follow it and dispatch subagents until the sonic bin is built |
| 07-20 12:51 | build a complete sonic-broadcom.bin |
| 07-21 15:43 | build both the sonic vs and sonic broadcom bins once, successfully |
| 07-23 14:12 | finish the current de-fork |
| 07-23 20:02 | vs and broadcom both build successfully on the \<personal\> branch |
| 07-24 15:08 | finish the plan |
| 07-27 14:10 | clean builds of vs and broadcom succeed, and broadcom is deployed to dut02 |

There is one hard requirement on how the condition is written: **the end state must be an external fact that cannot be talked around.** "after sonic kvm boots it shows ubuntu 26.04 and a 7.0 kernel; the docker containers are all running normally" is three independently checkable facts. "The build succeeded" can be loosely read as "the main artifact appeared".

The table also shows that we did not consistently hold to this. "Finish the plan" and "finish the current de-fork" are precisely the conditions that need the AI's own account to adjudicate; they are not external facts, and those two verdicts are noticeably less trustworthy than the others. The rule is right; compliance leaked.

The second requirement concerns what the verdict rests on. The judge's prompt contains this:

```
Based on the conversation transcript above, has the following stopping condition
been satisfied? Answer based on transcript evidence only.
```

That last clause is the barrier against the AI declaring its own success. It is built-in behaviour, so you do not write it — but you need to know it is there, because the next pitfall comes from bypassing it.

**A `/goal` sent as text mid-turn may not attach a judge at all.** Five `/goal` invocations in the record were sent while the AI was already working, persisted as `The user sent a new message while you were working: /goal …`. Two of them (07-20 06:00 and 07-23 14:12) also registered as commands and did attach a judge. **The other three — the 07-06 17:23 os-release one, the 07-13 13:45 "bring up the version with neighbours and run the whole T0 set", and the 07-23 00:41 "follow the approach in clean-rebuild-design" — attached no judge whatsoever**; the AI simply read them as ordinary instructions. Do not confuse the 07-06 one with the 07-04 15:52 row in the table above: that was a genuine activation, also on an os-release condition, but a separate one. These three look identical to the successful ones from the outside, and a human will not notice the difference. To confirm a judge attached, go find that `Stop hook is now active` confirmation in the record.

The accompanying constraints matter just as much, or the loop leaves the repository dirty:

```
If you hit problems and need to fix bugs, committing is allowed but pushing is not.
Keep going until it works. Also, no commits for the add-host part that uses the
local-image environment.

Agreed. But if you hit an error while building vs and a change is genuinely required,
you may make it — after which you must commit, and must run a full clean before
rebuilding.
```

"Committing is allowed but pushing is not" is what makes this mechanism safe to enable: the AI has full autonomous repair authority, but the output stops locally and a human reviews it in one pass. "Must commit, must fully clean before retrying" guarantees every iteration starts from a clean reproducible tree, so you never get a false success that depended on half-edited state or leftover artifacts.

On output: the 07-13 kernel-migration round fixed three real bugs, but only one of them is the loop's doing. The stale `LINUX_KBUILD` reference in `slave.mk` (05:54) and the missing `_CACHE_MODE` in `linux-kernel.dep` (06:20) were both fixed **before** that day's 07:01 `/goal`. The hardcoded old-ABI kernel path in the grub.cfg written by `installer/default_platform.conf` (07:41) is the loop's product — and it is exactly the valuable one, because it only surfaces if you actually boot, and the end state had been set at "os-release readable after boot" rather than "the bin exists".

### 3.2 Scheduled babysitting: turn "watching progress" into a repeatable diagnostic checklist

Long builds hang. A network wobble leaves a `curl` stuck inside a container, the log stops advancing, but the make process is still alive. A human cannot tell "running" from "stuck", so this was set up with `CronCreate`. It was used twice, with the expressions `7,17,27,37,47,57 * * * *` (07-20, the broadcom round) and `3-59/10 * * * *` (07-21, both platforms), and removed afterwards with `CronDelete`. These tasks are **session-scoped and die with the session**; nothing is written to disk.

The 07-21 prompt:

```
Ten-minute build check (goal: successfully build the sonic-vs and sonic-broadcom bins).
Check the current build state:
1) are the vs/broadcom make processes alive, and when was the log last written
   (to judge whether it has hung);
2) is there a stuck curl / network download inside the container
   (docker top, look at curl etimes);
3) has target/sonic-vs.img.gz or target/sonic-broadcom.bin been produced;
4) are there new FAIL LOGs.
If it has hung (log static for a long time plus curl stuck for a long time), handle it
per systematic-debugging (e.g. kill the stuck curl so it retries, or prefetch the deb).
If the build is progressing normally, report one line and keep waiting.
Delete this cron once the goal is met (both bins built).
```

Four design points:

- **Give the concrete command for judging a hang** (`docker top`, look at `curl`'s `etimes`) rather than leaving the AI to invent a criterion — it will read the log and conclude "looks like it is running".
- **One line only when things are normal.** Otherwise a screenful of status every 10 minutes buries the one anomaly that matters.
- **State the intervention authority explicitly** (kill the stuck curl, prefetch the deb), so "notice the problem" and "be allowed to act" arrive together.
- **Self-delete on success.** Otherwise the cron outlives the goal.

The earlier 07-20 broadcom cron went further and wrote the current progress snapshot into the prompt body itself:

```
4) If make is gone and the bin does not exist, read the tail of
   /tmp/broadcom-m3-bin.log for the failure, diagnose the next class of API drift,
   produce a fix patch, commit, and restart the build (background nohup + watcher).
Current progress: M1 (3 kmods) + M2 (3 syncd containers) + three RFS squashfs are done;
now fixing vendor kmods one by one for Linux 7.0 API drift
(already fixed spi/gpio/hrtimer/control/bin_attr/irq/i2c-probe/ioremap/
MODULE_IMPORT_NS/EXTRA_CFLAGS/Maintainer/GPIOF/device_find_child).
```

State goes into the prompt rather than relying on context because a scheduled task may fire into a context that has already been compacted. **Any task that outlives context compaction has to carry its state explicitly.**

Manual polling stayed as a backstop throughout — 9 distinct phrasings of "how is it going" after dedup, roughly two dozen occurrences. Mechanisms fail, and human spot checks should not stop.

### 3.3 Subagents and multi-agent orchestration

The criterion for dispatching a subagent with the `Agent` tool is clean:

```
grub2 and socat can run in parallel. Use subagents.
Spin up a subagent to try 1.83.
Have a subagent do it.
```

Two situations warrant one: **mutually independent parallel tasks** (grub2 and socat are unrelated packages), and **exploratory trials** (try boost 1.83 first, unsure whether it will work). `ultracode` was enabled once during the broadcom push (07-20), using Workflow multi-agent orchestration for "fix a dozen classes of kernel API drift one by one" — work that fans out cleanly.

What does not suit a subagent is integrative work requiring continuous judgement: writing documentation, reorganizing commits, cross-package consistency audits. Those stay in the main session.

---

## 4. Process and document skeleton

### 4.1 Three stages: spec → plan → report

The artifacts are physically separated and their locations are fixed:

- `docs/superpowers/specs/<date>-<topic>-design-{zh,en}.md` — design. Option selection, global constraints, a file-by-file table of intervention points.
- `docs/superpowers/plans/<date>-<topic>-plan-{zh,en}.md` — implementation plan. Task breakdown, a Files list per task, `- [ ]` checkboxes, exit criteria.
- Top-level reports — final state, change catalog, code review, validation reports.

Two details are what make this skeleton work.

**Pin the skill contract at the top of the plan file.** 17 of the 21 plans carry this line:

```
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
```

The next session's AI opens the plan and picks up the right workflow automatically; nobody has to explain it again. The 4 without it are progress and wrap-up documents, not oversights.

**Hard gates between phases.** The migration design defined five phases — slave → host OS → container base → vs containers → assembly/boot — each with an explicit exit criterion (Phase 0's was "`make` parses, `BLDENV=resolute` is selected, no sources pulled yet"). This stops the AI from changing two hundred files in one go and leaving no way to localize a failure. Subsequent rounds (clean rebuild, broadcom, de-fork) reused the same shape.

As for "list options A/B/C with the reasons the rejected ones were rejected": only about 5 of the 16 specs actually do it. It is useful, but do not read it as established practice here — it is something to bring up to standard, not something already achieved.

### 4.2 Generate long documents section by section

The 20,000-odd lines of bilingual documentation were not produced in one shot:

```
Write one section at a time, keep going until both the Chinese and English versions
are done.
One section at a time.
Continue, a bit at a time. Do not emit too much at once.
```

Section-by-section generation with section-by-section confirmation avoids producing a large block and only then discovering the direction was wrong. Prose style also needs explicit management: "this version still reads a bit too AI"; "no bold headings, plain sections are enough"; "keep it concise, I am posting it to the company channel".

### 4.3 Bilingual, two files

Every spec and plan ships as two **independently complete** files, `*-zh.md` and `*-en.md`, with English as the source of truth and conversation in Chinese. No single file mixing both languages.

The rule took three corrections to stick: set on 07-03, then "bilingual means one document each in Chinese and English" (07-06), then "agreed, but bilingual means two files" (07-10), and it was broken once more on 07-13 in a sonic-mgmt spec. It is also still not universal — `plans/2026-07-24-resolute-ubuntu-source-switch-plan.md` remains a single file. So this is **a convention adopted for this migration's later documents**, not a pre-existing repository rule.

### 4.4 AGENTS.md: durable rules, and the lesson of one wrong rule

`AGENTS.md` at the root of the build repository (174 lines) holds durable rules for AI, not a README. Two of its design decisions are worth reusing:

- **Draw the boundary explicitly.** It opens by stating that project plans, progress tracking, design rationale and migration reports must not be duplicated there — durable rules only.
- **Anti-dogma.** "Do not infer the active build environment, package version, or platform support from this file; verify it in the checked-out branch and relevant build configuration."

But the same file also supplies a cautionary lesson worth recording. The last entry under Git Hygiene still says that upstream date-named branches can be force-rewritten, and that a compare showing thousands of changes plus an implausibly old merge-base "usually means a force-rewrite, not a local mistake". That rule's diagnosis is **wrong** — case three in 6.2 is closed: upstream never force-pushed, and the real cause was a `git filter-repo --force` we ran in place ourselves. Once a rule is written from a bad diagnosis it keeps operating, and nobody went back to fix it. Line 36 of the same file still carries "still WIP on July 13, 2026", the kind of expiring status information that contradicts its own stated boundary.

So: **writing your pitfalls back into AGENTS.md is right, but when a conclusion is overturned you have to return and correct it, or the wrong rule keeps steering the next AI.** That force-rewrite entry needs a correction commit.

Alongside it are 49 memory files under `~/.claude/projects/<project>/memory/` (one fact per file plus a `MEMORY.md` index). The division of labour: AGENTS.md holds **rules** (shared with the team, in the repository), memory holds **conclusions** (personal context, including hypotheses that turned out to be wrong).

Memory also served once as a migration vehicle: on 07-02 the host was rebuilt from a zfs root onto ext4 and the whole build environment had to be recreated. The approach was to have the AI first write the non-reproducible parts (`rules/config.user`, two host-side fixes) into memory, then restore from memory on the new host.

---

## 5. Where human input lands

Category counts over the 747 deduplicated inputs. Categories are mutually exclusive, first match wins, and the unclassified remainder is reported:

| Category | Count | Share |
|---|---|---|
| Investigate / verify / audit / dig deeper | 87 | 11% |
| Challenge and overrule | 53 | 7% |
| push / commit / merge | 44 | 5% |
| Orchestration (subagent / goal / cron / jsonl / parallel) | 33 | 4% |
| Authorization boundaries | 32 | 4% |
| Minimal diff / revert gratuitous changes | 25 | 3% |
| Colleague / reviewer / review | 18 | 2% |
| Patch style (sed / awk / patch files) | 17 | 2% |
| From-scratch rebuild / clean | 13 | 1% |
| Document form and prose style | 13 | 1% |
| Bare advancement (continue / right / agreed) | 9 phrasings | — |
| Option letters | 8 | 1% |
| **Unclassified** | **395** | **52%** |

Two things have to be said, or this table gets over-used. First, **half of it is unclassified** — one-off substantive technical instruction that forms no reusable pattern, and that is the bulk of the input on this project. Second, the 9 on the advancement row is the number of **distinct phrasings** (every "continue" collapses to one row after text dedup); counted by occurrence, advancement phrases plus option letters come to 131. Classification is by keyword regex: the magnitudes are sound, individual numbers should not be cited as exact.

### 5.1 Bare advancement

```
continue
right
agreed
C first, then A
B. You can follow what we did for libnl3 / bash.
Agreed. But finish all of A and verify it once before doing C.
Only track a and c, but you can follow the approach in b.
```

This is not laziness; it outsources the cost of description to the AI. `superpowers:brainstorming` lays the options out numbered first, and the human replies with a letter. "C first, then A" carries a complete sequencing decision in four words. The prerequisite is that the options are genuinely orthogonal — with vague options, a letter reply is a gamble.

### 5.2 Anchored overrules

53 of them. The shared feature is that **each one carries a concrete counterexample or a piece of domain common sense**, rather than a vague "look again":

```
By that account resolute's own bash and socat packages would not compile.
  That does not add up.                                                  (paraphrase)
There is no way ifupdown2 is not in ubuntu. I think the others you claim are not in
  Ubuntu are not very credible either.
bash does have patches — your investigation is off. As for redis, bpo9? Look at what
  redis actually runs on on the 202605 branch.
No. resolute was forked from trixie.
Upstream never had a soft mv, did it? Investigate that more carefully.
The docker-base-trixie / docker-config-engine-trixie / docker-swss-layer-trixie
  suffixes need renaming to resolute as well.                            (paraphrase)
Hold on. I am starting to suspect the earlier memory investigation was wrong.
Check whether you are looking at the wrong directory. It is ~/sonic-buildimage-resolute.
```

The first one deserves separate mention. The AI's conclusion at the time was that resolute's own bash and socat would not compile. That is logically impossible — a distribution's own packages compile on that distribution. **Overruling it required no code reading, only common sense.** This is the archetypal AI failure mode: coherent narration, rich detail, contrary to common sense.

The opener "hold on" appears 4 times, 3 of them stopping the AI mid-action to reinvestigate.

### 5.3 Human proposes the hypothesis, AI verifies it in isolation

The fakeroot episode is worth recording as a negative example. The human proposed a direction — glibc changed its syscall pattern so fakeroot cannot parse the payload — and the AI followed it. That hypothesis was **wrong**: the real cause was the host's AppArmor `gs` profile denying file creation in the build directory, and the memory's own words are "This was mis-attributed to fakeroot for multiple sessions". The human's hypothesis anchored the AI in the wrong direction for several sessions.

So the split is not "human proposes, AI follows" but **human proposes while requiring the AI to verify in isolation**. What the memory records as the effective method is the useful part: run the failing step alone without fakeroot, then read the kernel audit log. The first immediately proves fakeroot is not necessary; the second points straight at AppArmor.

### 5.4 Reviewability is a first-class goal

The work is destined for upstream, so "can a human read this diff" carries the same weight as "is the code correct". This thread produced the mech / real branches and the now-merged PR#7 / PR#8:

```
If we are opening a pile of PRs we will have a pile of branches, so let us stack them:
202605@orig -> 202605_resolute_pr01 -> 202605_resolute_pr02 -> ...
No pushing and no PRs. Let me look first.

After discussion we plan to split this into two stacked PRs. One is mechanical changes
(two commits: the current copy of trixie, and then all the pure s/trixie/resolute/g;
if a line also carries another change it goes into the real-changes PR); the other PR
is the real changes.

I think these can be merged into one PR — but in the original pr01 you need to go back
to the copy-first-then-modify pattern, otherwise it cannot be reviewed.

Audit it. Also, cases where one logical change got scattered across several PRs
because it was split by line.
Not file-level overlap — logical-level overlap.

Then look again at the ten PRs we are going to open. After talking it over with a
colleague, I want to put the broadcom ones last.
```

The core insight is that **mechanical transformation and real modification must be separated**. A change like `s/trixie/resolute/g` costs almost nothing to review no matter how many lines it spans; mix in a single line of real logic and the whole diff becomes unreviewable. Hence the forced split into two stacked PRs — the first "verbatim copy plus pure rename", the second "real changes".

The same reasoning drives the copy-first-then-modify commit pattern: when adding `sonic-slave-resolute/`, the first commit copies `sonic-slave-trixie/` verbatim and only the second changes content. Worth noting: that shape was **back-filled** during the 07-23 reorganization for PR#7 (a copy commit then a rename commit on the mech branch); the original working branch's first commit already carried changes. Which means a reviewable commit sequence can be reconstructed before review — it does not have to be maintained while developing.

"Logical-level overlap" was an audit finding: one semantic change, landing on different lines of different files, had been mechanically split across several PRs, leaving each PR incomplete on its own. No file-level overlap does not imply no logical-level overlap.

### 5.5 Style discipline: patch style and minimal diff

17 inputs concern patch style, 25 concern diff size, and both express the same value:

```
The reviewer raised a lot of points. Our changes (parent repo and submodules) contain
plenty of sed/awk calls instead of SONiC-style patch files. That is not good.

Existing upstream sed/awk is fine, but we must not add new ones.
Re-check the current sed/awk and patches: which ones can graduate to editing directly?

The bash diff is nowhere near minimal: newline formatting, optional line-number edits,
the patch generator at the end — all of that could stay as it was. At worst you get a
few more offsets.

Are you doing a lot of optional work? Are all those mv changes and changelog edits
really necessary?
For the -mv ones, we need to be sure not one of them is ours.
The comments are all too long.
```

"At worst you get a few more offsets" captures a **cost trade-off that runs opposite to the AI's default**. The AI prefers patches that apply with exact alignment (clean, but a large diff); for an upstream fork the right choice is to tolerate offset warnings (slightly untidy, but a small diff). The AI will not generate this preference on its own and it has to be re-injected — each time, it drifts back to "fix it up while I am here".

The rule this hardened into (now in memory and AGENTS.md): **submodules and pulled-in sources get a `.patch` overlay; in-tree sources are edited directly; no in-place sed/awk rewrites.**

### 5.6 Authorization granted per occasion

32 boundary statements, and no blanket opening of the gate:

```
Agreed, but no pushing to the remote at any point in this.
Commit only for now. Push once both vs and broadcom build.
No pushing and no PRs. Let me look first.
I just deleted the 202605_resolute you pushed to by mistake, so push it again from
  202605. Just this once, with my explicit consent.
Push one formal round, then align canonical's 202605_resolute to 202605. From now on
  202605_resolute is our production branch — no pushing to it.
Investigate whether sonic-buildimage-resolute could be ported to this device. Probing
  system and hardware state is allowed; destructive operations are forbidden.
Delete pr01-08; rock belongs to someone else, leave it alone.
```

Three reusable phrasings: **"X is allowed, Y is forbidden"**; **"just this once, with my explicit consent"** (exceptions leave a trace and do not constitute standing authorization — and it was in fact used three times, on 07-23, 07-28 and 08-17, so it does get reused and each time has to be said afresh); and **"commit only for now, push once the condition is met"** (irreversible actions deferred past verification).

Irreversible organizational operations went through the same discipline. Creating the forks, the branch naming scheme, GitHub team permissions and the external announcement text were all executed by the AI — but the naming scheme was fixed by a human first:

```
You can use gh to create the repos under canonical. Adjust the branch names:
for sonic-* repos, the branch is 202605_resolute{,_doc};
for other repos, sonic_202605_resolute.
```

### 5.7 The session record as a data source

This practice started on 07-22, not as an afterthought at the end:

```
Dig deeper; you can look at the claude jsonl history.
Look at why this was changed before … (a pddf function-signature diff pasted in) …
  the claude history or the original repo should have a clue.
Look at c44da5c8-….jsonl and continue its investigation.
Also include what was done in the session that crashed on context overflow — extract
  the meaningful parts.
The outline is right, but for the pitfall history I suggest you go through the claude
  jsonl and distil it again.
```

The second is the archetype: a pddf kernel-module function signature had been changed (`void` → `int`), nobody remembered why, so the AI was sent into the session record to find the decision context. Commit history records what changed; the session record is the only place that records why.

A session that crashed on context overflow does not mean the work was wasted either — the raw record is still there to distil. This retrospective is the largest application of that practice, and it is exactly how the corpus problem in §1 came to light.

---

## 6. Incidents and structural risks

Technical root causes are all in `2026-08-24-resolute-port-final-state-and-pitfalls-en.md`. Only the collaboration-level lessons are kept here.

### 6.1 Working-directory drift across two repositories — two real incidents

The AI's shell working directory gets silently reset to the primary working directory (the output shows `Shell cwd was reset to …`), and because the two repositories have similar relative path structures the command looks correct. Twice this had real consequences: on 07-23, after a session resume, a `make … reset` landed in the docs repository; on 08-19 a `git commit --amend` hit the docs repository and overwrote the commit message of `0ee46067d8` with unrelated text (the tree was unchanged; `reset --soft` restored it). A third, lighter instance of the same root cause was simply reading the wrong repository.

**The only reliable mitigation is an explicit `git -C <repo>` on every git write**, never relying on the working directory. See memory `two-repo-cwd-hazard`.

### 6.2 Three cases of coherent narration on insufficient evidence

- **fakeroot "payload not recognized"** was taken as the main cause of the bash build failure for several sessions. See 5.3.
- **show/plugins.** There are in fact **two distinct faults** here, and we briefly let one "real cause" swallow both. `show ip …` reporting "No such command" is a database that is not ready or a missing minigraph; the hyphen import warning from `show.plugins.*` is an upstream bug (`import_module` rejects hyphens). The actual **import failure** was a module-level `ConfigDBConnector()` at `dhcp-relay.py:83` hitting a database that was not ready, and the claim that the hyphen caused the failure was disproved three ways (synthetic module, wheel, actual rootfs layout). The lesson: map similar-looking symptoms to separate faults first, then talk about root causes.
- **"Upstream force-rewrote 202605."** The real cause was a `git filter-repo --force` we ran in place ourselves. The decisive evidence was the GitHub Activity API (194 pr_merge events, `force_push=0`), the local `.git/logs/HEAD`, and the argument that the fork point is exactly the parent of the first signed commit. The gharchive BigQuery query covered only 35 of the 194 advances (18%) and proved unreliable — it cannot carry the conclusion. Full account in `2026-08-31-sonic-202605-workflow-forensics-en.md`.

Shared lesson: **the more fluent and detailed the causal chain the AI offers, the more it needs an independent evidence source that does not depend on its narration.** And once it is overturned, go back and fix AGENTS.md (see 4.4).

### 6.3 Caches masking real bugs

A genuinely from-scratch rebuild (the fixes all landed on 07-21) exposed three real bugs that cache layers had been hiding; technical detail is in pitfalls 4.3. Two collaboration-level conclusions belong here.

First, **the acceptance bar has to be a full from-scratch rebuild, not "the incremental build passed"**. This project ended up running two rounds (08-23 and 08-27, vs plus broadcom); two was the judgement at the time, not a universal number. The wipe order matters: `fsroot*` is root-owned and needs `sudo rm` before `git clean`.

Second, **"it passed on retry" may be false**: `.flags` is an independent make target, so when a package already has an old artifact (an incremental or platform-switch build), retrying a failed package can be judged up-to-date and silently reuse it.

A note on citation discipline: of those three bugs, the `build_image.sh:51` one now reads as the fixed form (`sudo -E env …`), and the dash-engine fix has been superseded by upstream #28587. **When a retrospective cites a line number, say it was the state at the time** — otherwise a reader following the reference reaches the opposite conclusion.

### 6.4 False "already upstream" comments — caught by an external reviewer

The AI will write "fixed upstream" in a comment where the truth is "skipped". All four charges in PR#8 were verified and all four held — the relevant lldpd and flashrom comments did not stand up, and both were returned to source builds.

Worth emphasising: **these false comments were not caught by our own process. An external reviewer caught them.** Nothing in the human/AI loop was challenging the "already upstream" assertions the AI wrote down. So the countermeasure has to be an explicit step — a **periodic claims audit**: any comment asserting "already upstream", "no longer needed" or "equivalent to" gets checked individually. Recorded in memory `resolute-defork-upstreamed-claims-audit`.

### 6.5 Submodules not rebased along with the super-repository

Rebasing only the super-repository and leaving submodule branches alone makes the gitlink retain the old commit and silently discards upstream fixes (this is how the permanently-zero SAI counters happened). Technical detail in pitfalls 4.1.

The collaboration-level countermeasure is to turn the rule into a script: `scripts/submodule-ff-audit.sh` (in the build repository), run after every upstream sync. **Rules that can be scripted should not be left to human attention.**

---

## 7. Checklist for the next piece of work of this shape

In order of when it applies. Items marked *(specific)* are this project's particular values, not general rules.

Before starting:

1. Raise `cleanupPeriodDays` in `~/.claude/settings.json`. It is the only carrier of "why", the 30-day default will delete it, and a corpus reconstructed from gateway logs afterwards is lossy (see §1).
2. Align the prerequisites: model and effort, the plugins and skills you need, the built-in tool names (`/goal`, `CronCreate`, `Agent`). The method depends on these; confirm they exist in your environment (§2).
3. Write an `AGENTS.md` at the target repository root with durable rules only, stating that plans and progress are not duplicated there and that readers should not infer current state from the file but verify it in the branch. Also **establish a correction path**: when a conclusion is overturned, come back and fix it, or the wrong rule keeps operating.
4. Fix the locations and naming for the three document stages. Bilingual two-file output is a team convention *(specific)* — set it to whatever you actually need.
5. If more than two repositories are in play, mandate `git -C` from the very first command.

During the work:

6. Produce a spec per phase before a plan (task breakdown, Files list, checkboxes, exit criteria). Pin `REQUIRED SUB-SKILL` at the top of the plan. Listing options A/B/C with rejection reasons in the spec is what you should do; this project managed it about a third of the time.
7. For long-running work use `/goal` to hand over the condition rather than the steps. The condition must be an external fact that cannot be talked around (this project failed that twice). **Confirm the judge actually attached** — find the `Stop hook is now active` confirmation in the record; a `/goal` typed mid-turn may not attach one. Pair it with "commit allowed, push forbidden".
8. Attach scheduled babysitting to long builds with `CronCreate`: give the concrete hang-detection command, state the intervention authority, allow one line when normal, write the progress snapshot into the prompt body, and `CronDelete` on success. Note that session-scoped crons die with the session.
9. Use subagents only for independent parallel tasks and exploratory trials; keep integrative work in the main session.
10. Generate long documents section by section with confirmation between sections. Manage prose style explicitly.
11. Authorize with "X is allowed, Y is forbidden"; mark exceptions "just this once, with my explicit consent" (it will be reused — say it afresh each time); defer irreversible actions past verification.
12. When a conclusion violates domain common sense, overrule it directly and supply the specific counterexample — do not say "look again". When you propose a hypothesis, require isolated verification with it, so the hypothesis does not become an anchor.
13. Keep re-injecting the two value judgements "minimal diff" and "reviewability"; they do not sustain themselves. Separate mechanical transformation from real modification; a reviewable commit sequence can be reconstructed before review.

Before wrapping up:

14. Full from-scratch rebuild, both platforms. "The incremental build passed" is not accepted. Set the number of rounds by your own risk appetite (two here *(specific)*).
15. Audit every "already upstream / no longer needed / equivalent to" comment. On this project an external reviewer supplied this step, which is why it has to be made explicit.
16. Run the submodule fast-forward audit script (`scripts/submodule-ff-audit.sh` here *(specific)*; the general rule is "script the rules that can be scripted").
17. Write disproved hypotheses into memory — negative conclusions prevent repeated work.
18. When citing line numbers or file state, say it was the state at the time; later commits will invalidate them.
19. Have a human pass over privacy before publishing: internal IPs, IPv6 prefixes, usernames, credentials. The AI will not realize on its own that internal topology is sensitive.

---

## Appendix A: the extraction pipeline

The script, its raw output and the full methodology are in `data/2026-09-03-prompt-corpus/` (`mine-prompts.py`, `corpus-stats.txt`, `README.md`; `prompts-dedup.tsv` holds the verbatim prompts and is not committed — regenerate it locally). Running `./mine-prompts.py` regenerates every number.

Three steps, each of which was got wrong first.

**One: structural filter.** Keep `type=="user"` where `isSidechain` is not true, `isMeta` is not true, and `toolUseResult` is null. Subagent conversations are also persisted with role user (5,820 of them at top level), so are tool results, and so are harness injections such as skill bodies and agent listings — that last class is what `isMeta` catches. **Omitting the `isMeta` check makes a 240 KB skill manual count as one human input**, which destroys the length statistics.

**Two: text filter, distinguishing "drop" from "unwrap".** Most non-human text injected in the user role should be dropped (`<system-reminder>`, hook feedback, task notifications, the `/goal` judge prompt, relayed agent messages, and so on). But four forms *wrap* real input rather than replace it, and dropping the record would discard the human's own words with it:

- `The user sent a new message while you were working:\n<real input>`
- `<ide_selection>` / `<ide_opened_file>` blocks
- `The user selected the lines N to M from <path>` preambles
- a trailing `CRITICAL: Respond with TEXT ONLY …` hook suffix

Slash commands are kept by extracting `<command-args>`, which is the human's text; the `<command-name>` wrapper is discarded.

**Three: two dedup keys, because neither alone is right.** Resuming a session re-persists earlier messages. Deduplicating on `(timestamp, text)` gives 969 and counts replays; deduplicating on text alone gives 747 and collapses genuine repetition (every "continue") to one row. **Count distinct instructions with the text key; count advancement-phrase frequency with the timestamp key.**

## Appendix B: forensic scope and known gaps

The facts here come from three places:

1. Session records (75 top-level files, 52 of them reconstructed; 56 subagent files across 10 subdirectories). §3's mechanisms and §5's categories and quotes come from here.
2. The two repositories themselves — `AGENTS.md` (174 lines), the structure and contents of `docs/superpowers/` (20,573 tracked lines), the build branch's 190 commits and 213 changed files against upstream, `scripts/submodule-ff-audit.sh`, PR status.
3. The 49 memory files and their index under `~/.claude/projects/<project>/memory/`. §6's conclusions come mainly from here and were cross-checked against the session records.

Four gaps, in order of impact:

- **The corpus is reconstructed, not original.** See §1. Every count covering 07-02 → 07-24 is an estimate over reconstructed material; the `recovered` column in a regenerated `prompts-dedup.tsv` supports re-checking against the 236 native inputs alone. Whether every swept session was reconstructed cannot be confirmed.
- **Half the classification table is unclassified.** 395 inputs (52%) are one-off substantive technical instruction forming no pattern. Classification is by keyword regex: magnitudes are sound, individual numbers should not be cited as exact.
- **The first timestamp is uncertain.** "2026-07-02 04:20" is the earliest input surviving the filters, but that whole period is reconstructed, so the true first input time is unknown.
- **This document covers the shape of the human/AI interaction only and does not assess the technical decisions themselves.** For whether a given option was the right one, or whether a given package should have been de-forked, see `2026-08-24-resolute-port-final-state-and-pitfalls-en.md` and `resolute-migration-code-review-en.md`.

`~/.claude/history.jsonl` is an independent record containing only human input. It was not used here and would serve as a cross-check on the figure of 747.

Related documents in this directory: `2026-08-24-resolute-port-final-state-and-pitfalls-en.md` (final state and pitfalls), `2026-08-31-sonic-202605-workflow-forensics-en.md` (upstream workflow forensics — the full account of case three in 6.2), `2026-07-27-resolute-defect-fixes-and-upstream-state-comparison-en.md` (component-by-component audit of an in-service switch), `2026-07-26-dut02-s5232f-validation-report-en.md` (hardware validation), `resolute-modification-catalog-en.md`, `resolute-migration-code-review-en.md`.
