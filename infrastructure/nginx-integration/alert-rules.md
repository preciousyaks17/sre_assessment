# infrastructure/nginx-integration/alert-rules.md

## Rule 1: 5xx error rate spike

- **Index:** `metrics-nginx*` (from the Prometheus scrape) or
  `logs-nginx.access-*` if computed from access logs instead
- **Condition:** `(count(status >= 500) / count(*)) * 100 > 5` over a
  2-minute rolling window
- **Rationale:** a sustained 5xx spike at the LB layer means backends are
  failing or unreachable — this is a direct user-facing outage signal and
  should page fast; 2-minute window balances speed against avoiding false
  positives from single-request blips.

## Rule 2: Upstream service unavailable (502/503)

- **Index:** `logs-nginx.access-*`
- **Condition:** KQL `status: (502 OR 503)` count > 0 over a 1-minute
  window, evaluated per upstream/backend service label so the alert
  identifies *which* backend is down, not just "something is down."
- **Rationale:** 502/503 specifically (vs generic 5xx) indicates the LB
  itself is healthy but can't reach or get a response from a backend —
  useful to distinguish from application-level 500s, since the fix is
  different (backend pod health/restart vs application bug).

## Rule 3: SSL certificate expiring within 14 days

- **Index:** `metrics-nginx*` (nginx_ingress_controller_ssl_expire_time_seconds)
- **Condition:** `(ssl_expire_time_seconds - now()) < 14 days`
- **Rationale:** cert expiry is a slow-moving, 100%-preventable outage
  cause. 14 days gives enough lead time for a renewal to go through
  change management without last-minute panic.

All three use the log connector for actions in this assessment environment;
in a real production setup these would route to a paging system (PagerDuty/
Opsgenie) for rules 1 and 2, with rule 3 routed to a lower-urgency ticket
queue since it's not time-critical on a per-minute basis.
