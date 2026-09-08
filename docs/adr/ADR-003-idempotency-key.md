# ADR-003: Idempotency-Key Header for Safe Retries

**Status:** Accepted
**Date:** 2026-09-08
**Author:** Engineering & Security Lead

---

## Context

Clients communicating over unreliable networks may not receive a response even when the server has successfully processed the request. Without a deduplication mechanism, a client retry after a network timeout would submit an identical transaction twice, potentially causing a double-charge. This is a critical correctness problem in any payment-processing system.

---

## Decision

Accept an optional `Idempotency-Key` HTTP header on transaction submission.

Implementation:
- The key is persisted alongside the transaction record in PostgreSQL with a `UNIQUE` constraint on the `idempotency_key` column.
- On duplicate key receipt, the service returns the previously stored transaction result without re-executing business logic or calling the external provider.
- The key is client-generated (UUID recommended) and must be unique per logical operation.
- Keys are stored indefinitely in the current implementation; a TTL-based expiry policy is a future improvement.

---

## Consequences

**Positive:**
- Prevents double-charging on client retry: safe retries are a first-class guarantee.
- The UNIQUE constraint at the database level provides a strong, race-condition-free deduplication backstop.
- Aligns with industry standards (Stripe, Adyen, and most payment APIs implement the same pattern).

**Negative / Known Gaps:**
- **Does not cover the ambiguous-state scenario:** if the external payment provider successfully executed the charge but the application crashed before persisting the transaction and its idempotency key, a subsequent retry with the same key will re-execute the provider call, potentially resulting in a duplicate charge at the provider level. This gap requires a **reconciliation job** (roadmap item) that detects unacknowledged provider executions and resolves their state.
- The idempotency key is optional; clients that do not provide one have no retry safety.
- Key expiry and storage growth are not addressed in the initial implementation.

> **Important:** The Idempotency-Key is a retry-safety mechanism, not a substitute for reconciliation. The known gap above is explicitly documented here to drive the reconciliation roadmap item.

---

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| **Request fingerprinting (hash of body fields)** | Brittle — minor payload variations produce different hashes; clients lose control over deduplication scope |
| **Rely on provider's own idempotency** | Does not protect against duplicates introduced before the provider call; also provider-specific, reducing portability |
| **No deduplication (accept duplicate risk)** | Unacceptable for a financial transaction service |
