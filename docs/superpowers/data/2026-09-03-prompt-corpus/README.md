# Prompt corpus for the resolute AI-workflow retrospective

Backs the statistics in `docs/superpowers/2026-09-03-resolute-ai-workflow-retrospective-{zh,en}.md`.

## Files

| File | What it is |
|---|---|
| `mine-prompts.py` | Extraction + classification pipeline. Run with no arguments to regenerate the outputs. |
| `corpus-stats.txt` | Output of the last run. Committed. |
| `prompts-dedup.tsv` | One row per text-deduplicated human input: timestamp, source file, recovered flag, category, text. **Not committed** — it is the verbatim prompt corpus. Regenerate it locally when you need to re-check a claim. |

```
./mine-prompts.py [PROJECT_DIR] [--out DIR]
```

`PROJECT_DIR` defaults to `~/.claude/projects/-home-sheldon-qi-sonic-buildimage/`.

## Corpus provenance — read this before citing any number

The session records are **not** a pristine capture.

`cleanupPeriodDays` defaults to 30 days. On 2026-08-24 we found that records from
before roughly 2026-07-24 had already been swept, and raised the setting to 3650
— too late for the migration's main body. On 2026-09-03 the missing sessions were
**reconstructed from the LLM API gateway's request log**, keyed on timestamps.
They were not restored from a backup.

Consequences, all verifiable from the files:

- 52 of the 75 top-level `*.jsonl` carry `"recovered": true`. The 23 native files
  start at 2026-07-25.
- The reconstructed files contain **zero** records with a non-null `toolUseResult`.
  Step 1 of the pipeline filters on that field, so for those 52 files the filter
  is a no-op: tool results were either dropped by the reconstruction or are mixed
  in as ordinary user text.
- Fidelity was never independently confirmed against the originals, because the
  originals are gone.

So: counts covering 2026-07-02 → 2026-07-24 are **estimates over a reconstructed
corpus**, not exact totals. Regenerating `prompts-dedup.tsv` gives a per-row
`recovered` column, so any claim can be re-checked against native-only records
(236 of the 747 deduplicated inputs). That file is not committed.

## Three filtering steps, each of which was got wrong first

1. **Structural filter.** Keep `type=="user"` where `isSidechain` is not true,
   `isMeta` is not true, and `toolUseResult` is null. Subagent turns are also
   persisted with role `user` (5,820 of them at top level); so are tool results;
   so are harness injections like skill bodies and agent listings, which is what
   `isMeta` catches. Without the `isMeta` check a 240 KB skill manual counts as
   one human "input" and wrecks the length statistics.

2. **Text filter, with a distinction that matters.** Most non-human text injected
   in the user role should be dropped (`<system-reminder>`, hook feedback,
   task notifications, the `/goal` judge prompt, relayed agent messages, …).
   But four forms *wrap* real input rather than replace it, and dropping the
   record would discard the human's actual words:

   - `The user sent a new message while you were working:\n<real input>`
   - `<ide_selection>` / `<ide_opened_file>` blocks
   - `The user selected the lines N to M from <path>` preambles
   - a trailing `CRITICAL: Respond with TEXT ONLY …` hook suffix

   Slash commands are kept by extracting `<command-args>`, which is the human's
   own text; the `<command-name>` wrapper is not.

3. **Two dedup keys, because neither alone is right.** Resuming a session
   re-persists earlier messages. Deduplicating on `(timestamp, text)` gives 969
   and over-counts replays; deduplicating on text alone gives 747 and
   under-counts genuine repetition — every "continue" collapses to one row.
   Count *distinct instructions* with the text key; count *advancement-phrase
   frequency* with the timestamp key.

## Known limits

- **52% of inputs are unclassified.** The categories are keyword heuristics over
  Chinese and English; each input is assigned to at most one category, first
  match wins. The unclassified half is mostly one-off substantive technical
  instruction that follows no recurring pattern. Treat the category magnitudes
  as sound and individual numbers as approximate.
- The longest two entries (7,157 and 2,799 characters) are pasted file content
  and a long research brief, not typed prose. They inflate `max` but not the
  median or the percentiles the retrospective actually relies on.
- `~/.claude/history.jsonl` is an independent record that contains only human
  input. It was not used here and would make a useful cross-check.
