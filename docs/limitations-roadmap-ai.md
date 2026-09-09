# Limitations, roadmap and AI use

## Current limitations

- The API has no authentication or authorization. It is suitable only for a
  controlled demo/local environment until an identity boundary is implemented.
- The configured payment provider is an external dependency; the repository
  supplies its HTTP contract but no local provider simulator.
- Idempotency is optional. A duplicate key returns a stored transaction, but a
  provider call that succeeds before the application persists the result remains
  an ambiguous state and can still lead to a duplicate external operation.
- Provider calls use configured connection/read timeouts. No retry, circuit
  breaker, reconciliation worker, audit trail, metrics export, or alerting is
  implemented in the application.
- The PostgreSQL Docker Compose credentials are development-only defaults.
  They must not be reused outside local development.

## Prioritized roadmap

1. Add OAuth2/JWT authentication, authorization policy and an audit event model.
2. Persist an operation/outbox record before provider interaction and build a
   reconciliation process for ambiguous provider outcomes.
3. Add provider-specific idempotency propagation, safe retry classification,
   circuit breaking and operational metrics/alerts.
4. Provision and verify the AWS/EKS/RDS controls represented by the IaC and
   Helm artifacts, including TLS, NetworkPolicy enforcement, IRSA and secrets
   rotation.
5. Add contract testing with a provider simulator and production readiness
   testing (backup/restore, load, failure and incident exercises).

## Use of AI

AI assistance was used to accelerate drafting and reviewing documentation and
code changes. It is not an authority for security, financial correctness or
production readiness. Repository tests, human review, dependency scanning and
environment-specific validation remain required before release. No credentials,
customer data or production transaction data should be supplied to AI tools.
