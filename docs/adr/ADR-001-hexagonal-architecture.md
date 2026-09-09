# ADR-001: Hexagonal Architecture (Ports & Adapters)

**Status:** Accepted
**Date:** 2026-09-08
**Author:** Engineering & Security Lead

---

## Context

The transaction orchestrator needs to remain maintainable and independently testable as infrastructure adapters evolve. Business rules — such as idempotency enforcement, amount validation, and transaction state transitions — must not be coupled to framework-specific concerns like JPA annotations, Spring HTTP types, or AWS SDK calls. Coupling business logic to infrastructure makes security-sensitive rules harder to audit, test in isolation, and evolve safely.

---

## Decision

Adopt **Hexagonal Architecture (Ports & Adapters)** as the structural pattern for the service.

Structure:
- `domain/` — pure Java domain model; no framework dependencies
- `application/` — use-case services and port interfaces; no JPA, no HTTP, no AWS
- `adapter/in/` — inbound adapters (REST controller, consumers)
- `adapter/out/` — outbound adapters (JPA persistence, provider HTTP client)
- `infrastructure/` — Spring Boot wiring, configuration, Flyway migrations

Ports are Java interfaces defined in `application/port/`; adapters implement them. The application core never imports from adapter or infrastructure packages.

---

## Consequences

**Positive:**
- Domain and application layers are framework-agnostic and trivially unit-testable without a running Spring context.
- Security-critical business logic (idempotency, validation, state machine) is isolated and auditable independently of HTTP or database concerns.
- Adapters can be swapped (e.g., replace the HTTP provider client with a message queue consumer) without touching business rules.

**Negative:**
- Minor boilerplate overhead: every inbound call requires mapping from DTO → Command → Domain model → Entity and back.
- Stricter package discipline must be enforced via ArchUnit tests or manual review to prevent dependency leaks.

---

## Alternatives Considered

| Alternative | Reason Rejected |
|---|---|
| **Layered (N-tier) architecture** | Business logic tends to leak into service or repository layers over time; harder to enforce isolation in a security-sensitive context |
| **CQRS (Command Query Responsibility Segregation)** | Adds read-model complexity not justified by the current single-service, single-database scope; can be adopted later if read scaling becomes a concern |
