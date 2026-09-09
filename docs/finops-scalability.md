# FinOps and scalability baseline

## Scope and assumptions

This is a capacity-planning baseline, not an AWS bill or a claim that the
environment has been provisioned. Prices vary by region, usage, commitments,
data transfer and AWS price changes; estimate them with the AWS Pricing
Calculator using the production region and observed volumes before approval.

The baseline is a public, synchronous transaction API with PostgreSQL as the
system of record. It assumes a modest initial production load, a two-AZ VPC,
three API replicas, and one managed EKS node group sized to carry the API plus
the required platform add-ons. Transaction execution must remain idempotent;
scaling application pods never makes the database or payment provider
infinitely scalable.

## Why EKS despite its cost

EKS is deliberately **not** selected as the cheapest way to run one API. ECS
Fargate is the lower-operations, lower-baseline-cost option for a single
service without Kubernetes expertise. EKS is justified here by the security
and platform requirements already represented in this repository: NetworkPolicy,
Pod Security settings, Kyverno admission policies, Helm-based delivery, AWS
Load Balancer Controller, ExternalDNS, and EKS Pod Identity. This lets the
team enforce and audit the same Kubernetes controls across future workloads.

The decision must be revisited if the platform remains a single low-volume
service or the team cannot operate EKS add-ons and upgrades. In that case,
move the workload to ECS Fargate rather than retaining EKS for demonstration
value alone. ADR-004 records the corresponding architectural trade-off.

## Cost drivers and controls

| Component | Baseline / driver | Control and review trigger |
| --- | --- | --- |
| EKS | Fixed cluster control-plane fee plus EC2 worker capacity, EBS, and add-ons. Requests, not limits, determine bin-packing. | Start with the current 2-node on-demand group and right-size from 14 days of CPU/memory percentiles. Review when requested capacity exceeds 70% of allocatable capacity or pods remain pending. Use committed compute only after stable utilization is proven. |
| API pods | Production requests are 500m CPU / 1 GiB per pod; CPU limit is 1 vCPU and memory limit 2 GiB. Three replicas reserve 1.5 vCPU / 3 GiB before add-ons. | Keep requests at approximately P95 observed usage plus headroom. Lower chronic over-requesting; raise memory requests after OOM/restart evidence. Do not set CPU limits so low that throttling invalidates latency measurements. |
| RDS PostgreSQL | Instance-hours, Multi-AZ standby, storage, I/O, backups and log export. Current `db.t4g.medium`, Multi-AZ, 20–100 GiB autoscaling storage is an availability-first baseline. | Review CPU, free memory, connections, read/write latency, storage growth and backup retention weekly. Increase class or storage before sustained saturation; add read replicas only for measured read pressure. Connection limits must be budgeted across maximum API replicas and pool size. |
| NAT gateway | Hourly gateway charge and per-GB processing. The current single NAT is low-cost but is a cross-AZ availability and transfer-cost trade-off. | Production should use one NAT per AZ when availability needs justify it. First add gateway/interface VPC endpoints for high-volume AWS traffic (for example S3, ECR API/DKR, STS, CloudWatch Logs and Secrets Manager where applicable), then compare remaining NAT GB and cross-AZ traffic. |
| ALB, Route 53, ACM and WAF | ALB hours/LCUs, DNS zones/queries, WAF Web ACL/rules/requests and logging destination. ACM public certificates have no certificate fee; logs can dominate at high volume. | Keep WAF managed/rate rules minimal and intentional; review LCU dimensions and WAF request/rule counts monthly. Sample/redact and retain WAF/ALB/application logs according to the approved retention policy, not indefinitely. |
| Observability | CloudWatch metric, ingestion, retention, query, trace and alarm charges grow with cardinality and volume. | Use the bounded-cardinality signals in `docs/observability.md`; exclude secrets and unbounded identifiers. Set retention per log class and alert on ingestion anomalies. |

Secrets Manager, AWS Load Balancer Controller, ExternalDNS and EKS Pod Identity
are part of the approved baseline. External Secrets Operator and
customer-managed KMS keys are intentionally out of scope and must not be
silently added to estimates.

## Scaling policy and guardrails

The Helm chart uses an HPA with production bounds of 3–20 replicas and a 60%
CPU target. That target is only a starting hypothesis: validate it under a
representative load test after metrics-server and capacity provisioning are
present. Pair the HPA with node capacity scaling; HPA alone cannot schedule a
pod onto a full node group.

Before increasing `maxReplicas`, calculate the database connection ceiling:

`maximum API replicas × Hikari maximumPoolSize + admin/migration reserve < RDS max connections`

Set a conservative Hikari pool explicitly for the chosen RDS class, reserve
connections for operations and migrations, and load-test provider latency.
Back-pressure, timeouts and circuit breaking are preferred to unlimited pools
or uncontrolled retries. PDB `minAvailable: 2` protects a three-replica
production deployment during voluntary disruptions; revisit it together with
replica count and availability objectives.

Capacity reviews use p95/p99 latency, error rate, CPU throttling, memory
working set/OOMs, HPA desired-vs-current replicas, pending pods, node
allocatable/requested resources, RDS connections/latency/storage and NAT/WAF/
log volume. A change is accepted only when it improves a measured bottleneck
without breaching the database or provider budgets.

## Data and asynchronous evolution

The transaction history endpoint already uses deterministic keyset pagination
(`createdAt DESC, id DESC`) and has a matching database index. Keep it instead
of offset pagination as the table grows: it avoids progressively scanning and
discarding earlier pages and is stable when new transactions arrive.

Kafka is not a baseline dependency. Introduce it only when measured coupling
between the synchronous transaction path and downstream side effects causes
latency, availability or throughput failures. Use an outbox pattern, idempotent
consumers, schema/version governance, retention and replay/runbook ownership;
otherwise Kafka adds operational cost and failure modes without solving a
current constraint.

## Decision checkpoints

| When | Decision |
| --- | --- |
| Before production | Pricing Calculator estimate, load test, RDS connection budget, log retention, NAT endpoint analysis and an owner for EKS upgrades/add-ons. |
| At sustained 60–70% utilization or latency SLO risk | Right-size pod requests/nodes and RDS from measurements; do not scale replicas blindly. |
| At AZ availability requirement | Move from the single development NAT to NAT per AZ and validate endpoint coverage/egress paths. |
| At material read volume or history growth | Re-check index/query plans, partitioning/archive policy and read-replica economics. |
| At asynchronous side-effect pressure | Evaluate outbox + Kafka only with a quantified SLO/cost case and operational owner. |
