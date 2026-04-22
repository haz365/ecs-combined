# ADR-004: Secrets Management

## Status
Accepted

## Context
The system handles several secrets:
- RDS password
- Redis auth token
- Any future API keys

Three options were evaluated:
1. **AWS Secrets Manager** — managed service, automatic rotation, native ECS integration
2. **AWS SSM Parameter Store** — cheaper, no automatic rotation for DB passwords
3. **HashiCorp Vault** — most powerful, highest operational burden

## Decision
AWS Secrets Manager with automatic rotation for the RDS password.

## Reasoning
- ECS task definitions support native Secrets Manager injection via the `secrets` block
- Containers never see plaintext secrets — they are injected as environment variables at task start
- Automatic rotation via the managed Lambda rotation function requires zero custom code
- Secrets Manager integrates with KMS CMKs for encryption at rest
- Cost is $0.40/secret/month — negligible

SSM Parameter Store was rejected because:
- No managed rotation for RDS passwords
- SecureString parameters have lower throughput limits

Vault was rejected because:
- Requires running and operating a Vault cluster
- Adds ~$50-100/month in infrastructure
- Overkill for a single-team project

## Consequences
**Positive:**
- Zero long-lived credentials in code, images, or environment variables
- Automatic 30-day rotation for RDS password
- Audit trail via CloudTrail

**Negative:**
- $0.40/secret/month cost
- Slight task startup latency as secrets are fetched
- If Secrets Manager endpoint is unavailable, tasks cannot start

## Secret Hygiene Rules
1. Never log secret values
2. Never pass secrets as build args in Dockerfiles
3. Verify with `docker history` that no secrets are baked into image layers
4. Rotate manually if a secret is suspected compromised