# Runbook: API Returning 5xx

## Symptom
- Error rate alert firing: `api_requests_total{status_code=~"5.."}` > 1%
- Users reporting errors on shorten or redirect endpoints
- Grafana service health dashboard showing red

## Dashboards to Check First
1. **Service Health** → Error Rate panel — is it all endpoints or one specific path?
2. **Service Health** → API Latency p95 — is latency spiking before the errors?
3. **Infrastructure** → RDS CPU/connections — is the DB overwhelmed?

## Likely Causes and Remediation

### 1. Database connection exhaustion
**Symptoms:** Errors contain `connection pool exhausted` or `too many connections`

**Check:**
```bash
# Check RDS connections in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=ecs-combined-prod \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region eu-west-2
```

**Fix:** Scale down ECS desired count temporarily, then scale back up gradually.

### 2. RDS failover in progress
**Symptoms:** Errors start suddenly, resolve within 60-90 seconds

**Check:** RDS console → Events tab — look for failover event

**Fix:** Wait for failover to complete. No action needed unless it persists.

### 3. Bad deployment
**Symptoms:** Errors start immediately after a deploy

**Check:**
```bash
# Check recent ECS deployments
aws ecs describe-services \
  --cluster ecs-combined-prod \
  --services ecs-combined-prod-api \
  --region eu-west-2 \
  --query "services[0].deployments"
```

**Fix:** Roll back via GitHub Actions — re-run the deploy workflow with the previous SHA.

### 4. Secret rotation caused connection failure
**Symptoms:** DB errors after Secrets Manager rotation (every 30 days)

**Fix:** Force new ECS deployment to pick up the new password:
```bash
aws ecs update-service \
  --cluster ecs-combined-prod \
  --service ecs-combined-prod-api \
  --force-new-deployment \
  --region eu-west-2
```

## Escalation
If none of the above resolves within 15 minutes, check CloudWatch Logs:
```bash
aws logs tail /ecs/ecs-combined-prod/api --follow --region eu-west-2
```