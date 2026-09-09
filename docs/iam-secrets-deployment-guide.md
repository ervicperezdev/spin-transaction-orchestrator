# Guía de implementación de IAM y secretos

## Namespace de la aplicación

Terraform crea `kubernetes_namespace_v1.application` con el nombre de
`application_namespace` (por defecto, `transaction-api`). Debe aplicarse con
la identidad administradora de plataforma antes de ejecutar el pipeline.
Crear un namespace exige permisos de alcance de clúster; el rol GitHub tiene
permisos dentro de `transaction-api` y el workflow ya no usa `--create-namespace`.
El proveedor Kubernetes utiliza AWS CLI y tokens renovables, con la misma
identidad y conectividad que el proveedor Helm.

Después de inicializar Terraform y revisar el plan, aplique la configuración
mediante el proceso de infraestructura y verifique como administrador:

```bash
kubectl get namespace transaction-api
```

Si el namespace ya existe fuera del estado, impórtelo antes de aplicar, desde
`terraform/environments/dev`:

```bash
terraform import kubernetes_namespace_v1.application transaction-api
```

No incluya este recurso en el chart de la aplicación: eso volvería a exigir
permisos de clúster al rol CI. Terraform administra su ciclo de vida; eliminar
el namespace también elimina los recursos que contiene.
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
variable. El workflow existente utiliza `id-token: write` e intercambia GitHub.
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

## Instalación previa de Secrets Store CSI Driver

`module.addons.helm_release.secrets_provider_aws` instala el chart AWS `3.1.3`
en `kube-system`, con Secrets Store CSI Driver y sus CRDs incluidos. La
sincronización a Kubernetes Secrets está deshabilitada. Aplique los complementos
antes de ejecutar el despliegue de la aplicación; la identidad de plataforma
necesita permisos para CRDs y RBAC de alcance de clúster. Si existe una instalación
externa, reconcilie su propiedad antes de aplicar para evitar duplicados.

```bash
kubectl wait --for=condition=Established --timeout=120s \
  crd/secretproviderclasses.secrets-store.csi.x-k8s.io
kubectl get csidriver secrets-store.csi.k8s.io
helm status secrets-provider-aws -n kube-system
kubectl get daemonsets,pods -n kube-system
```

Ambos DaemonSets deben estar listos en los nodos de la aplicación. EKS Pod
Identity Agent no instala este CRD. El error `no matches for kind
"SecretProviderClass"` indica que el tipo no está disponible en Kubernetes;
cambiar el ARN del secreto no instala el driver.

El workflow actual solo sobrescribe la imagen y su tag. Pase un archivo de
valores real con `-f` que configure `serviceAccount.roleArn`,
`secretsManager.secretArn`, `secretsManager.region`, `config.dbUrl`, URL del
proveedor e Ingress. Los archivos de ejemplo conservan placeholders. No incluya
valores secretos. El JSON de Secrets Manager debe contener `db-username`,
`db-password` y `payment-provider-api-key`; la política IRSA debe autorizar su
ARN exacto mediante `workload_secret_arns`.
