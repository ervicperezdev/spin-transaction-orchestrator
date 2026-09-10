# Base de infraestructura Terraform

Este directorio contiene la definición de infraestructura. El código y sus
validaciones no acreditan que los recursos estén desplegados en AWS.

## Estructura

`environments/dev` compone VPC, ECR, EKS, RDS, IAM y complementos de Kubernetes.
Conserve credenciales y valores secretos fuera de Git. Las variables del
ambiente contienen los identificadores y CIDRs reales; revise sus valores
antes de planificar. El nombre del clúster en esta integración es
`${project}-cluster`, mientras ECR usa `repository_name`.

## Estado remoto

El bucket S3 debe existir y tener versionado, cifrado, bloqueo de acceso público
y políticas de acceso. Copie `backend.hcl.example` fuera del repositorio y
reemplace sus placeholders. El archivo real `backend.hcl` se ignora en Git.
Se usa bloqueo nativo S3 (`use_lockfile = true`), sin DynamoDB.

```bash
cd terraform/environments/dev
terraform init -backend-config=/ruta/privada/backend.hcl
terraform fmt -check -recursive ../..
terraform validate
terraform plan -var-file=terraform.tfvars
```

## Pipeline de entrega Terraform

Los workflows no aceptan credenciales AWS estáticas ni archivos `backend.hcl`.
Todos usan OIDC de GitHub y construyen la configuración S3 en memoria. El
bucket se debe crear fuera de este estado (bootstrap) con **versioning**,
cifrado, Block Public Access, una política de TLS y `use_lockfile = true`.
No guarde state, `*.tfplan`, `*.tfvars` reales ni backend en Git o logs.

| Flujo | Trigger | Identidad y efecto |
| --- | --- | --- |
| `Terraform plan (PR)` | PR interno hacia `main` que modifica `terraform/**` | `AWS_TERRAFORM_PLAN_ROLE_ARN`, solo lectura de backend/proveedores. Ejecuta init remoto, fmt, validate, Checkov y plan; publica únicamente conteos de acciones. Nunca aplica. Los PR de forks se omiten deliberadamente para no entregar un token AWS a código no confiable. |
| `Terraform apply (development)` | push a `main` con cambios en `terraform/**` | Environment `development`, `AWS_TERRAFORM_APPLY_ROLE_ARN`, concurrencia exclusiva por state. Primero comprueba drift con `-refresh-only -detailed-exitcode`; ante drift/error no aplica. Genera, retiene siete días y aplica el mismo `tfplan`, sin `-auto-approve`. |
| `Terraform apply (production)` | `workflow_dispatch` con `refs/heads/...` o `refs/tags/...` | Un job de plan usa el rol read-only; el job de apply queda bloqueado por el Environment `production`, descarga el artifact de esa misma ejecución y aplica exactamente ese binario con un rol distinto. |

### Configuración de GitHub y AWS

Defina `AWS_REGION`, `TF_STATE_BUCKET` y `TF_STATE_REGION` como variables de
repositorio o Environment. Configure los valores Terraform reales como secreto
multilínea `TF_DEV_TFVARS`; el workflow lo escribe con permisos `0600` solo
durante el job y lo borra al finalizar. Para producción defina además
`TF_PRODUCTION_STATE_BUCKET`, el secreto `TF_PRODUCTION_TFVARS` y, cuando exista un entorno separado,
`TF_PRODUCTION_DIRECTORY` (por defecto
`terraform/environments/production`). El workflow falla de forma segura hasta
que ese directorio y su configuración protegida existan.

Configure los ARN como secretos de Environment, no como variables: los roles
son `AWS_TERRAFORM_PLAN_ROLE_ARN` (PR), `AWS_TERRAFORM_APPLY_ROLE_ARN`
(`development`), `AWS_TERRAFORM_PRODUCTION_PLAN_ROLE_ARN` y
`TF_PRODUCTION_TFVARS` (`production-plan`), y
`AWS_TERRAFORM_PRODUCTION_APPLY_ROLE_ARN` (`production`). Cree el Environment
`production-plan` con acceso limitado para que el plan no requiera exponer
secretos a nivel de repositorio. Cada trust policy debe validar
`aud=sts.amazonaws.com`, repositorio, evento/ref permitido y, para apply, el
subject del Environment correspondiente. El rol de plan solo puede leer el
bucket/key de estado y describir recursos; el de apply tiene permisos Terraform
mínimos sobre el ambiente. Ningún rol de plan puede asumir un rol de apply.

