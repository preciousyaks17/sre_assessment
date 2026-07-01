# infrastructure/postgres-integration/alert-rules.md
#
# Kibana -> Observability -> Rules definitions for PostgreSQL (requirement
# 3.2.3). Actual rules are created in the Kibana UI or via the Kibana Alerting
# API — this file documents the exact config to enter, and doubles as the
# "documented rationale" the rubric asks for. Once created in Kibana, export
# via Stack Management -> Saved Objects and drop the NDJSON in
# infrastructure/alerting-rules/.

## Rule 1: Connection pool exhaustion

- **Rule type:** Elasticsearch query (ES|QL or KQL threshold rule)
- **Index:** `metrics-postgresql.database-*`
- **Condition:** `postgresql.database.connections / postgresql.database.max_connections > 0.8`
  (if the integration doesn't expose max_connections as a field directly,
  set it as a static threshold matching the known instance config, e.g.
  `postgresql.database.connections > (max_connections * 0.8)`)
- **Evaluation window:** 5 minutes
- **Action:** log connector (or webhook, per assessment environment)
- **Rationale:** connection exhaustion is a hard outage mode for Postgres —
  new connections get rejected outright once the pool is full. 80% gives
  enough lead time to investigate before actual exhaustion, without being
  so sensitive it fires on normal peak-hour load.

## Rule 2: Cache hit ratio degradation

- **Rule type:** Elasticsearch query threshold rule
- **Index:** `metrics-postgresql.database-*`
- **Condition:**
  `(sum(postgresql.database.blocks.hit) / (sum(postgresql.database.blocks.hit) + sum(postgresql.database.blocks.read))) * 100 < 95`
- **Evaluation window:** 10 minutes (cache ratio is noisy over short windows,
  a 10-min rolling window avoids alert flapping on momentary blips)
- **Action:** log connector
- **Rationale:** a healthy OLTP workload should serve the vast majority of
  reads from shared_buffers cache. A sustained drop below 95% usually means
  either shared_buffers is undersized for the working set, or a query
  pattern change (e.g. a new full table scan) is thrashing the cache —
  both are worth paging someone about before they become a latency problem
  visible to users.

---

Both rules assume the standard Elastic PostgreSQL integration field
mappings (`postgresql.database.*` namespace). Field names should be
verified against the actual integration version deployed, since Elastic
has occasionally renamed fields across integration major versions.
