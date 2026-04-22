# Runbook: Grafana Showing No Data

## Symptom
- Grafana dashboards show "No data" on all panels
- Time range is correct
- This happened after a deploy or restart

## Diagnostic Tree

### Step 1 — Is Grafana itself healthy?
```bash
curl -s https://grafana.dev.hasanali.uk/api/health | jq .
```
Should return `{"commit":"...","database":"ok","version":"..."}`.

If Grafana is down check ECS:
```bash
aws ecs describe-services \
  --cluster ecs-combined-prod \
  --services ecs-combined-prod-grafana \
  --region eu-west-2 \
  --query "services[0].{Desired:desiredCount,Running:runningCount}"
```

### Step 2 — Is Prometheus scraping?
Go to `https://prometheus.dev.hasanali.uk/targets`

All targets should show **UP** in green. If any are **DOWN**:
- Check the ECS service for that target is running
- Check security groups allow Prometheus to reach the service on the metrics port

### Step 3 — Is the datasource configured?
In Grafana → Configuration → Data Sources → Prometheus → Test.
Should say "Data source is working".

If it fails, check the Prometheus URL is `http://prometheus:9090` (internal DNS).

### Step 4 — Is it a query issue?
Open a dashboard panel → Edit → go to the Query tab.
Run the query manually in Prometheus to see if it returns data.

Common issues:
- Metric name changed after a code deploy
- Label names changed (e.g. `status_code` vs `status`)
- Time range set to a period before the service existed

### Step 5 — Did Grafana lose its state?
Grafana stores dashboards and datasources on EFS. If EFS mount failed:
```bash
aws ecs describe-tasks \
  --cluster ecs-combined-prod \
  --tasks $(aws ecs list-tasks \
    --cluster ecs-combined-prod \
    --service-name ecs-combined-prod-grafana \
    --query "taskArns[0]" --output text) \
  --region eu-west-2 \
  --query "tasks[0].containers[0].reason"
```

If EFS mount failed, check the EFS security group allows NFS (port 2049) from the Grafana task security group.

## Recovery
If Grafana state is lost, dashboards are provisioned from JSON files in the repo — they will be automatically restored on next task start. Datasources are also provisioned from config. No manual intervention needed.