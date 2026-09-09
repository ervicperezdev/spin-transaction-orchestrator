# EXC-001 — Temporary public EKS API access for the challenge

## Decision record

| Field | Record |
| --- | --- |
| Tracking ID | EXC-001; this versioned document is the tracking record. |
| Recorded | 2026-09-09 |
| Disposition | Proposed time-bound risk acceptance for the development demonstration; not a false positive. |
| Status | Documented at the repository owner's request. Deployment evidence and security-owner approval are pending; no formal approval is asserted by this record. |
| Proposed implementation / risk owner | Repository owner, Ervic Pérez; responsible for verification, review and closure. |
| Approval authority | Security lead or delegated security owner, as required by the [risk assessment policy](vulnerability-risk-assessment.md). Record the approver and dated PR review before activation. |
| Scope | Only the challenge's `dev` EKS API endpoint, resource `module.eks.aws_eks_cluster.this`, defined in `terraform/modules/eks/main.tf`. No production authorization. |
| Proposed review | 2026-09-16, and before any deployment or access change. |
| Proposed expiry | 2026-09-23, or completion of the demonstration or introduction of real data, whichever occurs first. Approval must confirm or shorten this window; it does not restart on deployment. |
| Finding | `terraform.lang.security.eks-public-endpoint-enabled.eks-public-endpoint-enabled` |
| Source | Owner-supplied CI log from `returntocorp/semgrep:1.99.0`; image digest `sha256:ae27024c16f7848cdbfd49c24ed0b78b13f13b85fcd7b87c679aaa8b0c0dce98`. Run URL and affected commit SHA are pending. |

## Business rationale and technical boundary

The challenge demonstrates an automated application deployment using standard
GitHub-hosted `ubuntu-latest` runners. These runners have no configured route
into the EKS VPC and do not provide a dedicated static egress IP for this job.
A private endpoint would require private connectivity or a deployment runner
inside the VPC. That additional infrastructure is deferred for the limited
demonstration period.

The proposed exception permits `endpoint_public_access = true` while retaining
`endpoint_private_access = true`. If standard hosted runners require
`public_access_cidrs = ["0.0.0.0/0"]`, acceptance must explicitly cover access
from **all IPv4 source addresses**, not describe it as a GitHub-only allowlist.
There is no authorization here for IPv6-wide access or other environments.
An administrator's `/32` alone does not provide access for the hosted runner.

At documentation time, the repository baseline sets public access to `false`
and rejects `0.0.0.0/0` in variable validation. The reported finding therefore
does not establish the state of the current checkout or deployed cluster.
This record changes neither setting. Any activation must identify the exact
commit, reviewed plan and actual CIDRs; any validation exception must remain
explicitly scoped to the development environment.

This concerns the Kubernetes management API, independently of the application's
public ALB, DNS and TLS configuration. Successful AWS OIDC authentication or
`aws eks update-kubeconfig` does not establish Kubernetes authorization.

## Risk assessment

The finding is valid when public endpoint access is enabled. Internet exposure
allows external hosts to reach the API authentication boundary, increasing
exposure to scanning, unauthorized authentication attempts, API availability
attacks and abuse of stolen authorized credentials. An authenticated attacker
could change workloads or access Kubernetes data within the compromised
principal's permissions; cluster-admin compromise has cluster-wide impact.

The qualitative residual risk is **High pending verification**. This is not a
scanner severity or CVSS score, and no numerical score is assigned to this
configuration finding. Short duration and synthetic data limit the intended
business exposure but do not remove the technical risk. Failure to demonstrate
the controls below prevents activation under this exception.

The application's WAF, ALB security group and pod NetworkPolicies do **not**
protect the EKS public API endpoint. They are not compensating controls for
this finding. Logging provides detection, not prevention.

## Required controls and verification evidence

