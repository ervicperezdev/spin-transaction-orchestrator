# Runbook: teardown seguro de `dev`

`terraform/environments/dev` conserva un único state. Terraform construye el
grafo a partir de referencias entre recursos; no se deben reordenar archivos ni
usar `-target` como estrategia de desmantelamiento. Los `depends_on` que
existen son únicamente prerequisitos que Terraform no puede inferir.

## Límites del state

La hosted zone de Route 53 se consulta como `data.aws_route53_zone` y no es un
recurso de este state. El provider OIDC de EKS es un input externo
(`eks_oidc_provider_arn`); tampoco se destruye. Los registros de validación ACM
sí pertenecen al entorno y se eliminan con él.

La aplicación, su provider mock y su Ingress se entregan por Helm fuera del
state Terraform. Por tanto, el ALB, target groups y ENIs que crea el controller
de AWS deben desaparecer antes de que Terraform pueda eliminar VPC/subnets.

## Preflight y plan protegido

1. Abra el workflow manual **Terraform destroy plan (development)**. El
   Environment `development-teardown-plan` debe exigir revisores responsables.
   Escriba `PLAN-DEV-TEARDOWN`; este workflow no contiene ningún `terraform
   apply`.
2. Deje `skip_final_snapshot=false` y `delete_ecr_images=false` como valores
   seguros. El workflow genera un nombre de snapshot único por ejecución y el
   preflight comprueba que no exista.
3. El preflight, solo lectura, inspecciona releases Helm, Ingress, recursos
   ELB/target groups/ENIs de la VPC, imágenes ECR, snapshot RDS y el state. Si
   informa un bloqueo, no continúe: desinstale la release Helm y el mock,
   espere la limpieza del controller y repita el preflight.
4. Revise los conteos y el artifact binario `destroy.tfplan`. Confirme que no
   se incluyan la hosted zone ni un provider OIDC de EKS externo.
5. Solo después de una aprobación humana explícita, un operador autorizado
   puede ejecutar `terraform apply destroy.tfplan` desde una sesión controlada
   con el mismo backend, variables y plan revisado. No hay apply automático al
   hacer merge ni desde el workflow de plan.

Para un entorno realmente efímero, un responsable puede aprobar
`rds_skip_final_snapshot=true` y/o `ecr_force_delete=true` en la ejecución.
Esas opciones eliminan respectivamente la recuperación final de RDS y todas
las imágenes del repositorio; no son valores por defecto.

## Ejecución local

Con credenciales AWS de un operador autorizado y sin guardar secretos en el
repositorio, genere primero el plan:

```bash
BACKEND_CONFIG=/ruta/privada/backend.hcl \
TF_VAR_FILE=/ruta/privada/dev.tfvars \
./scripts/destroy-dev-local.sh
```

El script requiere `terraform`, `aws`, `kubectl`, `helm` y `jq`; ejecuta el
preflight y deja `terraform/environments/dev/destroy.dev.tfplan` para revisión.
Después de una aprobación humana explícita, aplique exactamente ese flujo con:

```bash
BACKEND_CONFIG=/ruta/privada/backend.hcl \
TF_VAR_FILE=/ruta/privada/dev.tfvars \
./scripts/destroy-dev-local.sh --apply
```

Además de `--apply`, exige escribir `DESTROY-DEV`. Las opciones
`--skip-final-snapshot` y `--delete-ecr-images` son irreversibles y sólo se
usan cuando un responsable las haya aprobado.

## Orden esperado

Una vez retirados los recursos fuera del state, el grafo normalmente se
destruye en este orden: aplicación/Ingress → ALB y add-ons → RDS/node group →
EKS → roles y policies gestionadas → edge/NAT/EIP → subnets/route tables →
VPC. Las claves KMS quedan en borrado diferido por AWS (ventana de 30 días).

Si AWS conserva un ALB, target group o ENI durante su limpieza asíncrona, espere
su desaparición y repita `terraform plan -destroy`; no fuerce el orden con
`-target` ni borre state manualmente.
