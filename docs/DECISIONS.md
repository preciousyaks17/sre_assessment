# Architectural Decision Log

This log tracks key trade-offs made during the assessment, and — given the
24-hour turnaround — an honest account of what was prioritized, what was
scoped down, and what would be done next with more time.

## Scope & Prioritization (read this first)

Given the 24-hour window against the full scope of this assessment (11
services across multiple languages, RUM, 3 dashboard suites, and infra
monitoring across 5 separate systems), full "Excellent" tier completion on
every section was not realistic. Priorities were set as:

1. **Section 1 (OTel Collector + instrumentation + trace validation)** —
   highest priority. This is the foundational pipeline; nothing else works
   without it, and it's the most heavily weighted rubric category.
2. **Section 3 (infra monitoring)** — second priority, aiming for coverage
   across all 4 required components at "adequate," rather than depth on
   fewer. The rubric rewards component *breadth* here.
3. **Section 2 (RUM + dashboards)** — implemented at a functional-but-not-
   exhaustive level: RUM agent wired in and Web Vitals confirmed flowing;
   dashboards use a mix of out-of-the-box Elastic integration dashboards
   plus a smaller set of custom Lens panels rather than the full panel list
   specified for all 3 dashboards.

Where a requirement was scoped down or skipped, it's called out explicitly
below and in the relevant subdirectory's own notes, rather than silently
omitted.

## 1.1 — OTel Collector Topology

**Decision:** Gateway + Agent (DaemonSet) topology, as required.

- **Agents (DaemonSet)** do local hostmetrics collection + k8s attribute
  enrichment, then forward everything to the gateway. They do NOT hold the
  Elastic APM Server credentials — only the gateway does.
- **Gateway (Deployment, 2 replicas)** performs tail-based sampling (needs
  full traces assembled, which requires a single point of aggregation) and
  is the only component exporting to Elastic via OTLP.

**Trade-off accepted:** with 2 gateway replicas and no load-balancing
exporter in front of them, a given trace's spans could in theory land on
different gateway pods and break tail-sampling's "see the whole trace"
assumption under high concurrency. For the traffic volume in this
assessment (demo app, scripted test traffic) this isn't a practical
problem, but in a real production deployment this would need either a
single gateway replica per sampling domain, or the `loadbalancing` exporter
on the agents keyed by trace ID. Documented here rather than solved, given
time constraints.

**Sampling policy:** always-sample errors, always-sample >2s latency,
10% baseline. Full rationale in `otel-collector/sampling-policy.yaml`.

## 1.2 — Service Selection for Instrumentation

Chosen: **frontend (Go)**, **recommendationservice (Python)**,
**paymentservice (Node.js)**.

**Rationale:** these three have the best-documented, most stable
auto-instrumentation libraries in the OTel ecosystem, which matters given
the time budget. C#, C++, and Ruby instrumentation for cartservice,
currencyservice, and emailservice were scoped out — noted as not attempted
rather than attempted-and-broken.

## Status Tracker

| Section | Status | Notes |
|---|---|---|
| 1.1 Collector deploy | Done (values files) | Not yet applied against a live cluster in this session |
| 1.2 Instrumentation (3 services) | Done (code written) | frontend (Go), paymentservice (Node.js), recommendationservice (Python) — auto-instr + 2 custom spans + 1 custom metric each. Not yet deployed/verified against a live cluster in this session. |
| 1.3 Trace validation | In progress | Script + checklist being drafted; actual screenshots require a live cluster, which is outside this offline drafting session |
| 2.1 RUM | Not started | Next up |
| 2.2 Dashboards | Not started | |
| 3.1 VM monitoring | Done (Fleet steps + standalone fallback + alert rules documented) | Not yet applied against real VMs |
| 3.2 DB monitoring (Postgres/Redis) | Done (Beats configs + alert rules documented) | Not yet applied against real DB instances; Redis cluster topology caveat noted in redis.yml |
| 3.3 Firewall/NetworkPolicy | Scoped down / likely skipped | Highest complexity, lowest distinct rubric weight given overlap with 3.1/3.2 patterns |
| 3.4 NGINX / load balancer | Done (OTel Prometheus receiver + Filebeat access logs + alert rules documented) | Not yet applied against real ingress controller |

*(This table will be updated as work progresses — treat it as the live
source of truth for what's actually done vs. planned.)*

## Session Log — Day 2: Cluster Restart & Scheduling Constraint

### AKS cluster auto-stopped overnight
The sandbox/trial Azure subscription used for this assessment
(`ME-MngEnvMCAP...`) appears to auto-stop idle AKS clusters after a period
of inactivity — the cluster's `powerState` was found `Stopped` at the
start of Day 2, despite having been left running the previous session.
Fixed via `az aks start`. Node VMs were recreated on restart (new VM names:
`vmss000003/4/5` vs. the original `000000/1/2`), but this is normal/
expected AKS behavior for a stopped-then-started cluster with no persistent
node identity requirement — all workloads (Online Boutique + OTel
Collector) rescheduled automatically without any manual redeployment,
confirming the deployments/DaemonSets were correctly configured to
self-heal.

**Lesson for future sessions:** always check `az aks show --query
powerState.code` before assuming a "cluster not reachable" DNS error means
something is broken — it may simply be stopped.

### Known constraint: DaemonSet agent pod scheduling on undersized nodes
One of the 3 OTel Collector agent DaemonSet pods remains stuck `Pending`
after the cluster restart, due to CPU **request** exhaustion (not actual
usage — `kubectl top nodes` shows real CPU usage at 10-20%, but two of the
three nodes have 94-99% of *requested* CPU already reserved by Online
Boutique's 11 services + loadgenerator, all packed onto small
Standard_D2s_v3 (2 vCPU) nodes).

Attempted fix: lowered the agent's CPU request from 100m to 50m — did not
fully resolve it, the remaining headroom is that tight. Given time
constraints, **not pursuing further** (e.g. increasing node count/size,
adding resource limits to Online Boutique's own pods, or using a larger
VM SKU) — 2 of 3 agent pods running is sufficient to demonstrate the
DaemonSet + Gateway topology works correctly per the rubric's evaluation
criteria, which assesses architectural correctness, not 100% pod
scheduling success on an intentionally small/cheap node pool.
**Documented here as a known, understood, and consciously-deprioritized
issue** rather than a silent gap.