### Diagnóstico de credenciales

`configure-aws-credentials` solo recibe un token OIDC cuando
`role-to-assume` contiene un ARN válido. Si el log dice *"Could not load
credentials from any providers"* y no muestra `role-to-assume`, falta el
secreto del workflow: no es una expiración de AWS. El workflow ahora termina
antes de pedir credenciales e identifica los valores ausentes. En el estado
actual del repositorio existen `AWS_DEPLOY_ROLE_ARN` y
`AWS_DEPLOY_EKS_ROLE_ARN`, pero **no** sustituyen los roles Terraform: su
trust/políticas están destinadas a la entrega de aplicación y no conceden un
plan remoto de PR. Cree los roles y secretos Terraform indicados, con una trust
policy que admita el subject OIDC de PR interno para el rol de plan y los
subjects `environment:development`/`environment:production` para apply.

Este repositorio tiene habilitada una plantilla OIDC personalizada. El claim
validado en GitHub para este PR fue
`repo:ervicperezdev@55267476/spin-transaction-orchestrator@1360862265:pull_request`;
no use `repo:ervicperezdev/spin-transaction-orchestrator:pull_request` en una
trust policy. Para development, los subjects efectivos usan el mismo prefijo
con `:ref:refs/heads/main` (build), `:environment:development` (deploy/apply)
y `:pull_request` (plan). Los roles Terraform del módulo usan este prefijo por
defecto.

### Bootstrap de roles Terraform

El módulo `modules/iam` crea dos roles OIDC de development junto con sus
outputs: `github_terraform_plan_role_arn` y
`github_terraform_apply_role_arn`. El primero puede leer el state exacto y
leer/crear/eliminar sólo su archivo `.tflock`; nunca puede sobrescribir el
state.

El flujo de development genera el plan read-only en `main` y después espera la
aprobación del Environment `development` antes de aplicar ese mismo artifact.
Por ello el trust policy del rol de plan debe admitir tanto `:pull_request`
como `:ref:refs/heads/main` con el prefijo OIDC personalizado del repositorio.
Al adoptar este flujo en un rol ya existente, actualice esa trust policy una
vez con una identidad administradora antes del primer push a `main`.
El segundo puede leer y escribir exclusivamente
`spin-transaction-orchestrator/dev/terraform.tfstate` y su lock en el bucket
configurado. Así el `apply` puede persistir state sin conceder acceso a otros
states del bucket.

Por el bootstrap, este cambio se debe aplicar una vez con una identidad humana
o de plataforma ya autorizada contra el backend existente. Después publique
los outputs como secretos `AWS_TERRAFORM_PLAN_ROLE_ARN` (repositorio) y
`AWS_TERRAFORM_APPLY_ROLE_ARN` (Environment `development`). El rol de apply
acepta además `terraform_apply_managed_policy_arns`: adjunte un policy
account-managed revisado que permita únicamente los recursos Terraform del
ambiente. No se adjunta `AdministratorAccess` de forma implícita.

El mismo rol de apply recibe una EKS access entry de alcance cluster porque
Terraform instala add-ons y recursos Helm cluster-scoped. Esta autorización es
para la identidad Terraform; el rol de entrega de la aplicación conserva su
acceso limitado al namespace `transaction-api`.

El rol de plan recibe una access entry distinta con `AmazonEKSViewPolicy` de
alcance cluster. Es necesaria porque el provider Kubernetes refresca el
namespace y los recursos Helm durante el plan; es sólo lectura y no permite
leer Secrets ni mutar el clúster. Como el propio plan no puede crear su acceso,
en un clúster ya existente la entrada debe bootstrapearse una vez con una
identidad administradora antes de ejecutar el primer PR plan:

