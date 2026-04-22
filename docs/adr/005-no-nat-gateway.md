# ADR-005: No NAT Gateway

## Status
Accepted

## Context
ECS Fargate tasks run in private subnets and need to reach AWS services:
- ECR (pull images)
- Secrets Manager (fetch secrets at startup)
- CloudWatch Logs (ship logs)
- SQS (publish/consume events)
- KMS (decrypt secrets)
- SSM (Session Manager access)

Two options:
1. **NAT Gateway** — simple, routes all outbound traffic through a managed NAT
2. **VPC Interface Endpoints** — private connectivity to each AWS service

## Decision
VPC Interface Endpoints for all required AWS services. No NAT gateways.

## Endpoints Created
| Endpoint | Type | Purpose |
|---|---|---|
| ecr.api | Interface | ECR authentication |
| ecr.dkr | Interface | ECR image pulls |
| s3 | Gateway | ECR layer storage, ALB logs |
| secretsmanager | Interface | Secret injection at startup |
| logs | Interface | CloudWatch log shipping |
| sqs | Interface | Click event queue |
| kms | Interface | Secret decryption |
| ssm | Interface | Session Manager |
| ssmmessages | Interface | Session Manager |
| ec2messages | Interface | Session Manager |
| sts | Interface | IAM role assumption |
| monitoring | Interface | CloudWatch metrics |

## Cost Comparison
| Option | Monthly Cost (eu-west-2) |
|---|---|
| NAT Gateway (1 AZ) | ~$35/month + data transfer |
| NAT Gateway (3 AZs) | ~$105/month + data transfer |
| VPC Interface Endpoints (12) | ~$84/month flat |

At low data transfer volumes endpoints are slightly more expensive.
At high data transfer volumes endpoints are significantly cheaper.

## Consequences
**Positive:**
- Traffic never leaves the AWS network
- No data transfer charges for AWS service calls
- Better security posture — no internet egress from private subnets

**Negative:**
- Cannot reach non-AWS internet endpoints from private subnets
- Each new AWS service requires a new endpoint
- Interface endpoints cost ~$7/month each regardless of usage
- More complex VPC configuration

## Operational Impact
If a task needs to reach a non-AWS endpoint (e.g. a third-party webhook),
a NAT gateway must be added or the call must be proxied through a Lambda
in a public subnet. This is a deliberate constraint — it forces all
external calls to be explicit and auditable.