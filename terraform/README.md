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

La aplicación de cambios debe pasar por el proceso de infraestructura revisado;
no hay un workflow de `apply` de producción en este repositorio. No ejecute
`apply` desde CI como consecuencia de una validación estática.

## Límites y supuestos de seguridad

- VPC separa subredes de aplicaciones y base de datos; RDS no es público.
- EKS habilita endpoints público y privado para desarrollo bajo
  [EXC-001](../docs/security/EXC-001-eks-public-endpoint.md). Los CIDRs reales y
  la evidencia operativa deben revisarse. La validación heredada rechaza
  `0.0.0.0/1`, pero permite `0.0.0.0/0`; no garantiza una exposición restringida.
- RDS tiene cifrado, respaldos, protección contra eliminación y acceso
  PostgreSQL únicamente desde el security group de los nodos.
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
