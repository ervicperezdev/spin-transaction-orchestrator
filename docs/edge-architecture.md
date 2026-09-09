# Complementos de Internet Edge y EKS
El entorno Terraform implementa esta ruta de tráfico:
```text
Internet → Route 53 → ALB + WAF → AWS Load Balancer Controller → Service → Pods
                         └─ ACM certificate terminates HTTPS
```

`modules/edge` busca la zona alojada pública aprobada de Route 53, crea y
DNS valida un certificado ACM y crea una ACL WAF regional con AWS
reglas comunes administradas y un límite de tasa de IP. La aplicación que recibe Ingress
el certificado y los ARN de WAF como anotaciones. ExternalDNS vigila que Ingress
y escribe el registro de alias ALB solo en la zona hospedada aprobada.
`modules/addons` instala el EKS Pod Identity Agent, AWS Load Balancer
AWS Load Balancer Controller y ExternalDNS a través de Terraform. Cada controller tiene su propio
`aws_eks_pod_identity_association` y función en la que confía únicamente
`pods.eks.amazonaws.com`; no hay ninguna anotación de cuenta de servicio ni clave estática
usado. El rol de AWS Load Balancer Controller gestiona los recursos de ALB; ExternalDNS es
limitado a cambios en la zona alojada de Route 53.
Antes de aplicar, proporcione los `route53_zone_name` y `application_hostname` reales,
revisar la propiedad/validación de ACM y configurar los valores de Helm de implementación con
las salidas `acm_certificate_arn` y `waf_web_acl_arn`. Una única puerta de enlace NAT
es intencional para la línea base de desarrollo; La producción debe utilizar un NAT.
puerta de enlace por zona de disponibilidad o endpoints de VPC aprobados.
## Grupos de seguridad
Terraform posee todos los grupos de seguridad relacionados con las cargas de trabajo. El grupo público ALB permite
sólo TCP/80 (redireccionamiento) y TCP/443 desde Internet, y puede salir sólo a
TCP/8080 en el grupo de nodos trabajadores. El grupo de nodos trabajadores no tiene acceso público;
Acepta TCP/8080 solo del grupo ALB, TCP/10250 solo del cluster
tráfico de grupo y de nodo a nodo mediante autorreferencia. El grupo de API del clúster
Acepta TCP/443 solo de nodos trabajadores. El grupo RDS solo acepta TCP/5432
desde los nodos trabajadores y no tiene salida inicial. Estas referencias de grupo a grupo
Evite listas de IP permitidas obsoletas y mantenga la propiedad fuera del AWS Load Balancer Controller.

## API de administración y complementos CSI

El API de Kubernetes es independiente del ALB de la aplicación. La integración conserva acceso público y privado; `public_access_cidrs` controla la exposición pública, no la conectividad privada. Las reglas del security group del clúster no equivalen a una lista de IP permitidas para el endpoint público. Consulte [EXC-001](security/EXC-001-eks-public-endpoint.md) para alcance, caducidad y cierre.

El módulo `addons` también instala Secrets Store CSI Driver, sus CRDs y el proveedor AWS. Los secretos se montan como archivos y no se sincronizan a Kubernetes Secrets. Debe aplicarse antes del chart de la aplicación; consulte la [guía de IAM y secretos](iam-secrets-deployment-guide.md).
