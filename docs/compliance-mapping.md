# Compliance mapping and evidence register

## Purpose and boundary

This is a design-time mapping of controls versioned in this repository to selected control objectives in NIST SP 800-53 Rev. 5, CIS AWS Foundations and CIS Kubernetes Benchmark, PCI DSS v4.0, and ISO/IEC 27001:2022 Annex A. It describes a **contribution to compliance**, not a certification, attestation, or assertion that a deployed AWS account meets any framework.

Evidence below is repository evidence as of the revision under review. An independent assessor must validate deployed configuration, operating effectiveness, scope (including whether cardholder data is present), people and processes, and the organization-selected versions of each framework. This MVP does not claim PCI DSS cardholder-data-environment (CDE) scope; payment data handling and tokenization must be assessed before making that determination.

Status meanings: **Implemented in IaC/chart** is inspectable declarative evidence, not proof it has been applied; **Designed/documented** needs an operational implementation; **Gap** is not implemented or lacks evidence.

## Evidence and gap register

| Control objective | Repository evidence | Framework contribution | Status / gap and required validation |
| --- | --- | --- | --- |
| Segment public, workload and database traffic | `terraform/modules/edge/main.tf` defines managed ALB and node security groups; `terraform/modules/eks/main.tf` keeps the EKS API private; `terraform/modules/rds/main.tf` makes RDS private and permits PostgreSQL only from the node SG; Helm has default-deny workload `NetworkPolicy` with explicit ingress/egress. | NIST SC-7; CIS AWS networking / EKS network-policy guidance; PCI DSS 1; ISO A.8.20, A.8.22. | **Implemented in IaC/chart.** Confirm Terraform state, VPC routing/NAT, ALB-to-WAF association, NetworkPolicy-capable CNI enforcement, allowed CIDRs and no alternate paths in each environment. |
| Protect external web entry points and transport | Terraform provisions DNS-validated ACM and a regional WAF ACL with AWS managed rules and rate limiting; production Helm values pass the ACM and WAF ARNs to the ALB controller. | NIST SC-7, SC-8, SI-4; CIS AWS edge/logging guidance; PCI DSS 1, 4, 6.4; ISO A.8.20, A.8.21, A.8.26. | **Implemented in IaC/chart.** Validate the rendered Ingress has real non-placeholder ARNs, the controller attached the ACL/certificate, TLS policy/ciphers and WAF logging are enabled. |
| Encrypt and protect application secrets | `SecretProviderClass` mounts AWS Secrets Manager via the Secrets Store CSI driver read-only, without `secretObjects`; the workload IAM policy limits reads to supplied secret ARNs. RDS storage is encrypted and uses RDS managed credentials. | NIST IA-5, SC-12, SC-13, SC-28; CIS AWS IAM / secrets-management guidance; PCI DSS 3, 4, 8; ISO A.5.17, A.8.24. | **Implemented in IaC/chart, with bootstrap gap.** Terraform intentionally does not create secret values, the CSI driver/provider, or the EKS OIDC provider. Validate installed components, exact secret policy, rotation, mounted-file permissions, and that no Kubernetes Secret copy exists. AWS-managed KMS keys are used; key policy/CMK governance is not provided. |
| Apply least privilege and federated identities | CI trust is restricted to the configured GitHub repository/ref in `terraform/modules/iam/main.tf`; workload IRSA trust is restricted to one namespace/service account. Load Balancer Controller and ExternalDNS use EKS Pod Identity with separate roles. EKS nodes require IMDSv2. | NIST AC-2, AC-3, AC-6, IA-2, IA-5; CIS AWS IAM and EKS identity guidance; PCI DSS 7, 8; ISO A.5.15–A.5.18, A.8.2. | **Implemented in IaC, with account/RBAC gap.** Verify the external OIDC bootstrap and values, role use through CloudTrail, IAM Access Analyzer results, Kubernetes RBAC/access entries, break-glass controls, access review cadence and removal process. |
| Harden containers and workloads | Helm security contexts and Kyverno policies require non-root, read-only root filesystem, dropped privilege escalation, resource limits, probes, approved registries and non-`latest` tags. The Dockerfile uses a distroless non-root runtime. | NIST CM-6, CM-7, SI-7; CIS Kubernetes workload-pod security guidance; PCI DSS 2, 5, 6; ISO A.8.9, A.8.19, A.8.27. | **Implemented in repository policy/chart.** Validate Kyverno is installed, policies are enforced (not audit-only), exceptions are reviewed, images are immutable/digest-pinned at deployment, and runtime vulnerability remediation is operated. |
| Secure build and artifact provenance | PR workflows run Gitleaks, Semgrep, Trivy SCA, Checkov, Helm lint and Hadolint. Release/container workflows generate SPDX SBOMs and sign images/attestations with Cosign and GitHub OIDC. | NIST RA-5, SA-10, SI-2, SI-7; CIS software-supply-chain guidance; PCI DSS 6.2, 6.3, 6.4; ISO A.8.8, A.8.25, A.8.29, A.8.32. | **Implemented in CI definition.** Validate branch protection makes required jobs blocking, signatures/attestations are verified by admission or deployment tooling, findings have SLA/exception records, and artifacts/retention are available to auditors. |
| Log, monitor and respond to security events | `docs/cloud-security-operations.md` defines CloudTrail, GuardDuty, Security Hub, WAF, ALB/RDS/EKS signal handling, triage and escalation; EKS control-plane logs are configured. | NIST AU-2, AU-6, AU-9, AU-12, CA-7, IR-4, SI-4; CIS AWS logging/monitoring guidance; PCI DSS 10, 11.5, 12.10; ISO A.5.24–A.5.28, A.8.15, A.8.16. | **Designed/documented; operational gap.** The repository does not enable CloudTrail, GuardDuty, Security Hub, WAF log destinations, SIEM, alarms, retention/immutability, or pager integrations. Implement and exercise the validation plan before relying on this control. |
| Resilience, recovery and change protection | RDS uses Multi-AZ, encrypted backups with seven-day retention, deletion protection and final snapshot; Helm defines HPA/PDB/probes. Changes are versioned as Terraform, Helm and reviewed PR workflows. | NIST CP-9, CP-10, CM-2, CM-3; CIS AWS backup/configuration guidance; PCI DSS 6.4, 12.10; ISO A.8.13, A.8.14, A.8.32. | **Implemented configuration, operating-evidence gap.** Test backup restore and failover, document RPO/RTO, protect Terraform state, enforce change approvals, and retain deployment/change evidence. |
| Govern risk, scope and security responsibilities | `SECURITY.md`, `docs/threat-model.md`, `docs/security-remediation.md`, and vulnerability assessment documentation define reporting, threat/risk context and remediation expectations. | NIST PL-2, RA-3, RA-5, PM-9; PCI DSS 12; ISO A.5.1, A.5.2, A.5.7, A.5.36. | **Partially documented.** Establish approved policies, asset/data-flow inventory, CDE scoping decision, vendor/service-provider responsibility matrix, security training, annual review and auditable risk acceptance process outside this repository. |

