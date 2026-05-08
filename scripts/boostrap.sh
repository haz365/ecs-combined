#!/bin/bash
set -euo pipefail

ENV=${1:-dev}
REGION="eu-west-2"
ACCOUNT="989346120260"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
PROJECT="ecs-combined"
CLUSTER="${PROJECT}-${ENV}"

echo "==> Bootstrapping $ENV environment"

# Step 1 - Login to ECR
echo "==> Logging in to ECR"
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $REGISTRY

# Step 2 - Push observability images
echo "==> Pushing observability images"
for img in "prom/prometheus:v2.51.2" "grafana/grafana:10.4.2"; do
  name=$(echo $img | cut -d'/' -f2 | cut -d':' -f1)
  tag=$(echo $img | cut -d':' -f2)
  docker pull $img
  docker tag $img ${REGISTRY}/${PROJECT}/${name}:${tag}
  docker push ${REGISTRY}/${PROJECT}/${name}:${tag}
  echo "==> Pushed ${name}:${tag}"
done

# Step 3 - Build and push app images
echo "==> Building and pushing app images"
SHA=$(git rev-parse --short HEAD)
for svc in api worker dashboard; do
  docker build --platform linux/amd64 \
    -f docker/${svc}.Dockerfile \
    -t ${REGISTRY}/${PROJECT}/${svc}:${SHA} .
  docker push ${REGISTRY}/${PROJECT}/${svc}:${SHA}
  echo "==> Pushed ${svc}:${SHA}"
done

# Step 4 - Deploy all services including observability
echo "==> Deploying app services"
SHA=$SHA ./scripts/deploy-services.sh $ENV

# Step 5 - Deploy prometheus and grafana
echo "==> Deploying observability services"
for svc in prometheus grafana; do
  IMAGE="${REGISTRY}/${PROJECT}/${svc}:$([ "$svc" = "prometheus" ] && echo "v2.51.2" || echo "10.4.2")"

  aws ecs describe-task-definition \
    --task-definition ${PROJECT}-${ENV}-${svc} \
    --region $REGION \
    --query "taskDefinition" \
    --output json > /tmp/task-${svc}.json

  python3 -c "
import json
with open('/tmp/task-${svc}.json') as f:
    td = json.load(f)
td['containerDefinitions'][0]['image'] = '${IMAGE}'
for key in ['taskDefinitionArn','revision','status','requiresAttributes','compatibilities','registeredAt','registeredBy','deregisteredAt']:
    td.pop(key, None)
with open('/tmp/task-${svc}-new.json', 'w') as f:
    json.dump(td, f)
"

  NEW_ARN=$(aws ecs register-task-definition \
    --region $REGION \
    --cli-input-json file:///tmp/task-${svc}-new.json \
    --query "taskDefinition.taskDefinitionArn" \
    --output text)

  aws ecs update-service \
    --cluster $CLUSTER \
    --service ${CLUSTER}-${svc} \
    --task-definition $NEW_ARN \
    --region $REGION \
    --no-cli-pager > /dev/null

  echo "==> Deployed $svc"
done

# Step 6 - Recreate DNS record
echo "==> Updating Route53 DNS"
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names ${PROJECT}-${ENV} \
  --region $REGION \
  --query "LoadBalancers[0].DNSName" \
  --output text)

ALB_ZONE=$(aws elbv2 describe-load-balancers \
  --names ${PROJECT}-${ENV} \
  --region $REGION \
  --query "LoadBalancers[0].CanonicalHostedZoneId" \
  --output text)

aws route53 change-resource-record-sets \
  --hosted-zone-id Z044516511F47YV4NV151 \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"hasanali.uk\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE\",
          \"DNSName\": \"$ALB_DNS\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }" > /dev/null

echo ""
echo "==> Bootstrap complete!"
echo "==> Site live at: https://hasanali.uk"
echo "==> Grafana at: https://hasanali.uk/grafana"