# ecs-combined

A production-grade, end-to-end URL shortener and analytics platform deployed
on AWS ECS Fargate. Three application services, full observability stack,
zero long-lived credentials, zero NAT gateways, and a deployment pipeline
built to production standards.

---

## Overview

The platform shortens URLs, tracks clicks in real time, and exposes analytics
via a read API. Three services run on ECS Fargate behind an ALB with WAF:

| Service | Language | Port | Role |
|---|---|---|---|
| api | Python (FastAPI) | 8080 | Shortens URLs, handles redirects, publishes click events to SQS |
| worker | Go | 9091 | Consumes SQS, persists click analytics to PostgreSQL |
| dashboard | Go | 8081 | Read API — top URLs, hourly breakdowns, recent events |

---

## Architecture
Route 53 (hasanali.uk)
│
WAFv2 + ALB
│
┌────┴────────────┐
│                 │
api            dashboard
│                 │
├── SQS ──► worker
│
├── ElastiCache Redis (cache)
└── RDS PostgreSQL (primary store)
All compute in private subnets.
No NAT gateways — 12 VPC endpoints for AWS service traffic.

---

## How to Run Locally

Requirements: Docker Desktop, AWS CLI (for SQS via LocalStack)

```bash
git clone https://github.com/haz365/ecs-combined
cd ecs-combined
docker compose up --build
```

Services:
- API: http://localhost:8080
- Dashboard: http://localhost:8081
- Grafana: http://localhost:3000 (admin / devgrafana)
- Prometheus: http://localhost:9090

Test the flow:

```bash
# Shorten a URL
curl -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://google.com"}'

# Follow the redirect
curl -L http://localhost:8080/r/<short_code>

# Check analytics
curl http://localhost:8081/summary
curl http://localhost:8081/top-urls
```

---

## How to Deploy

### Prerequisites
- AWS CLI configured with `terraform-admin` credentials
- Terraform >= 1.7
- Docker

### Bootstrap (run once per account)
```bash
cd infra/bootstrap
terraform init
terraform apply -var="project=ecs-combined" -var="aws_region=eu-west-2"
```

### Deploy dev
```bash
make plan-dev
make apply-dev
```

### Deploy staging
```bash
make plan-staging
make apply-staging
```

### Deploy prod (requires manual approval in GitHub)
```bash
make plan-prod
make apply-prod
```

### Push images manually
```bash
SHA=$(git rev-parse --short HEAD)
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin \
  989346120260.dkr.ecr.eu-west-2.amazonaws.com

for svc in api worker dashboard; do
  docker build --platform linux/amd64 \
    -f docker/${svc}.Dockerfile \
    -t 989346120260.dkr.ecr.eu-west-2.amazonaws.com/ecs-combined/${svc}:${SHA} .
  docker push 989346120260.dkr.ecr.eu-west-2.amazonaws.com/ecs-combined/${svc}:${SHA}
done
```

### Tear down
```bash
make destroy-dev      # leaves no billable resources
make destroy-staging
```

---

## Deployment Workflow

A developer merges a PR to `main` at 3pm on a Tuesday.

### What triggers
1. If `app/` or `docker/` changed → `app-build.yml` triggers
   - Builds all three images for `linux/amd64`
   - Scans each with Trivy — fails on HIGH/CRITICAL
   - Generates SBOMs and uploads as artifacts
   - Pushes images to ECR tagged with the 7-char git SHA

2. On build success → `app-deploy.yml` triggers
   - Downloads the current task definition for each service
   - Updates the image URI to the new SHA tag
   - Registers a new task definition revision
   - Calls `ecs update-service` with the new task definition
   - Waits for `services-stable` (ECS rolling deploy with circuit breaker)
   - Runs smoke tests against the ALB `/health` endpoint
   - If smoke test fails → rolls back to previous task definition revision

3. If `infra/` changed → `infra-apply.yml` triggers
   - Runs `terraform apply` on dev automatically
   - Staging and prod require manual approval via GitHub Environments

### Database migrations
Migrations run as a one-off ECS task before the service deploy:
```bash
./scripts/run-migration.sh dev
```
All migrations must be backward compatible with the previous service version.
Non-additive changes are split across multiple deploys.

### Bad deploy detection
- ECS circuit breaker monitors task health during rollout
- If new tasks fail health checks → automatic rollback to previous revision
- Smoke tests in the pipeline provide a second gate
- Grafana error rate alert fires within 5 minutes if errors exceed 1%

### What the on-call engineer sees
- GitHub Actions: deploy workflow shows red, rollback step runs
- Grafana service health dashboard: error rate spike, then recovery
- CloudWatch Logs: `/ecs/ecs-combined-prod/api` shows the crash reason
- ECS console: deployment shows FAILED status, previous revision restored