## Material gaps and ownership

The following are prerequisites to describing controls as operating in an AWS environment. They remain outside this repository's Terraform scope and must have an accountable platform or security owner, target date, and retained evidence:

1. Account bootstrap: AWS Organizations/account guardrails, CloudTrail, Config, GuardDuty, Security Hub, centralized immutable log storage, alerting, IAM Identity Center/MFA and root-account protections.
2. Cluster bootstrap: EKS OIDC provider for workload IRSA, Secrets Store CSI driver and AWS provider, Kyverno installation/enforcement, CNI NetworkPolicy support, access entries/RBAC and admission verification.
3. Deployment assurance: a reviewed Terraform apply process, remote-state encryption/access controls, production values/secret ARNs, WAF logging and certificate/WAF attachment validation.
4. Operational assurance: tested restore/failover and incident exercises, access reviews, vulnerability remediation SLAs/exceptions, log retention, signature verification enforcement and evidence retention.
5. PCI scope: data discovery and a payment-provider integration review to establish whether PAN, SAD, tokens or other account data enters this system; if it does, perform a formal CDE segmentation and PCI assessment.

### Development endpoint exception

The private-EKS claim in the segmentation row describes the current repository
baseline. If the proposed [EXC-001](security/EXC-001-eks-public-endpoint.md)
exception is activated, that control is **deviated for the development EKS
management endpoint** until closure. Public exposure must not be reported as
private segmentation or protected by the application's WAF. Record the actual
CIDRs, approval, deployment revision and verification evidence before claiming
compensating controls. This exception grants no production or regulatory
compliance attestation.

## Review cadence and evidence collection

Review this mapping on material architecture, AWS account, framework-version, or payment-data-flow changes, and at least annually. For each review, retain: the commit and approved PR, Terraform plan/apply and state evidence (redacted), rendered Helm manifests and admission results, AWS configuration exports, IAM/access-review records, CI findings/SBOM/signature verification, backup restore and incident-exercise results. Do not place secrets, transaction payloads, cardholder data, or raw sensitive logs in the evidence package.