```bash
aws eks create-access-entry --region us-east-1 --cluster-name spin-cluster \
  --principal-arn arn:aws:iam::911167887101:role/spin-dev-transaction-api-terraform-plan \
  --type STANDARD
aws eks associate-access-policy --region us-east-1 --cluster-name spin-cluster \
  --principal-arn arn:aws:iam::911167887101:role/spin-dev-transaction-api-terraform-plan \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster
```

En GitHub, configure `development` y `production` con secrets/variables
restringidos; en `production` exija reviewers, impida que el autor se
autoapruebe y limite despliegues a `main` y tags protegidos. Proteja también
esas ramas/tags y convierta el job **Terraform plan (no mutation)** en check
requerido para los cambios Terraform. Los artifacts de plan son sensibles:
mantenga el acceso al repositorio mínimo y el retention de siete días.

### Aprobación, evidencia y recuperación

Para producción el operador dispara el workflow con una ref totalmente
calificada; revisa el resumen y artifact del job `plan`, y un revisor del
Environment autoriza el job `apply`. El resumen de ejecución conserva ref y
commit resuelto como registro de despliegue; CloudTrail debe retener
`AssumeRoleWithWebIdentity` y las llamadas Terraform/AWS.

Si init, seguridad, drift o apply fallan, el workflow falla y no reintenta
automáticamente. Investigue el estado remoto bloqueado y la causa; use una
ejecución manual posterior contra una ref protegida. Para recuperación de
estado, restaure una versión anterior del objeto S3 mediante el procedimiento
aprobado, valide con un plan de solo lectura y documente el incidente. Nunca
edite ni borre state/lock a ciegas.

## Límites y supuestos de seguridad

- VPC separa subredes de aplicaciones y base de datos; RDS no es público.
- EKS habilita endpoints público y privado para desarrollo bajo
  [EXC-001](../docs/security/EXC-001-eks-public-endpoint.md). Los CIDRs reales y
  la evidencia operativa deben revisarse. La validación heredada rechaza
  `0.0.0.0/1`, pero permite `0.0.0.0/0`; no garantiza una exposición restringida.
- RDS tiene cifrado y acceso PostgreSQL únicamente desde el security group de
  los nodos. El perfil mínimo de `dev` reduce explícitamente HA, retención y
  protección contra eliminación; consulte
  [`docs/finops-dev-profile.md`](../docs/finops-dev-profile.md) para los riesgos,
  rollback y verificación de Cost Explorer.
- ECR conserva tags inmutables, escaneo y retención de imágenes sin tag.
- GitHub usa OIDC para asumir un rol restringido al repositorio/ref configurado,
  acceder al repositorio ECR y consultar el clúster. Las entradas de acceso EKS
  declaran por separado al administrador y al rol de despliegue.
- La aplicación usa IRSA para leer solo los ARN de Secrets Manager autorizados.
  Los valores se montan como archivos y no se copian a Kubernetes Secrets.
- Terraform instala EKS Pod Identity Agent, Load Balancer Controller,
  ExternalDNS y Secrets Store CSI Driver con su proveedor AWS y CRDs. Aplique
  los complementos antes de desplegar la aplicación; consulte la
  [guía de IAM y secretos](../docs/iam-secrets-deployment-guide.md).
- No se crean valores secretos, proveedor OIDC de EKS, observabilidad completa
  ni un proceso de despliegue de producción. El acceso de red, la autorización
  Kubernetes y los controles operativos requieren verificación en AWS.

Antes de ejecutar el pipeline, compruebe que `AWS_DEPLOY_ROLE_ARN` y
`EKS_CLUSTER_NAME` coincidan con las salidas del ambiente. El proveedor Helm
obtiene credenciales renovables mediante AWS CLI; debe utilizar la misma
identidad que Terraform. Consulte [ADR-006](../docs/adr/ADR-006-oidc-iam-and-secrets.md).
