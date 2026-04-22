#!/bin/bash
# Tears down an environment cleanly leaving no billable resources
# Usage: ./scripts/teardown.sh dev

set -euo pipefail

ENV=${1:-dev}
REGION="eu-west-2"
PROJECT="ecs-combined"

echo "==> Tearing down environment: $ENV"

# Clear ECR images first to allow repo deletion
for repo in api worker dashboard; do
  echo "==> Clearing ECR: ${PROJECT}/${repo}"
  IMAGES=$(aws ecr list-images \
    --repository-name ${PROJECT}/${repo} \
    --region $REGION \
    --query 'imageIds' \
    --output json 2>/dev/null || echo "[]")

  if [ "$IMAGES" != "[]" ] && [ "$IMAGES" != "null" ]; then
    aws ecr batch-delete-image \
      --repository-name ${PROJECT}/${repo} \
      --region $REGION \
      --image-ids "$IMAGES" \
      --no-cli-pager
  fi
done

# Run terraform destroy
echo "==> Running terraform destroy for $ENV"
cd infra/environments/$ENV
terraform destroy -var-file=terraform.tfvars -auto-approve

echo "==> Teardown complete for $ENV"
echo "==> Verify no billable resources remain:"
echo "    aws ecs list-clusters --region $REGION"
echo "    aws rds describe-db-instances --region $REGION"
echo "    aws elasticache describe-replication-groups --region $REGION"