### Non-rollbackable migrations
If a migration cannot be safely rolled back:
1. Keep the old column/table alongside the new one
2. Deploy the new service version that reads both
3. Backfill data
4. Deploy again removing the old column reads
5. Drop the old column in a final migration

---

## Observability

### Dashboards (Grafana)
| Dashboard | What to look at first during an incident |
|---|---|
| Service Health | Error rate, p95 latency per service |
| Infrastructure | ECS CPU/memory, RDS connections, Redis hit rate |
| Business Metrics | URLs shortened/hour, click events processed, SQS depth |
| Deployment Tracking | Annotation on deploy events, correlate with metric changes |

### Alerts
| Alert | Threshold | Action |
|---|---|---|
| API p95 latency | > 500ms for 5min | Check RDS CPU, connection count |
| Error rate | > 1% for 5min | Check logs, recent deploy |
| SQS depth | > 1000 for 10min | Check worker service, scale up |
| RDS CPU | > 80% for 5min | Check slow queries, scale instance |
| Task count below desired | 5min | Check ECS events, task stop reason |

### Structured logging
All services log JSON to CloudWatch with a `trace_id` field propagated
across the API → SQS → worker flow via the `X-Trace-ID` header.

---

## Security Posture

| Control | Implementation |
|---|---|
| Zero long-lived credentials | GitHub Actions uses OIDC to assume IAM role |
| Secrets | All in Secrets Manager, injected at task start, never in images |
| KMS | CMKs for RDS, S3, Secrets Manager, CloudWatch, SQS |
| Network | Private subnets only, no NAT, VPC endpoints for AWS services |
| WAF | AWS Managed Rules (Core + Known Bad Inputs + SQLi) + rate limiting |
| Container | Non-root user, read-only root filesystem, drop ALL capabilities |
| Images | Trivy scan on every build, SBOM generated, immutable ECR tags |
| IAM | Least-privilege per-service task roles, no wildcard actions |
| Audit | CloudTrail enabled, VPC Flow Logs to CloudWatch |
| Access | No bastion — SSM Session Manager only |

---

## Cost

Estimated monthly cost at rest (eu-west-2):

| Environment | Estimated Cost |
|---|---|
| Dev | ~$130/month |
| Staging | ~$160/month |
| Prod | ~$220/month |

Main cost drivers: VPC interface endpoints (~$7 each × 12), RDS, ElastiCache.

Run `make destroy-dev` when dev is not in use.

AWS Budgets configured per environment with alerts at 50%, 80%, 100%.

---

## Chaos + Load Test Results

### Chaos test
- Killed a running API task manually — ECS replaced it within 45 seconds
- Drained tasks from one AZ — remaining tasks in other AZs continued serving
- Finding: desired_count >= 2 is required for zero-downtime task replacement

### Load test (k6 against staging)
Total requests:  48,392
Failed requests: 12 (0.02%)
p50 latency:     45ms
p95 latency:     312ms
p99 latency:     489ms

Alarm thresholds set based on observed p95 at 2× peak load.

---

## Trade-offs and What I'd Do With Another Week

**What I'd improve:**
- Add PgBouncer as a connection pooler — RDS connections become the bottleneck first
- Implement OpenTelemetry tracing end to end across all three services
- Add canary deployments for prod using weighted ALB target groups
- Write a proper DR runbook and test RDS snapshot restore
- Add AWS Config rules for compliance drift detection
- Set up Dependabot for automatic dependency updates

**Deliberate trade-offs:**
- Self-hosted Prometheus/Grafana over managed — more to operate but teaches more
- Rolling deploy over blue/green — simpler, good enough at this scale
- Single AWS account over multi-account — reduced complexity for a solo project
- Standard SQS over FIFO — click events are idempotent, ordering not required

---

## ADRs
- [ADR-001: Database Choice](docs/adr/001-database-choice.md)
- [ADR-002: Monitoring Stack](docs/adr/002-monitoring-stack.md)
- [ADR-003: Deployment Strategy](docs/adr/003-deployment-strategy.md)
- [ADR-004: Secrets Management](docs/adr/004-secrets-management.md)
- [ADR-005: No NAT Gateway](docs/adr/005-no-nat-gateway.md)

## Runbooks
- [001: API returning 5xx](docs/runbooks/001-api-5xx.md)
- [002: SQS queue depth climbing](docs/runbooks/002-sqs-queue-depth.md)
- [003: RDS CPU pegged](docs/runbooks/003-rds-cpu.md)
- [004: Grafana showing no data](docs/runbooks/004-grafana-no-data.md)
- [005: Deploy rolled back automatically](docs/runbooks/005-deploy-rollback.md)