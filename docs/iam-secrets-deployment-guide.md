# IAM and Secrets deployment guide

This guide configures identity without putting a credential or secret value in
the repository. It assumes the AWS account, EKS cluster and AWS Secrets Store
CSI driver/provider are owned by an authorized platform operator.

## 1. Bootstrap reviewed inputs

Create the EKS IAM OIDC provider once for the cluster issuer, then set its ARN
and issuer host/path in a private `terraform.tfvars`. Do not commit that file.
Use an exact, versioned Secrets Manager ARN in `workload_secret_arns`; do not
use `*`. Create the secret value with an approved secret-management process.

```hcl
workload_secret_arns = [
  "arn:aws:secretsmanager:us-east-1:123456789012:secret:spin/transaction-api/prod-ABC123",
]
eks_oidc_provider_arn    = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
eks_oidc_issuer_hostpath = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
```

Run `terraform plan` for review, then apply only through the approved
infrastructure change process. Terraform deliberately never sets a secret
value.

## 2. Bind the transaction API and mount Secrets Manager directly

Annotate the transaction API service account with `workload_role_arn`:

```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<environment>-transaction-api
```

The namespace and service-account name must match `application_namespace` and
`application_service_account`. Set the Helm `serviceAccount.roleArn`,
`secretsManager.region`, and `secretsManager.secretArn` values. The chart
creates a `SecretProviderClass` that mounts the approved JSON fields as
read-only files; Spring Boot imports them through `configtree`. It does not
create a Kubernetes `Secret`.

Secrets Manager should use its AWS-managed key (`alias/aws/secretsmanager`),
and RDS uses its AWS-managed RDS key. No customer-managed KMS key is created.

## 3. Configure CI federation

Set the Terraform output `github_deploy_role_arn` as the protected GitHub
repository secret `AWS_DEPLOY_ROLE_ARN`, and set `AWS_REGION` as a repository
variable. The existing workflow uses `id-token: write` and exchanges GitHub's
short-lived token directly with STS. It is restricted to the configured
repository and `refs/heads/main`.

Before enabling deployment, grant this deploy role only the EKS access entry
and Kubernetes RBAC permissions required for its target namespace. Verify the
role has no IAM write, Secrets Manager, wildcard ECR repository, or
`sts:AssumeRole` permissions.

## Verification checklist

- `terraform fmt -check -recursive terraform` and `terraform validate` pass.
- The GitHub role trust contains both exact `aud` and `sub` conditions.
- The API IRSA trust contains exact EKS issuer, namespace and service-account
  conditions.
- `workload_secret_arns` contains only the intended secret ARNs.
- Repository and organization secrets contain no static AWS access key pair.
- `helm template transaction-api helm/transaction-api` renders the
  `SecretProviderClass` and CSI volume without revealing a value.