| Control | Required evidence before activation |
| --- | --- |
| Temporary, isolated demonstration | Confirm the account/cluster/environment, owner and teardown date; use synthetic transactions and test credentials only. |
| Short-lived CI credentials | Verify GitHub OIDC trust restricts the intended repository/ref and audience; record the actual assumed IAM role. No static AWS keys in Actions. |
| Kubernetes access control | Verify the deploy role has its own EKS access entry or supported identity mapping and permissions limited to application deployment in `transaction-api`. Keep platform administration separate; demonstrate denied access outside the permitted scope. |
| Trusted deployment source | Verify the deployment trigger and repository branch protections. Untrusted PR code must not obtain the deployment identity. Workflow definitions alone do not prove repository settings. |
| Private node connectivity | Verify `endpointPrivateAccess = true`; retain private application/database subnets and RDS isolation. This limits other exposure but does not restrict the public API. |
| Detection and review | Verify API, audit and authenticator logs are delivered to CloudWatch; review failed authentication and privileged changes before/after each demonstration. Record log retention and the responsible reviewer. |
| Controlled infrastructure change | Retain the reviewed Terraform plan, apply result and live endpoint/CIDR configuration. Do not grant the application deploy role permissions to widen EKS endpoint access. |

No live verification of these controls was performed while writing this record.
Keep evidence links in the table below; do not attach tokens, kubeconfig
credentials, Terraform state or unredacted plans containing secrets.

| Audit artifact | Evidence status |
| --- | --- |
| Source scan run URL, commit SHA and full finding | Pending; only the supplied log excerpt is available. |
| Approver, approval date and reviewed PR | Pending. |
| Target cluster ARN, deployment revision and actual CIDRs | Pending. |
| Reviewed plan and deployment result | Pending. |
| IAM/OIDC, EKS permissions and negative authorization checks | Pending. |
| Logging, branch protection and synthetic-data verification | Pending. |
| Review outcome and closure evidence | Pending. |

## Scanner treatment

At the repository owner's explicit request, a rule-specific `nosemgrep`
annotation has been added immediately above `aws_eks_cluster.this` in
`terraform/modules/eks/main.tf`. It references EXC-001 and the 2026-09-23
expiry, and suppresses only the identified rule at that resource. The current
endpoint remains private, so the annotation does not itself activate the
network exception. Formal approval and deployment evidence remain pending.
The existing `--error` behavior and Quality Gate remain in force for other
findings. Do not exclude the Terraform directory, disable the scanner job or
introduce `continue-on-error` to implement this exception.

Re-run the original scanner after any suppression and demonstrate that other
findings remain blocking. Expiry is a manual review obligation here; the
repository does not currently enforce this document's dates automatically.

## Remediation and closure

1. Establish private deployment connectivity: a trusted runner in the VPC or
   an authenticated private network path from the hosted runner. Provide
   administrator access through VPN or an SSM-managed administration host.
2. Verify DNS, routing, HTTPS security-group access and EKS authorization for
   both the deployment and administrator identities before disabling public
   access. A public runner with static egress is an interim way to narrow
   CIDRs, but does not satisfy the private-endpoint closure criterion.
3. Apply `endpoint_public_access = false` while retaining private access, or
   tear down the demonstration environment through the reviewed process.
4. Remove any associated scanner suppression and development-only validation
   bypass; rerun Semgrep and record the clean result at the closing commit.
5. Retain live endpoint configuration and a successful private deployment as
   evidence, or evidence that the demonstration cluster was removed.

Close at the earliest expiry trigger. Suspected credential compromise,
unexpected access, missing controls or production use requires immediate
reassessment and restriction of access under the incident-response process.
An extension requires a new dated review, rationale and expiry; it is never
automatic. Until private connectivity is ready, disabling public access will
also interrupt deployments from the current hosted runners.

## References

- [EKS endpoint access](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html)
- [GitHub-hosted runner IP address limitations](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Repository vulnerability and exception policy](vulnerability-risk-assessment.md)
- [Cloud security operations](../cloud-security-operations.md)
- [Incident response](../incident-response.md)
