# ADR-006: OIDC federation, IRSA and Secrets Manager access

**Status:** Accepted  
**Date:** 2026-09-08

## Context

The delivery pipeline must publish a reviewed image to ECR and discover one EKS
cluster without storing AWS access keys in GitHub. Application credentials must
not be committed to Git, injected as Terraform variables, or shared with EKS
nodes. The transaction API reads approved Secrets Manager values directly
through the AWS Secrets Store CSI driver; no secret is synchronized into
Kubernetes.

## Decision

Use two independent IAM roles and web-identity federation:

1. `*-github-deploy` trusts only GitHub's OIDC provider through
   `sts:AssumeRoleWithWebIdentity`. Its conditions require
   `aud=sts.amazonaws.com` and the exact
   `repo:ervicperezdev/spin-transaction-orchestrator:ref:refs/heads/main`
   subject (parameterized for another reviewed environment).
2. `*-transaction-api` trusts only the EKS OIDC provider and the exact API
   service account subject. It can only `DescribeSecret` and `GetSecretValue`
   for the explicit Secrets Manager ARNs supplied by the environment owner.

The CI role can authenticate to ECR, push only to the orchestrator repository,
and call `eks:DescribeCluster` only for its cluster. EKS Kubernetes API access
is separately granted through EKS access entries/RBAC; it is not implicit IAM
administrator access. The API's IRSA role reads only the explicit secret ARN
and the CSI driver exposes each JSON property as a read-only mounted file.

Encryption uses AWS-managed keys: RDS uses the AWS-managed RDS key and Secrets
Manager uses `alias/aws/secretsmanager`. The custom EKS KMS key was removed;
EKS uses its platform-managed default encryption behavior.

## Consequences

- GitHub Actions must use the output `github_deploy_role_arn` as the protected
  `AWS_DEPLOY_ROLE_ARN` repository secret. No `AWS_ACCESS_KEY_ID` or
  `AWS_SECRET_ACCESS_KEY` may be configured.
- The EKS OIDC provider is an account bootstrap prerequisite. Its ARN and
  issuer host/path are explicit Terraform inputs so a cluster cannot
  accidentally trust an arbitrary issuer.
- Secret values are created and rotated out of band. Terraform receives only
  exact secret ARNs, and the API service account is annotated with the output
  workload role ARN.
- GitHub Actions OIDC and EKS IRSA remain separate blast-radius boundaries;
  neither role may assume the other.

## Rejected alternatives

- Long-lived IAM users or repository secrets containing AWS keys.
- A node IAM role with Secrets Manager access.
- Broad GitHub OIDC subjects such as `repo:owner/repository:*`.
- External Secrets Operator or a Kubernetes Secret copy of the source value.
