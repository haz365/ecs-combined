# ADR-001: Database Choice

## Status
Accepted

## Context
The URL shortener needs to store two types of data:
- URL mappings (short code → original URL) — read-heavy, low latency required
- Click analytics (events, aggregates) — write-heavy, query flexibility needed

We evaluated PostgreSQL, DynamoDB, and MySQL.

## Decision
PostgreSQL on RDS with Multi-AZ in staging and prod.

Reasons:
- URL mappings and click analytics share a natural relational structure
- `ON CONFLICT DO UPDATE` (upsert) simplifies the shorten endpoint
- Window functions and `date_trunc` make hourly analytics queries trivial
- RDS handles backups, failover, and patching operationally
- The team already knows SQL

## Consequences
**Positive:**
- Single data store, simple operational model
- Rich query capabilities for analytics without a separate warehouse
- Multi-AZ gives automatic failover with ~60s RTO

**Negative:**
- Vertical scaling limit — at 10x scale we would shard or move analytics to a columnar store (Redshift, ClickHouse)
- Connection pooling becomes critical at high concurrency — would add PgBouncer at scale
- RDS is more expensive than DynamoDB at low traffic

## At 10x Scale
- Separate the analytics write path into its own PostgreSQL instance or migrate to ClickHouse
- Add PgBouncer as a connection pooler in front of RDS
- Consider read replicas for the dashboard service
- Evaluate Aurora Serverless v2 for auto-scaling storage and compute