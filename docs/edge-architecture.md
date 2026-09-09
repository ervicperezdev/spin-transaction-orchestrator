# Internet edge and EKS add-ons

The Terraform environment implements this traffic path:

```text
Internet → Route 53 → ALB + WAF → AWS Load Balancer Controller → Service → Pods
                         └─ ACM certificate terminates HTTPS
```

`modules/edge` looks up the approved public Route 53 hosted zone, creates and
DNS-validates an ACM certificate, and creates a regional WAF ACL with AWS
managed common rules and an IP rate limit. The application Ingress receives
the certificate and WAF ARNs as annotations. ExternalDNS watches that Ingress
and writes the ALB alias record only in the approved hosted zone.

`modules/addons` installs the EKS Pod Identity Agent, AWS Load Balancer
Controller and ExternalDNS through Terraform. Each controller has its own
`aws_eks_pod_identity_association` and role trusted solely by
`pods.eks.amazonaws.com`; no service-account annotation or static key is
used. The Load Balancer Controller role manages ALB resources; ExternalDNS is
limited to changes in the one Route 53 hosted zone.

Before apply, supply the real `route53_zone_name` and `application_hostname`,
review ACM ownership/validation, and configure the deployment Helm values with
the `acm_certificate_arn` and `waf_web_acl_arn` outputs. A single NAT gateway
is intentional for the development baseline; production should use one NAT
gateway per availability zone or approved VPC endpoints.
