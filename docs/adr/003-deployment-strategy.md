# ADR-003: Deployment Strategy

## Status
Accepted

## Context
Three deployment strategies were considered for ECS services:

1. **Rolling update** — replace tasks gradually, always some old + some new running
2. **Blue/green** — run two full environments, switch traffic atomically via CodeDeploy
3. **Canary** — send a small % of traffic to new version, gradually increase

## Decision
ECS rolling deploy with circuit breaker and auto-rollback enabled.

## Reasoning
- Rolling deploy is native to ECS with zero additional AWS services
- Circuit breaker (`deployment_circuit_breaker { enable = true, rollback = true }`) gives automatic rollback if health checks fail
- Blue/green requires CodeDeploy, an additional ALB target group, and more complex pipeline logic
- Canary requires a service mesh or weighted target groups — overkill for this scale

For a URL shortener the main risk during deploy is a bad DB migration, not
traffic routing. The circuit breaker handles bad code; migrations are handled
separately as a pre-deploy ECS task.

## Consequences
**Positive:**
- Simple — no additional AWS services
- Automatic rollback on health check failure
- Zero downtime as long as desired_count >= 2

**Negative:**
- During rollout both old and new versions serve traffic simultaneously
- No fine-grained traffic control (10% canary etc.)
- If a migration is not backward compatible, rolling deploy will cause errors
  during the transition window

## Migration Safety Rule
All DB migrations must be backward compatible with the previous version of the
application. Non-additive changes (column renames, type changes) must be split
into multiple deploys.