# ADR-004: Amazon EKS over ECS Fargate

**Status:** Accepted
**Date:** 2026-09-08
**Author:** Engineering & Security Lead

---

## Context

The transaction orchestrator must be deployed on a container orchestration platform. Two primary options exist within the AWS ecosystem: Amazon EKS (managed Kubernetes) and Amazon ECS (with Fargate). The choice affects operational complexity, security controls expressiveness, and the breadth of platform engineering capabilities that can be demonstrated.

---

## Decision

Deploy on **Amazon EKS** with managed node groups.

The primary driver for this context is the ability to demonstrate the full breadth of Kubernetes security controls:
- `NetworkPolicy` for pod-level traffic segmentation (deny-all default, explicit allow rules)
- `PodSecurityContext` with `runAsNonRoot`, `readOnlyRootFilesystem`, `seccompProfile: RuntimeDefault`
- **Kyverno** admission controller enforcing cluster-wide security policies (block privileged pods, enforce image pull policy, require resource limits)
- **IRSA** (IAM Roles for Service Accounts) for least-privilege AWS API access without node-level credentials
- **Helm** for reproducible, version-controlled deployments
- **HPA** (Horizontal Pod Autoscaler) for load-driven scaling

---

## Consequences

**Positive:**
- Full Kubernetes security primitive surface: NetworkPolicy, Pod Security Admission, Kyverno, IRSA, seccomp profiles.
- Helm charts provide templated, reviewable infrastructure as code.
- Richer observability integration: Prometheus metrics, Grafana dashboards, structured log shipping.
- Demonstrates K8s security engineering depth relevant to fintech platform roles.

**Negative:**
- Significantly higher operational complexity than ECS Fargate: cluster upgrades, node group management, add-on lifecycle (CoreDNS, kube-proxy, VPC CNI).
- Higher baseline cost than Fargate (always-on node capacity vs. per-task billing).
- Requires K8s expertise on the operations team; a team without it faces a steep learning curve.

---

## Alternatives Considered

| Alternative | Reason Rejected (for this context) |
|---|---|
| **ECS Fargate** | Simpler and lower-cost for a single service; lacks NetworkPolicy, Kyverno, and the full K8s security primitive surface. **Preferred for a single-service production system without K8s expertise on the team.** |
| **AWS Lambda** | Event-driven model does not map naturally to synchronous REST + persistent database connection pooling; cold starts add latency variance unacceptable for payment SLAs |

> **Trade-off note:** For a single-service production system where the team does not have Kubernetes expertise, **ECS Fargate would be the recommended choice** — lower complexity, lower cost, and AWS manages the control plane entirely. EKS is chosen here specifically to demonstrate platform security depth.
