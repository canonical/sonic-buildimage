# Data: sonic-net/sonic-buildimage `202605` branch forensics (2026-08-31)

Raw evidence behind
[`2026-08-31-sonic-202605-workflow-forensics-en.md`](../../2026-08-31-sonic-202605-workflow-forensics-en.md)
/ [`-zh.md`](../../2026-08-31-sonic-202605-workflow-forensics-zh.md).

Snapshot taken 2026-08-31, upstream tip `be4939271e761c4946afead0d78a18c33d97987a`.

## Files

| File | What it is | How it was produced |
|---|---|---|
| `activity-202605.json` | **Authoritative** ref-activity log for `refs/heads/202605`: 195 records, `2026-06-03T06:10:13Z branch_creation` → `2026-08-31T09:13:22Z`. Type distribution: `pr_merge` 194, `branch_creation` 1, `push` 0, `force_push` 0. | `gh api --paginate -X GET 'repos/sonic-net/sonic-buildimage/activity' -f ref=refs/heads/202605 -f per_page=100` |
| `push-events-202605.json` | 35 GitHub `PushEvent`s (2026-06-09 → 2026-08-24) from [GH Archive](https://www.gharchive.org/) via [BigQuery](https://console.cloud.google.com/bigquery), dataset `githubarchive.day.2026*`. **18% coverage** of the branch's real tip advances — see `query-gharchive.sql`. | `query-gharchive.sql` |
| `query-gharchive.sql` | The exact BigQuery SQL that produced the row set above, plus the caveats. | supplied by the user |
| `commits-202605-first-parent.tsv` | 193 first-parent commits from the branch point `ea4acb6bc2` to the tip, with signature status. Columns: `sha, commit_date, author, committer, signed, parents, subject`. | `git log --first-parent` + `git cat-file commit \| grep '^gpgsig'` |
| `stripped-vs-signed-twins.tsv` | The signature-stripped / signed commit pairs, showing identical trees. | `git rev-parse <sha>^{tree}` on both chains |
| `raw-commit-2017-{stripped,signed}.txt` | Byte-level dump of the two 2017-10-27 twins. The **only** difference is the `gpgsig` header. | `git cat-file commit <sha>` |

## Caveats

- **The Activity API retains ~90 days.** `202605` was created 2026-06-03, i.e. 89 days before this
  snapshot, so the window happens to cover the branch's entire life. Older branches (202511, 202505)
  cannot be audited this way — re-run against them and you will get a truncated window.
- `push-events-202605.json` is a sample, not a log — and **not because of the query**. The SQL's
  date range covers the branch's entire life and its `LIMIT 1000` was never reached, yet it returns
  35 rows against 194 real tip advances (**18%**). The loss is in GitHub's public event firehose
  that GH Archive mirrors. Cross-check performed: all 35 rows map to real `pr_merge` records
  (100% precision, zero phantom rows), and none of the 10 merge-commit advances were captured.
  Every row is a fast-forward of exactly one commit, but **absence of a force-push row proves
  nothing**; use `activity-202605.json` for that.
- Conversely, `activity-202605.json` **is** provably complete for this branch: sorting its 195
  records by timestamp and checking `before[i] == after[i-1]` gives zero gaps, from
  `branch_creation` to the tip.
- One `before_sha` in the push events (2026-08-23, `1b9c46411c`) arrived truncated in the source data.
  It is consistent with the real parent of `71b53c5eaa`.
- The stripped-chain objects (`7177dca054`, `67a348840b`, …) exist only in the local clones
  (`~/sonic-buildimage`, `~/sonic-buildimage-resolute`). They 404 on GitHub. If those clones are
  ever re-created from scratch, this evidence is unreproducible — hence the raw dumps above.

## Reproduce the headline checks

```sh
# 1. No force-push ever happened on 202605
gh api --paginate -X GET 'repos/sonic-net/sonic-buildimage/activity' \
  -f ref=refs/heads/202605 -f per_page=100 |
  jq -r '.[].activity_type' | sort | uniq -c
# control: the filter does work — this lists real force pushes
gh api -X GET 'repos/canonical/sonic-buildimage/activity' -f activity_type=force_push

# 2. The divergence point is exactly the parent of the repo's first signed commit
git rev-list --reverse --first-parent sonic-net/202605 | head -1200 | while read h; do
  git cat-file commit "$h" | sed -n '/^$/q;p' | grep -q '^gpgsig' && { git log -1 --format='%h %s' "$h"; break; }
done                                     # -> 961a6669f7, whose parent is 437419c79e

# 3. Stripped twin is byte-identical except for gpgsig
diff <(git cat-file commit e2a863b60ab89a464215f567c00207510a3498d4) \
     <(git cat-file commit 961a6669f7c896d0521b0a9bfc796330f12608fe)

# 4. Stripped 2026-era SHAs do not exist upstream
gh api repos/sonic-net/sonic-buildimage/commits/7177dca054dea934b5a70cdb8f62897b0ab981ff   # 404
gh api repos/sonic-net/sonic-buildimage/commits/9c84048a4240ea5d358f74b0821d2d51bba9a3b5   # 200
```
