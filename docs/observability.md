# Observability signal catalog

## Scope and safety boundary

This repository instruments the transaction API and provisions some AWS metric
sources through Terraform. It does **not** deploy a log shipper, OpenTelemetry
collector, dashboards, or CloudWatch alarms. Those production integrations are
P3 work and must be operated by the platform owner.

The corresponding CloudTrail, GuardDuty, Security Hub and WAF-log detection
strategy is documented in `docs/cloud-security-operations.md`. It is also a
design only: no audit trail, finding aggregator, log destination or SOC routing
is provisioned by this repository.

Secrets Manager is the source of truth for credentials. Secret values mounted by
the AWS Secrets Store CSI driver, payment-provider credentials, transaction IDs,
idempotency keys, provider references, amounts, currencies, request/response
bodies, and rejection reasons are prohibited from logs, metrics, and traces.

## Application signals

| Signal | Type | Dimensions / fields | Purpose | Safety |
| --- | --- | --- | --- | --- |
| `payment.provider.requests` | Counter | `outcome`: `approved`, `rejected`, `http_error`, `unavailable`, `invalid_response` | Provider availability and business-result rate | No transaction or provider identifiers |
| `payment.provider.request.duration` | Timer | Same bounded `outcome` | Provider latency by result class | No request payload or URL |
| `payment_provider_request_completed` | Structured log event | `traceId` MDC field, `outcome` | Correlate a provider attempt to the inbound request | No exception stack, status body, or financial fields |
| `X-Correlation-ID` | Response header / MDC `traceId` | UUID only; supplied valid UUID is echoed, otherwise generated | Request-to-log correlation | Header values are validated to avoid log injection |
| `/actuator/health` | Health probe | Overall status only | ALB/Kubernetes liveness and readiness | Component details are disabled |
| `/actuator/metrics` | Actuator metric discovery | Metric names and meter measurements | Restricted operational metric readout | `/actuator/env` and other sensitive endpoints remain unexposed |

Console logs use Spring Boot's Logstash structured JSON format. The emitted
`traceId` is a correlation identifier, not a distributed OpenTelemetry trace;
OTel propagation/export is explicitly deferred to P3.

## AWS and Kubernetes signals

| Source | Signal family | Use | Ownership / status |
| --- | --- | --- | --- |
| Route 53 | DNS health checks and query/health-check metrics | Detect DNS resolution and endpoint-health issues | AWS source; collection/alarms are not created here |
| AWS WAF regional | Allowed/blocked requests, rate-based rule matches | Detect attack traffic and false-positive blocks | Terraform enables WAF CloudWatch metric names; alerts are not created here |
| ALB / ACM | ALB 4xx/5xx, target health, latency, TLS certificate expiry | Detect edge and certificate failures | AWS source; dashboards/alarms are not created here |
| EKS | Control-plane, node, pod, deployment, and container resource signals | Detect cluster/workload health and saturation | EKS source; managed collection is out of repository scope |
| RDS PostgreSQL | CPU, connections, storage, latency, failover events | Detect database capacity and availability risks | RDS source; alarms are not created here |

The AWS Load Balancer Controller and ExternalDNS retain EKS Pod Identity. Any
future telemetry integration must not broaden those roles or use application
secrets as telemetry credentials.

## Operator guidance

Restrict Actuator access to the cluster/operations network; it is not a public
API. Build dashboards and alerts from the catalog above with bounded labels only.
At minimum, page on sustained provider unavailability, ALB unhealthy targets,
RDS resource exhaustion, WAF block surges, and expiring ACM certificates. Tune
thresholds from production baselines before enabling paging.
