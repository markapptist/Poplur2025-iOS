# Bounded map discovery

The map loads spatial winners and local pages instead of subscribing to the newest posts worldwide. The feed and the account's total radius retain their separate data sources.

## Contract and presentation

- `queryMapDiscovery` is an authenticated callable, schema 1. The browser calls it with Firebase Auth; the embedded map relays through the signed-in iOS/Android shell.
- World views read at most 64 regional summary tiles per cohort. City views read at most 200 approximately 5 km cells. A latitude-band grid adjusts longitude widths for latitude; cells are approximate squares, not cadastral boundaries.
- Street views query at most 24 intersecting cells and return pages of 50, including non-winning posts. Cursors bind to viewer, viewport, zoom and cohort. A selected post may be hydrated separately.
- Responses contain at most 200 post markers and 200 cell outlines. The existing renderer limits rich pins to 18 (10 at world scale); additional posts use a batched GeoJSON layer.
- Pan/zoom cancels stale results. Requests debounce 220 ms after movement and refresh once a minute only while the map is visible. A new page replaces the previous page to keep memory bounded.
- Profile/account totals and the posting maximum do not come from the viewport result.

## Competition and privacy

Accepted engagement receipts contribute recent unique views, likes, comments, dislikes and radius growth. An actor contributes once per event kind per six-hour window. Owner engagement is excluded; synthetic actors cannot elect real winners. Real and test cohorts have separate summaries.

Scores decay with a six-hour half-life, normalize engagement/growth by exposure, and reduce confidence for small samples. At least five decayed unique views qualify a winner. Until then the newest eligible post is a provisional new pop. A challenger must exceed the incumbent by 10% for two minutes. Candidates expire after 72 hours without a newer rank event.

Cell elections examine up to 16 qualified-at-write candidates from each of 13 six-hour buckets, plus 32 newest posts: at most 240 indexed documents. This is a bounded candidate election, not an exhaustive scan of every post in a hot cell. Parent summaries aggregate child leaders.

Post changes atomically update the spatial projection and a sharded invalidation outbox. Cloud Tasks coalesces work, retries failures, and schedules expiry/challenger transitions. A repair schedule revisits overdue work. Owner privacy changes reconcile that owner's posts in pages of 100.

Every response re-reads live posts, owners and mutual blocks before returning a whitelisted payload. Private, ghost, disabled, deleted, unpublished, blocked and moved-away candidates disappear even while a cached election is stale. A hidden winner is omitted rather than replacing it with an unelected alternate. Ranking identities and private collections are never sent to clients.

## Retention processing

`radiusDecayQueue` stores due time plus one of 256 stable post shards. Every minute, the dispatcher visits 32 shards; each shard is visited once per eight minutes. A worker processes up to five pages of 200 due posts. Decay, history, account delta and due-time advancement share one transaction, making retries idempotent. The existing hourly full scan is disabled while `dueDecayEnabled` is true and remains available for rollback. This changes scheduling, not real-user decay weights.

## Deployment and rollout

`mapDiscovery/config` contains `enabled`, `dueDecayEnabled`, `includeTest`, schema and optional canary UIDs. The administrator script is deliberately not a public callable:

```sh
node functions/scripts/mapDiscoveryAdmin.js PROJECT backfill
node functions/scripts/mapDiscoveryAdmin.js PROJECT verify
node functions/scripts/mapDiscoveryAdmin.js PROJECT enable
```

Deploy `firestore.indexes.json`, wait for indexes to become READY, deploy the exported map/queue functions, backfill, verify, then enable. `backfill` is resumable and records migration state; it does not change post contents or radii. `requeue` repairs up to 500 due jobs. Access to all new private collections falls through the existing deny rules.

Current deployment fits the project's existing regional CPU quota: query instances are capped at 4 with concurrency 40; each task worker at 2 instances with concurrency 8 and 16 concurrent dispatches; event triggers use fractional CPU and at most 4 instances. These are rollout bounds, not a throughput promise.

Rollback: an administrator sets both `enabled` and `dueDecayEnabled` to false. Updated clients resume the legacy map subscription after their next refresh, and the hourly decay schedule resumes at its next run. To stop in-flight decay as well, pause the `radiusDecayWorker` task queue and let current transactions finish. Do not delete indexes or migration state during rollback.

## Validation and remaining capacity work

The emulator exercises pagination, cursor isolation, confidence/hold elections, deduplicated events, synthetic separation, privacy, mutual blocks, deletion, edited origins and transactional due-work retries. The policy stress test generates one million synthetic records in memory and streams cell elections; it does not insert one million Firestore documents or simulate one million concurrent users.

This release uses materialized JSON summaries and a bounded 512-entry, 30-second warm-instance summary cache. Personalized post payloads bypass shared caches and retain live privacy checks. Public CDN/vector tiles, exact cell counts/movement badges and a dedicated contender drawer are not part of this initial deployment. At larger traffic volumes, publish only non-personalized geometry/summary IDs through a versioned tile cache, then hydrate eligible details through the authenticated API.

Before claiming million-user readiness, run a separate staging workload with dense cities, sustained concurrent viewers and bursty events; measure p50/p95/p99 request latency, queue age, election lag, Firestore reads/writes/index entries, CPU quota, mobile memory and frame time. Raise quotas and worker budgets only from those measurements. Current live canary measurements are small-dataset admin queries from the developer machine, not end-to-end callable latency or a production load test.
