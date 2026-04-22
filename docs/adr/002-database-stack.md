# ADR-002: Monitoring Stack

## Status
Accepted

## Context
The spec requires full observability — metrics, dashboards, and alerting.
Two options were evaluated:

**Option A: Self-hosted** — Prometheus + Grafana on ECS Fargate
**Option B: Managed** — Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG)

## Decision
Self-hosted Prometheus and Grafana on ECS Fargate.

## Reasoning

| Concern | Self-hosted | Managed |
|---|---|---|
| Cost (dev) | ~$10/month | ~$30/month base + per metric |
| Operational burden | Medium — we manage upgrades | Low |
| Flexibility | Full — any exporter, any dashboard | Limited by AMG plugin support |
| Learning value | High | Low |
| Setup time | Higher | Lower |

The spec explicitly states self-hosted is the default because it teaches more.
For a production system owned by a small team, managed would be preferable.

## Consequences
**Positive:**
- Full control over scrape configs, retention, and dashboard JSON
- Lower cost at small scale
- Demonstrates real observability engineering

**Negative:**
- We own upgrades and availability of the monitoring stack
- Grafana state on EFS adds operational complexity
- If Prometheus goes down we lose metrics visibility

## Managed Alternative
If operational burden becomes unacceptable:
- Migrate to AMP by changing the remote_write endpoint in prometheus.yml
- Migrate Grafana dashboards to AMG via the API
- Estimated migration time: 1 day