# ADR-006: Acceso a federación OIDC, IRSA y Secrets Manager
**Estado:** Aceptado
**Fecha:** 2026-09-08
## Contexto
La canalización de entrega debe publicar una imagen revisada en ECR y descubrir un EKS.
clúster sin almacenar claves de acceso de AWS en GitHub. Las credenciales de la solicitud deben
no estar comprometido con Git, inyectado como variables de Terraform ni compartido con EKS
nodos. La API de transacciones lee los valores aprobados de Secrets Manager directamente
a través del controlador CSI de AWS Secrets Store; ningún secreto está sincronizado en
Kubernetes.
## Decisión
Utilice dos roles de IAM independientes y una federación de identidades web:
1. `*-github-deploy` confía únicamente en el proveedor OIDC de GitHub a través de
   `sts:AssumeRoleWithWebIdentity`. Sus condiciones requieren
   `aud=sts.amazonaws.com` y el exacto
   `repo:ervicperezdev/spin-transaction-orchestrator:ref:refs/heads/main`
   sujeto (parametrizado para otro entorno revisado).
2. `*-transaction-api` confía únicamente en el proveedor EKS OIDC y en la API exacta
   Asunto de la cuenta de servicio. Sólo puede `DescribeSecret` y `GetSecretValue`
   para los ARN explícitos de Secrets Manager proporcionados por el propietario del entorno.
La función de CI puede autenticarse en ECR, enviar solo al repositorio del orquestador,
y llame a `eks:DescribeCluster` solo para su clúster. Acceso a la API de EKS Kubernetes
se otorga por separado a través de entradas de acceso EKS/RBAC; no es IAM implícito
acceso de administrador. La función IRSA de la API lee solo el ARN secreto explícito
y el controlador CSI expone cada propiedad JSON como un archivo montado de solo lectura.
El cifrado utiliza claves administradas por AWS: RDS utiliza la clave y los secretos de RDS administrados por AWS
El administrador usa `alias/aws/secretsmanager`. Se eliminó la clave EKS KMS personalizada;
EKS utiliza su comportamiento de cifrado predeterminado administrado por la plataforma.
## Consecuencias
- Las GitHub Actions deben usar la salida `github_deploy_role_arn` como protegida
  Secreto del repositorio `AWS_DEPLOY_ROLE_ARN`. Sin `AWS_ACCESS_KEY_ID` o
  Se puede configurar `AWS_SECRET_ACCESS_KEY`.
- El proveedor EKS OIDC es un requisito previo de inicio de cuenta. Su ARN y
  el host/ruta del emisor son entradas explícitas de Terraform, por lo que un clúster no puede
  confiar accidentalmente en un emisor arbitrario.
- Los valores secretos se crean y rotan fuera de la banda. Terraform recibe sólo
  ARN secretos exactos y la cuenta de servicio API está anotada con el resultado
  ARN del rol de carga de trabajo.
- GitHub Actions OIDC y EKS IRSA siguen siendo límites de radio de explosión separados;
  ningún papel puede asumir el otro.
## Alternativas rechazadas
- Usuarios de IAM de larga duración o secretos de repositorio que contienen claves de AWS.
- Un rol de IAM de nodo con acceso a Secrets Manager.
- Temas amplios de GitHub OIDC como `repo:owner/repository:*`.
- Operador de secretos externos o una copia secreta de Kubernetes del valor de origen.
