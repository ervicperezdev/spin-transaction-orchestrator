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
- EKS endpoint access is private; the permitted control-plane CIDRs must be explicitly supplied by the environment owner.
- RDS uses encrypted storage, encrypted backups, deletion protection, a private subnet group and a security group that accepts PostgreSQL only from the EKS node security group.
- ECR image scanning and immutable tags protect the registry boundary. Lifecycle retention is deliberately short only for untagged images.
- The workload IAM role is separate from node roles and has no permissions by default. Add exact Secrets Manager ARNs only after a workload access review; IRSA wiring is a deployment integration step.
- This foundation does not create DNS, ACM/WAF, secrets, observability, Kubernetes add-ons, OIDC/IRSA trust relationships, or a production CI apply path. Those are roadmap items requiring ownership and account-specific design.

Known risk: an apply with an overly broad `allowed_control_plane_cidrs` value could expose EKS endpoint access. Validation rejects `0.0.0.0/0`, but network approval remains required.
