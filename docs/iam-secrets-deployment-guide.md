# Guía de implementación de IAM y secretos
Esta guía configura la identidad sin poner una credencial o un valor secreto en
el repositorio. Asume la cuenta de AWS, el clúster de EKS y AWS Secrets Manager.
El conductor/proveedor de CSI es propiedad de un operador de plataforma autorizado.
## 1. Entradas revisadas por Bootstrap
Cree el proveedor EKS IAM OIDC una vez para el emisor del clúster y luego configure su ARN.
y host/ruta del emisor en un `terraform.tfvars` privado. No confirme ese archivo.
Utilice un ARN de Secrets Manager exacto y versionado en `workload_secret_arns`; no
Utilice `*`. Cree el valor secreto con un proceso de gestión de secretos aprobado.
```hcl
workload_secret_arns = [
  "arn:aws:secretsmanager:us-east-1:123456789012:secret:spin/transaction-api/prod-ABC123",
]
eks_oidc_provider_arn    = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
eks_oidc_issuer_hostpath = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
```

Ejecute `terraform plan` para revisión, luego aplique solo a través del programa aprobado.
proceso de cambio de infraestructura. Terraform deliberadamente nunca guarda un secreto
valor.
## 2. Vincule la API de transacciones y monte Secrets Manager directamente
Anote la cuenta del servicio API de transacciones con `workload_role_arn`:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/<environment>-transaction-api
```

El espacio de nombres y el nombre de la cuenta de servicio deben coincidir con `application_namespace` y
`application_service_account`. Configure el timón `serviceAccount.roleArn`,
Valores `secretsManager.region` y `secretsManager.secretArn`. el cuadro
crea un `SecretProviderClass` que monta los campos JSON aprobados como
archivos de sólo lectura; Spring Boot los importa a través de `configtree`. no lo hace
cree un Kubernetes `Secret`.
Secrets Manager debe utilizar su clave administrada por AWS (`alias/aws/secretsmanager`),
y RDS utiliza su clave RDS administrada por AWS. No se crea ninguna clave KMS administrada por el cliente.
## 3. Configurar la federación de CI
Configure la salida de Terraform `github_deploy_role_arn` como GitHub protegido
secreto del repositorio `AWS_DEPLOY_ROLE_ARN` y configure `AWS_REGION` como repositorio
variable. El flujo de trabajo existente utiliza `id-token: write` e intercambia GitHub.
token de corta duración directamente con STS. Está restringido a lo configurado.
repositorio y `refs/heads/main`.
Antes de habilitar la implementación, otorgue a esta función de implementación solo la entrada de acceso EKS
y permisos RBAC de Kubernetes necesarios para su espacio de nombres de destino. Verificar el
El rol no tiene escritura de IAM, Secrets Manager, repositorio ECR comodín ni
Permisos `sts:AssumeRole`.
## Lista de verificación de verificación
- Pase `terraform fmt -check -recursive terraform` y `terraform validate`.
- La confianza del rol de GitHub contiene condiciones exactas de `aud` y `sub`.
- La confianza API IRSA contiene el emisor, el espacio de nombres y la cuenta de servicio exactos de EKS.
  condiciones.
- `workload_secret_arns` contiene solo los ARN secretos previstos.
- Los secretos del repositorio y de la organización no contienen ningún par de claves de acceso estáticas de AWS.
- `helm template transaction-api helm/transaction-api` representa el
  `SecretProviderClass` y volumen CSI sin revelar un valor.
