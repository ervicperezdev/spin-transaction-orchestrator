## Excepciones de Checkov revisadas

Las excepciones de infraestructura se conservan junto al recurso mediante
`#checkov:skip=<id>:<justificación>`. No silencian hallazgos generales: cada una
corresponde a una limitación de autorización de AWS o a una decisión de diseño
con controles compensatorios identificados.

| Check | Recurso | Motivo y control compensatorio |
| --- | --- | --- |
| CKV_AWS_111, CKV_AWS_356 | AWS Load Balancer Controller | Varias API `Describe` y acciones de ELBv2 requeridas por el controlador no permiten autorización por recurso. El controlador usa una service account dedicada y sólo administra recursos etiquetados/propiedad del clúster. |
| CKV_AWS_356 | ExternalDNS | `ListHostedZones` y `ListHostedZonesByName` no admiten el ARN de hosted zone; la mutación `ChangeResourceRecordSets` permanece limitada a `hosted_zone_arn`. |
| CKV_AWS_260 | Security group del ALB | El ALB público acepta puerto 80 únicamente para redirigir a HTTPS. No existe acceso HTTP al workload y el puerto de aplicación se limita al security group de nodos. |
| CKV2_AWS_5 | Security group del ALB | El ALB es creado dinámicamente por AWS Load Balancer Controller, por lo que el análisis estático no puede enlazar su attachment. |
| CKV2_AWS_31 | WAF | El destino y la política de logs son responsabilidad del servicio de logging central de la cuenta. Antes de producción debe verificarse que el ACL esté incluido en ese destino; no se crea un destino duplicado desde este módulo. |
| CKV_AWS_382 | Security groups EKS | EKS requiere salida de retorno y hacia endpoints AWS/NAT para control plane, DNS e imágenes. La entrada sigue restringida. La reducción futura requiere VPC endpoints y NetworkPolicies validadas. |
| CKV_AWS_341 | Launch template EKS | El hop limit 2 soporta rutas de red de pods que usan IMDS; IMDSv2 es obligatorio y los tags de metadata están deshabilitados. |
| CKV_AWS_39 | EKS public endpoint | Excepción temporal EXC-001: acceso público limitado por CIDR para runners hospedados de GitHub durante desarrollo; el endpoint privado también permanece activo. Debe retirarse al habilitar runner privado. |
| CKV_AWS_109, CKV_AWS_111, CKV_AWS_356 | KMS key policies | Las políticas de una CMK requieren el statement administrativo de account root y `Resource="*"` por diseño de KMS; los consumidores de cifrado reciben grants del servicio, no permisos IAM amplios. |
| CKV2_AWS_69 | RDS PostgreSQL | TLS se fuerza con `force_ssl=1` en el parameter group PostgreSQL adjunto. El check de grafo no sigue esa relación. |

Las demás alertas del análisis se remedian en Terraform: cifrado KMS de ECR y
Secrets de EKS, logs completos de EKS y VPC Flow Logs, default security group
vacío, reglas WAF contra entradas maliciosas, y endurecimiento operativo de RDS.
