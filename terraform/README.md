# Terraform foundation

This directory is a reviewed **foundation**, not evidence of an AWS deployment. It creates no resources until an authorized operator runs an apply outside this repository workflow.

## Layout

`environments/dev` composes the VPC, ECR, EKS, RDS and workload-IAM modules. Values are deliberately non-sensitive placeholders; real account identifiers, CIDRs approved by network engineering, and database credentials stay out of Git.

## Remote state

State is expected in an existing, separately governed S3 bucket. Configure it at init time so the bucket name, key and AWS account are not committed:

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.hcl.example
terraform fmt -check -recursive ../..
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars.example
```

Copy `backend.hcl.example` outside the repository and replace its placeholders. S3 versioning, encryption, public-access blocking and access policies are bootstrap-account responsibilities. Native S3 lockfiles are used (`use_lockfile = true`); DynamoDB locking is intentionally not configured because current Terraform supports S3 lockfiles. Do not run `apply` from this repository or CI.

## Security boundaries and assumptions

- The VPC supplies isolated database subnets and private application subnets; RDS is never publicly accessible.
- The repository baseline disables public EKS endpoint access. `allowed_control_plane_cidrs` configures the public endpoint allowlist when enabled; it does not grant private connectivity. The proposed temporary development exception for GitHub-hosted runners is recorded in [EXC-001](../docs/security/EXC-001-eks-public-endpoint.md), with approval and live verification pending.
- RDS uses encrypted storage, encrypted backups, deletion protection, a private subnet group and a security group that accepts PostgreSQL only from the EKS node security group.
- ECR image scanning and immutable tags protect the registry boundary. Lifecycle retention is deliberately short only for untagged images.
- GitHub Actions uses an OIDC-to-STS deployment role restricted to the configured repository and branch. It can push only to this ECR repository and discover only this EKS cluster; it has no static AWS keys or Secrets Manager access.
- The transaction API uses a separate IRSA role restricted to its exact service account and the exact Secrets Manager ARNs it mounts through the AWS Secrets Store CSI driver. No Kubernetes Secret copy is created. Secrets Manager and RDS use AWS-managed KMS keys; no customer-managed KMS key is created. See `../docs/iam-secrets-deployment-guide.md` and `../docs/adr/ADR-006-oidc-iam-and-secrets.md`.
- Terraform creates public/private edge routing, DNS-validated ACM, a regional WAF ACL, the EKS Pod Identity Agent, AWS Load Balancer Controller, and ExternalDNS. See `../docs/edge-architecture.md`. It does not create secret values, observability, the Secrets Store CSI driver/provider add-on, EKS OIDC provider bootstrap, EKS access entries/RBAC, or a production CI apply path.

Known risk: an apply with an overly broad `allowed_control_plane_cidrs` value could expose EKS endpoint access. Validation rejects `0.0.0.0/0`, but network approval remains required.
