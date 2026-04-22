#!/bin/bash
set -euo pipefail

ENV=${1:-dev}
SHA=${SHA:-$(git rev-parse --short HEAD)}
REGION="eu-west-2"
ACCOUNT="989346120260"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
PROJECT="ecs-combined"
CLUSTER="${PROJECT}-${ENV}"

echo "==> Deploying SHA: $SHA to environment: $ENV"

for svc in api worker dashboard; do
  echo ""
  echo "==> Updating $svc..."

  # Get current task definition
  TASK_DEF=$(aws ecs describe-services \
    --cluster $CLUSTER \
    --services ${CLUSTER}-${svc} \
    --region $REGION \
    --query "services[0].taskDefinition" \
    --output text)

  echo "    Current task def: $TASK_DEF"

  # Download and update image
  aws ecs describe-task-definition \
    --task-definition $TASK_DEF \
    --region $REGION \
    --query "taskDefinition" \
    --output json > /tmp/task-${svc}.json

  NEW_IMAGE="${REGISTRY}/${PROJECT}/${svc}:${SHA}"

  python3 -c "
import json
with open('/tmp/task-${svc}.json') as f:
    td = json.load(f)
td['containerDefinitions'][0]['image'] = '${NEW_IMAGE}'
for key in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy']:
    td.pop(key, None)
with open('/tmp/task-${svc}-new.json', 'w') as f:
    json.dump(td, f)
"

  # Register new revision
  NEW_ARN=$(aws ecs register-task-definition \
    --region $REGION \
    --cli-input-json file:///tmp/task-${svc}-new.json \
    --query "taskDefinition.taskDefinitionArn" \
    --output text)

  echo "    New task def: $NEW_ARN"

  # Update service
  aws ecs update-service \
    --cluster $CLUSTER \
    --service ${CLUSTER}-${svc} \
    --task-definition $NEW_ARN \
    --region $REGION \
    --no-cli-pager > /dev/null

  echo "    Deployed $svc"
done

echo ""
echo "==> All services updated. Waiting for stability..."

aws ecs wait services-stable \
  --cluster $CLUSTER \
  --services ${CLUSTER}-api ${CLUSTER}-worker ${CLUSTER}-dashboard \
  --region $REGION

echo "==> Done. All services stable."