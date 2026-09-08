# ADR-002: PostgreSQL over NoSQL for Transaction Storage

**Status:** Accepted
**Date:** 2026-09-08
**Author:** Engineering & Security Lead

---

## Context

Financial transactions are the core domain entity of this service. The storage layer must guarantee correctness properties that are non-negotiable in a fintech context: atomic writes (a transaction either persists completely or not at all), durable storage, precise monetary arithmetic, and the ability to enforce uniqueness constraints (idempotency key). The choice of database engine directly impacts the integrity of every financial record.

---

## Decision

Use **PostgreSQL** (deployed as Amazon RDS) as the primary data store.

Key implementation choices:
- Monetary amounts stored as `NUMERIC(19,2)` — never `FLOAT` or `DOUBLE`, which introduce binary floating-point rounding errors unacceptable in financial calculations.
- `BigDecimal` used throughout the Java domain model; never `double` or `float`.
- `idempotency_key` column carries a `UNIQUE` constraint enforced at the database level, preventing duplicates even under concurrent retries.
- RDS deployed in a private subnet with Multi-AZ standby for high availability.
- Flyway manages all schema migrations with version-controlled SQL scripts reviewed in PRs.

---

## Consequences

**Positive:**
- Full ACID guarantees: concurrent transaction writes are safe from partial-write anomalies.
- `NUMERIC(19,2)` eliminates floating-point precision errors — critical for regulatory compliance and customer trust.
- Mature tooling: Flyway migrations, JPA/Hibernate, RDS snapshots, point-in-time recovery.
- UNIQUE constraint on `idempotency_key` enforces deduplication at the storage layer as a last line of defense.

**Negative:**
- Vertical scaling limits compared to horizontally-sharded NoSQL stores; mitigated by RDS Multi-AZ and read replicas.
- Schema migrations require coordination and careful review; Flyway enforces ordering but not correctness of SQL logic.

---

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| **Amazon DynamoDB** | No multi-item ACID transactions in the general case (DynamoDB Transactions exist but add complexity); eventual consistency model requires additional application-level conflict resolution |
| **MongoDB** | Document schema flexibility is not needed here; ACID multi-document transactions added in v4.0 but less battle-tested than PostgreSQL for financial workloads; no native `NUMERIC` equivalent to prevent floating-point errors |
