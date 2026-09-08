# ADR-005: Resilience4j Retry and Circuit Breaker Strategy

**Status:** Accepted
**Date:** 2026-09-08
**Author:** Engineering & Security Lead

---

## Context

The transaction orchestrator calls an external payment provider over HTTPS. The provider can be temporarily unavailable (transient network errors, brief maintenance) or permanently reject a request (invalid input, authentication failure). Naive retry logic risks two critical failure modes:

1. **Duplicate financial operations:** retrying a timed-out request when the provider may have already executed it.
2. **Provider saturation:** retrying aggressively during a provider outage amplifies load, worsening recovery.

The retry strategy must distinguish between error classes where retry is safe, ambiguous, or forbidden.

---

## Decision

Use **Resilience4j** for timeout, retry, and circuit breaker controls on all outbound provider calls.

### Configuration

**Timeouts:**
- Connect timeout: 2 seconds
- Read timeout: 3 seconds

Rationale: payment APIs should respond within milliseconds to low single-digit seconds. Longer waits hold a thread and a DB connection open unnecessarily.

**Circuit Breaker:**
- Failure rate threshold: 50% (over a sliding window of 10 calls)
- Wait duration in OPEN state: 10 seconds before moving to HALF_OPEN
- Half-open permitted calls: 3 (probe calls before deciding to CLOSE or stay OPEN)

**Retry policy — explicit error classification:**

| Error Type | Retry? | Rationale |
|---|---|---|
| Connection refused / network unreachable | Yes (up to 2 retries) | Provider was not reached; no financial operation occurred |
| HTTP 503 Service Unavailable | Yes (up to 2 retries) | Provider explicitly signals transient unavailability |
| Read timeout | **NO** | Provider may have processed the request; retrying risks double-charge |
| HTTP 4XX (400, 409, 422) | **NO** | Functional rejection; the provider evaluated the request and refused it; retry will not change the outcome |
| HTTP 5XX (other than 503) | **NO** | Ambiguous server-side error; retry without reconciliation is unsafe |

Retry backoff: exponential with jitter, base 500 ms.

---

## Consequences

**Positive:**
- Circuit breaker prevents cascading failure: once the provider is determined unhealthy, calls fast-fail immediately instead of exhausting the thread pool.
- Explicit no-retry on timeout forces the reconciliation design to be addressed rather than hidden behind optimistic retries.
- No-retry on 4XX reduces unnecessary load and avoids masking bugs in request construction.

**Negative / Known Gaps:**
- Explicit non-retry on timeout means timed-out calls surface as errors to the caller. Clients must handle these as potentially-ambiguous states and use the `Idempotency-Key` on retry.
- This strategy does not resolve the ambiguous-state problem — it makes it visible. A **reconciliation job** (roadmap) is required to detect and resolve provider-executed-but-not-persisted transactions.

---

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| **Retry on all errors including timeout** | Unacceptable double-charge risk; hides the reconciliation gap |
| **No retry at all** | Causes unnecessary failures on clearly transient errors (connection refused, 503) where no financial operation occurred |
| **Spring Retry** | Less expressive circuit breaker and rate limiter support compared to Resilience4j; weaker observability integration |
