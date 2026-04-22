#!/bin/bash
set -euo pipefail

REGION="eu-west-2"
ACCOUNT="989346120260"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
PROJECT="ecs-combined"
SHA=$(git rev-parse --short HEAD)

echo "==> Logging in to ECR"
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $REGISTRY

echo "==> Building and pushing with tag: $SHA"

for svc in api worker dashboard; do
  echo ""
  echo "==> Building $svc..."
  docker build \
    --platform linux/amd64 \
    -f docker/${svc}.Dockerfile \
    -t ${REGISTRY}/${PROJECT}/${svc}:${SHA} \
    .

  echo "==> Pushing $svc..."
  docker push ${REGISTRY}/${PROJECT}/${svc}:${SHA}
  echo "==> Done: ${REGISTRY}/${PROJECT}/${svc}:${SHA}"
done

echo ""
echo "==> All images pushed with tag: $SHA"
echo "==> To deploy run:"
echo "    SHA=$SHA ./scripts/deploy-services.sh dev"