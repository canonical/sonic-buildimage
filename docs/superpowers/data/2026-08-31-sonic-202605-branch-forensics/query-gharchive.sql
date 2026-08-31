-- Provenance of push-events-202605.json
--
-- Source : GH Archive (https://www.gharchive.org/), queried through BigQuery
--          (https://console.cloud.google.com/bigquery), public dataset `githubarchive`.
-- Run    : 2026-08-31, returned 35 rows (LIMIT 1000 was NOT reached).
--
-- IMPORTANT — this result set is COMPLETE with respect to the query but NOT with respect
-- to reality. The date range 0401..0831 fully covers the life of the 202605 branch
-- (created 2026-06-03) and the LIMIT was never hit, yet it yields only 35 PushEvents
-- against 194 real tip advances recorded by the GitHub Activity API — 18% coverage.
-- The loss is in GitHub's public event firehose that GH Archive mirrors, not in this SQL.
-- Never conclude "no force push happened" from this table; use the Activity API
-- (activity-202605.json) for that.
--
-- Also note: JSON_VALUE(payload, '$.size') came back NULL for all 35 rows, so commit_count
-- is unusable from this source. The per-push commit counts in our analysis were derived
-- from git instead (`git rev-list --count <before>..<head>`) — all 35 advanced by 1 commit.

WITH pushes AS (
  SELECT
    created_at,
    actor.login AS actor,
    JSON_VALUE(payload, '$.ref') AS ref,
    JSON_VALUE(payload, '$.head') AS head_sha,
    JSON_VALUE(payload, '$.before') AS before_sha,
    SAFE_CAST(JSON_VALUE(payload, '$.size') AS INT64) AS commit_count,
    JSON_VALUE(payload, '$.push_id') AS push_id
  FROM `githubarchive.day.2026*`
  WHERE _TABLE_SUFFIX BETWEEN '0401' AND '0831'
    AND type = 'PushEvent'
    AND repo.name = 'sonic-net/sonic-buildimage'
    AND JSON_VALUE(payload, '$.ref') = 'refs/heads/202605'
)
SELECT *
FROM pushes
ORDER BY created_at DESC
LIMIT 1000;
