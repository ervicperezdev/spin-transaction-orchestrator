# Architecture

## Current implementation

The service is a Java 21 / Spring Boot REST API with PostgreSQL persistence.
It follows a ports-and-adapters structure:

```text
HTTP REST controller -> application use cases -> domain model
                                  |                    |
                         repository/provider ports     |
                                  |                    |
                    JPA/PostgreSQL and HTTP provider adapters
```

- `domain`: transaction state and validation rules, without framework imports.
- `application`: commands, queries, use cases and inbound/outbound ports.
- `adapter/in/rest`: request mapping, validation, error mapping and OpenAPI annotations.
- `infrastructure`: Spring wiring, JPA/Flyway persistence and the HTTP payment-provider adapter.

The synchronous write path is: validate request, look up an optional idempotency
key, call the configured provider, transition the transaction to `APPROVED` or
`REJECTED`, then persist it. `GET /transactions` reads a deterministic page
(created time descending, then id descending).

## Deployment intent vs. present evidence

The repository contains Helm templates, Kyverno policies, Terraform and GitHub
Actions workflow definitions. They are deployable artifacts, not evidence that
an AWS account, EKS cluster, WAF, RDS instance, monitoring stack or admission
controller is currently running. Those environment controls must be verified
at deployment time.

The container image is built from a Maven stage and runs the packaged JAR as the
distroless image's `nonroot` user. Helm also declares probes, resource values,
a security context, AWS Secrets Store CSI `SecretProviderClass`, and
NetworkPolicy templates.

## Decision records

The rationale for the major choices is in `docs/adr/`:

- ADR-001 — ports and adapters.
- ADR-002 — PostgreSQL and exact decimal storage.
- ADR-003 — client-provided idempotency keys.
- ADR-004 — EKS as the intended Kubernetes deployment option.
- ADR-005 — retry/circuit-breaker policy is a roadmap decision, not current code.
