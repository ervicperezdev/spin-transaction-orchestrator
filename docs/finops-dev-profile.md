# Perfil mínimo de coste para desarrollo

## Objetivo y límite

El entorno `terraform/environments/dev` mantiene el recorrido que valida el
challenge: EKS en dos AZ, ECR, una única NAT Gateway, ALB público, certificado
ACM, Route 53, AWS Load Balancer Controller, ExternalDNS, Secrets Store CSI
Driver, EKS Pod Identity Agent y PostgreSQL administrado. ACM público no tiene
coste de certificado. Producción debe declarar sus propios valores: los módulos
conservan valores seguros/HA por defecto y solo `dev` selecciona este perfil.

## Cambios de coste en dev

| Servicio | Perfil dev | Perfil retenido para producción / motivo |
| --- | --- | --- |
| EKS workers | `t3.medium`, mínimo/deseado 1 y máximo 2 | Capacidad por ambiente; conserva EKS y los add-ons requeridos. |
| Logs EKS | Solo `api` y `audit` | Conserva evidencia de seguridad; `authenticator` queda fuera de dev. |
| RDS PostgreSQL | `db.t4g.micro`, Single-AZ, un día de backup, sin exportación de logs y sin deletion protection | El módulo conserva `db.t4g.medium`, Multi-AZ, 7 días, logs y protección por defecto. |
| WAF | No se crea y Helm no emite la anotación del ACL | El módulo tiene WAF habilitado por defecto y `values-prod.yaml` lo mantiene habilitado. |
| VPC/edge | Dos AZ, NAT única, ALB, ACM y Route 53 | Necesarios para FQDN HTTPS y smoke post-despliegue. |

Quedan aplazados para dev: alta disponibilidad de RDS, WAF, retención de
backups/logs más larga y más de un nodo base. No se eliminan VPC, EKS, ECR, ALB
ni Route 53.

## Riesgos aceptados en desarrollo

- Una caída de AZ o una falla de instancia RDS interrumpe la base de datos;
  Single-AZ no proporciona failover.
- La recuperación se limita al último día de backups y la base puede borrarse
  accidentalmente si se autoriza un cambio destructivo.
- Sin WAF dev queda expuesto a tráfico web no filtrado; el ALB sigue usando TLS,
  security groups y las políticas de red de Kubernetes.
- Un nodo deja poca holgura para actualizaciones, add-ons y picos. Si hay pods
  pendientes, se permite crecer hasta dos nodos antes de modificar el perfil.

Las exclusiones estáticas de IaC son deliberadamente puntuales: la regla de
EKS se suprime porque la validación del módulo exige `api` y `audit`, algo que
el análisis no deduce a través de variables; la regla de logging de RDS se
suprime únicamente para el valor vacío de `dev` descrito arriba. No son una
exclusión global del scanner ni una autorización para producción.

Estos riesgos son exclusivos de `dev`, están sujetos a revisión antes de
promover cambios de arquitectura, y no autorizan rebajar los controles de
producción.

## Despliegue, smoke y rollback

1. Revisar el plan con el `terraform.tfvars` privado y confirmar que solo cambia
   RDS, node group, logs de EKS y WAF; no aprobar destrucciones de VPC, EKS,
   ECR, ALB o Route 53.
2. Aplicar únicamente con aprobación explícita y una ventana de cambio.
3. Desplegar Helm con `values-dev.yaml`. Con `ingress.waf.enabled: false` la
   anotación `alb.ingress.kubernetes.io/wafv2-acl-arn` queda ausente, mientras
   el certificado ACM, ExternalDNS y el FQDN continúan configurados.
4. Ejecutar el smoke público del pipeline (`.github/scripts/post-deploy-smoke.sh`)
   contra el FQDN HTTPS.

Para revertir, restaurar `enable_waf = true`, los parámetros RDS de alta
disponibilidad y la capacidad de nodos aprobada, actualizar los valores Helm
con el ARN actual del WAF y aplicar el plan revisado. El rollback de capacidad
no sustituye una restauración de datos: ante pérdida de datos, usar el backup
automatizado disponible de RDS.

## Medición y verificación posterior

Antes y después de aplicar, registrar el coste amortizado por servicio para el
mismo intervalo completo (recomendado: 14 días) en Cost Explorer, filtrado por
la etiqueta `Environment=dev`. Ejemplo con AWS CLI:

```bash
aws ce get-cost-and-usage \
  --time-period Start=YYYY-MM-DD,End=YYYY-MM-DD \
  --granularity DAILY \
  --metrics AmortizedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Tags":{"Key":"Environment","Values":["dev"]}}'
```

Conservar la exportación aprobada junto con el cambio y comparar, al menos,
Amazon RDS, Amazon Elastic Compute Cloud - Compute, Amazon Elastic Kubernetes
Service, AWS WAF, Elastic Load Balancing, AWS NAT Gateway/EC2-Other,
CloudWatch y Route 53. El coste real no se puede afirmar antes de `apply` y de
que Cost Explorer procese el uso; la aceptación financiera se completa con esa
evidencia, no con una estimación estática.
