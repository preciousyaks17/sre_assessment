# infrastructure/redis-integration/alert-rules.md

## Rule 1: Memory usage approaching maxmemory

- **Rule type:** Elasticsearch query threshold rule
- **Index:** `metrics-redis.info-*`
- **Condition:** `(redis.info.memory.used_value / redis.info.memory.max_value) * 100 > 85`
- **Evaluation window:** 5 minutes
- **Action:** log connector
- **Rationale:** once Redis hits maxmemory, its configured eviction policy
  kicks in (or writes start failing, depending on policy) — 85% gives
  headroom to intervene (scale up, adjust eviction policy, or investigate
  a memory leak in usage patterns) before that happens.

## Rule 2: High eviction rate

- **Rule type:** Elasticsearch query threshold rule
- **Index:** `metrics-redis.info-*`
- **Condition:** rate of increase of `redis.info.stats.evicted_keys` over a
  5-minute window exceeds a sustained threshold (e.g. >50 keys/sec
  sustained) — implemented as an ES|QL rule computing the delta between
  consecutive periods rather than an absolute value, since evicted_keys is
  a cumulative counter.
- **Evaluation window:** 5 minutes
- **Action:** log connector
- **Rationale:** cartservice depends on Redis being available and warm.
  A rising eviction rate is an early signal that the working set no
  longer fits in memory, which for a cart cache specifically risks users'
  carts disappearing mid-session — a direct product-impacting failure
  mode, not just an infra metric.
