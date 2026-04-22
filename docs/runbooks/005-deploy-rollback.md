# Runbook: Deploy Rolled Back Automatically

## Symptom
- GitHub Actions deploy workflow failed
- ECS circuit breaker triggered automatic rollback
- Slack/email alert: deployment failed for service X

## What Happened
ECS deployment circuit breaker monitors new tasks. If they fail health checks
within the deployment window, ECS automatically rolls back to the previous
task definition revision.

## Investigation Steps

### Step 1 — Find which task definition failed
```bash
aws ecs describe-services \
  --cluster ecs-combined-prod \
  --services ecs-combined-prod-api \
  --region eu-west-2 \
  --query "services[0].{Current:taskDefinition,Deployments:deployments}"
```

The failed deployment will show status `FAILED`.

### Step 2 — Get logs from the failed tasks
```bash
# List stopped tasks from the last hour
aws ecs list-tasks \
  --cluster ecs-combined-prod \
  --service-name ecs-combined-prod-api \
  --desired-status STOPPED \
  --region eu-west-2

# Get stop reason
aws ecs describe-tasks \
  --cluster ecs-combined-prod \
  --tasks <task-arn> \
  --region eu-west-2 \
  --query "tasks[0].{StopCode:stopCode,StoppedReason:stoppedReason}"
```

### Step 3 — Check CloudWatch logs for the failed task
```bash
aws logs tail /ecs/ecs-combined-prod/api \
  --since 30m \
  --region eu-west-2
```

### Common Root Causes

**Bad DB migration** — migration ran but is incompatible with new code
- Check migration logs
- If migration cannot be rolled back, fix forward with a new migration

**Missing environment variable** — new code references an env var not in task definition
- Check the logs for `KeyError` or missing env var errors
- Add the variable to Terraform and redeploy

**Image failed to start** — application crash on startup
- Check logs for stack traces
- Test the image locally: `docker run --env-file .env.local <image>`

**Health check path changed** — code changed `/health` to something else
- Update the target group health check path in Terraform

### Step 4 — Fix and redeploy
Once root cause is identified:
1. Fix the code or config
2. Push to main — CI will build and deploy automatically
3. Monitor the deployment in GitHub Actions and Grafana

### If You Need to Manually Deploy a Specific SHA
Go to GitHub Actions → Deploy to ECS → Run workflow → enter the known-good SHA.