# Runbook: RDS CPU Pegged

## Symptom
- Alert firing: RDS CPU > 80% for 5 minutes
- API response times degrading
- Dashboard queries timing out

## Dashboards to Check First
1. **Infrastructure** → RDS CPU/connections/IOPS
2. **Service Health** → API Latency p95 — correlate with RDS CPU spike
3. **Business Metrics** → URLs shortened/hour — is there a traffic spike?

## Diagnostic Steps

### Step 1 — Find the slow queries
Connect via SSM Session Manager (no bastion needed):
```bash
aws ssm start-session \
  --target $(aws ecs list-tasks \
    --cluster ecs-combined-prod \
    --service-name ecs-combined-prod-api \
    --query "taskArns[0]" --output text) \
  --region eu-west-2
```

Or check CloudWatch Logs for slow query log:
```bash
aws logs tail /aws/rds/instance/ecs-combined-prod/postgresql \
  --follow \
  --region eu-west-2 | grep "duration"
```

### Step 2 — Check pg_stat_statements
```sql
SELECT query, calls, total_exec_time/calls as avg_ms,
       rows, shared_blks_hit, shared_blks_read
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Likely Causes and Fixes

**Missing index** — new query pattern hitting sequential scan
- Add index, monitor EXPLAIN ANALYZE output

**Click events table unbounded growth** — no partitioning
- Add a cleanup job: `DELETE FROM click_events WHERE created_at < NOW() - INTERVAL '90 days'`

**Too many connections** — connection pool exhausted
- Scale down ECS tasks temporarily
- Long term: add PgBouncer

**Traffic spike** — legitimate load increase
- Scale up RDS instance class (requires ~5 min maintenance window)
- Enable RDS read replica for dashboard queries

## Emergency — Immediate Relief
If CPU is at 100% and services are down:
```bash
# Temporarily scale down worker to reduce write load
aws ecs update-service \
  --cluster ecs-combined-prod \
  --service ecs-combined-prod-worker \
  --desired-count 0 \
  --region eu-west-2
```

Remember to scale back up after the incident.