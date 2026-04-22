# Runbook: SQS Queue Depth Climbing

## Symptom
- Alert firing: SQS queue depth > 1000 for 10 minutes
- Grafana business metrics showing click events not being processed
- `worker_messages_processed_total` rate dropping to zero

## Dashboards to Check First
1. **Business Metrics** → SQS Worker In-flight
2. **Service Health** → Worker Messages Processed/s
3. **Infrastructure** → ECS CPU/Memory for worker service

## Likely Causes and Remediation

### 1. Worker service is down
**Check:**
```bash
aws ecs describe-services \
  --cluster ecs-combined-prod \
  --services ecs-combined-prod-worker \
  --region eu-west-2 \
  --query "services[0].{Desired:desiredCount,Running:runningCount}"
```

**Fix:** If running count is 0, check logs and force redeploy:
```bash
aws logs tail /ecs/ecs-combined-prod/worker --follow --region eu-west-2
aws ecs update-service \
  --cluster ecs-combined-prod \
  --service ecs-combined-prod-worker \
  --force-new-deployment \
  --region eu-west-2
```

### 2. Worker is running but RDS is slow
**Symptoms:** Worker logs show slow DB inserts, `worker_message_processing_duration_seconds` p95 > 1s

**Fix:** Check RDS CPU and connections. Scale up RDS instance class if needed.

### 3. Messages stuck in flight
**Symptoms:** Queue depth high but `ApproximateNumberOfMessagesNotVisible` also high

**Fix:** Visibility timeout may be too low. Messages are being received but not processed in time:
```bash
# Check in-flight messages
aws sqs get-queue-attributes \
  --queue-url https://sqs.eu-west-2.amazonaws.com/989346120260/ecs-combined-prod-click-events \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible \
  --region eu-west-2
```

### 4. Traffic spike — worker needs scaling
**Fix:** Scale up worker desired count:
```bash
aws ecs update-service \
  --cluster ecs-combined-prod \
  --service ecs-combined-prod-worker \
  --desired-count 3 \
  --region eu-west-2
```

## Checking the DLQ
If messages are appearing in the DLQ, they failed processing 5 times:
```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.eu-west-2.amazonaws.com/989346120260/ecs-combined-prod-click-events-dlq \
  --attribute-names ApproximateNumberOfMessages \
  --region eu-west-2
```

Inspect a DLQ message to understand why it failed before redriving.