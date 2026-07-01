# infrastructure/elastic-agent-policies/vm-system-integration.md
#
# Section 3.1 — VM / Compute monitoring for the 2 Ubuntu VMs (bastion host
# + CI runner), via Fleet-managed Elastic Agent with the System integration.
#
# Fleet is a UI-driven workflow in Kibana, so this file documents the exact
# steps/config rather than a single applicable YAML (unlike a standalone
# Beats setup). If Fleet isn't usable in the assessment environment for any
# reason, `elastic-agent-standalone.yml` in this folder is the fallback.

## Steps (Kibana -> Fleet)

1. Kibana -> Management -> Fleet -> Agent Policies -> Create policy:
   `vm-hosts-policy`.
2. Add integration: **System** (from the Integrations catalog).
   - Enable datasets: `cpu`, `memory`, `disk`, `diskio`, `filesystem`,
     `network`, `load`, `process`, `process_summary`, `socket_summary`.
   - Set collection period: 10s for cpu/memory/network (high-resolution
     enough to catch short spikes), 60s for filesystem (slow-changing,
     no need for high resolution — reduces index volume).
3. Kibana -> Fleet -> Agents -> Add agent -> copy the enrollment command
   for policy `vm-hosts-policy`.
4. On each VM (bastion + CI runner), run the generated enrollment command,
   e.g.:
   ```
   sudo elastic-agent install \
     --url=<fleet-server-url> \
     --enrollment-token=<token-for-vm-hosts-policy>
   ```
5. Verify in Kibana -> Observability -> Infrastructure -> Inventory that
   both hosts appear with live metric tiles.

## Metric coverage mapping (requirement 3.1.2)

| Requirement | System integration dataset / field |
|---|---|
| CPU per-core + aggregate | `system.cpu.*` (per-core via `system.cpu.core_*`) |
| Memory used/available/cached/buffered | `system.memory.*` |
| Disk I/O (IOPS, throughput, latency, util) | `system.diskio.*` |
| Network I/O (bytes, packets, errors, drops) | `system.network.*` |
| Filesystem usage (% used, inodes) | `system.filesystem.*` |
| Load averages | `system.load.*` |
| Process counts | `system.process.summary.*` |

## Alerting rules (requirement 3.1.4)

Created under Kibana -> Observability -> Rules, type "Metric threshold":

1. **High CPU sustained** — `system.cpu.total.norm.pct > 0.85` for 5
   consecutive minutes, grouped by `host.name` (so each VM alerts
   independently). Rationale: single CPU spikes are normal; 5-minute
   sustained high usage indicates an actual resource constraint (runaway
   process, undersized instance) worth investigating.
2. **Disk space critical** — `system.filesystem.free / system.filesystem.total
   < 0.10`, grouped by `host.name` + `system.filesystem.mount_point`.
   Rationale: disk-full is a hard failure mode (services crash, logs stop
   writing); 10% free gives a window to clean up or expand before that
   happens.
3. **Memory pressure** — `system.memory.actual.free < 500000000` (500MB in
   bytes), grouped by `host.name`. Rationale: below this threshold, Linux
   OOM-killer risk rises sharply, especially on smaller CI-runner instance
   types where spiky memory usage during builds is common.

Action for all 3: log connector configured to write to a dedicated
`alerts-vm-*` index (or webhook, if the assessment environment provides
one) — documented in `infrastructure/alerting-rules/` once exported as
NDJSON from the live Kibana instance.
