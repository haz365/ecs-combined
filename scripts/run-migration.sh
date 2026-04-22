#!/bin/bash
# Runs Flyway migrations as a one-off ECS task before service deploy
# Usage: ./scripts/run-migration.sh dev

set -euo pipefail

ENV=${1:-dev}
REGION="eu-west-2"
PROJECT="ecs-combined"
CLUSTER="${PROJECT}-${ENV}"

echo "==> Running migrations for environment: $ENV"

# Get DB connection details from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${PROJECT}/${ENV}/rds/password" \
  --region $REGION \
  --query SecretString \
  --output text)

DB_HOST=$(echo $SECRET | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])")
DB_PORT=$(echo $SECRET | python3 -c "import json,sys; print(json.load(sys.stdin)['port'])")
DB_NAME=$(echo $SECRET | python3 -c "import json,sys; print(json.load(sys.stdin)['dbname'])")
DB_USER=$(echo $SECRET | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")
DB_PASS=$(echo $SECRET | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")

echo "==> DB host: $DB_HOST"

# Run Flyway via Docker
docker run --rm \
  -v "$(pwd)/migrations:/flyway/sql" \
  flyway/flyway:10 \
  -url="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require" \
  -user="$DB_USER" \
  -password="$DB_PASS" \
  -locations="filesystem:/flyway/sql" \
  migrate

echo "==> Migrations complete"