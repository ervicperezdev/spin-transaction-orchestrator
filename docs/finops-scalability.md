# FinOps y línea base de escalabilidad
## Alcance y supuestos
Esta es una base de planificación de capacidad, no una factura de AWS ni una afirmación de que el
Se ha aprovisionado el entorno. Los precios varían según la región, el uso, los compromisos,
transferencia de datos y cambios de precios de AWS; estimarlos con el precio de AWS
Calculadora que utiliza la región de producción y los volúmenes observados antes de la aprobación.
La línea de base es una API de transacciones síncrona y pública con PostgreSQL como
sistema de registro. Se supone una carga de producción inicial modesta, un VPC de dos AZ,
tres réplicas de API y un grupo de nodos EKS administrado del tamaño adecuado para transportar la API más
los complementos de plataforma necesarios. La ejecución de la transacción debe seguir siendo idempotente;
escalar los pods de aplicaciones nunca hace que la base de datos o el proveedor de pagos
infinitamente escalable.
## Por qué EKS a pesar de su coste
EKS **no** se selecciona deliberadamente como la forma más barata de ejecutar una API. ECS
Fargate es la opción de menor costo de operación y base para un solo
servicio sin experiencia en Kubernetes. EKS se justifica aquí por la seguridad.
y requisitos de plataforma ya representados en este repositorio: NetworkPolicy,
Configuración de seguridad del pod, políticas de admisión de Kyverno, entrega basada en Helm, AWS
AWS Load Balancer Controller, ExternalDNS y EKS Pod Identity. Esto permite que el
El equipo aplica y audita los mismos controles de Kubernetes en cargas de trabajo futuras.
La decisión debe revisarse si la plataforma sigue siendo una única plataforma de bajo volumen.
El servicio o el equipo no pueden operar complementos y actualizaciones de EKS. En ese caso,
trasladar la carga de trabajo a ECS Fargate en lugar de conservar EKS para la demostración
valor solo. ADR-004 registra la compensación arquitectónica correspondiente.
## Controladores y controles de costos
| Component | Baseline / driver | Control and review trigger |
| --- | --- | --- |
| EKS | Fixed cluster control-plane fee plus EC2 worker capacity, EBS, and add-ons. Requests, not limits, determine bin-packing. | Start with the current 2-node on-demand group and right-size from 14 days of CPU/memory percentiles. Review when requested capacity exceeds 70% of allocatable capacity or pods remain pending. Use committed compute only after stable utilization is proven. |
| API pods | Production requests are 500m CPU / 1 GiB per pod; CPU limit is 1 vCPU and memory limit 2 GiB. Three replicas reserve 1.5 vCPU / 3 GiB before add-ons. | Keep requests at approximately P95 observed usage plus headroom. Lower chronic over-requesting; raise memory requests after OOM/restart evidence. Do not set CPU limits so low that throttling invalidates latency measurements. |
| RDS PostgreSQL | Instance-hours, Multi-AZ standby, storage, I/O, backups and log export. Current `db.t4g.medium`, Multi-AZ, 20–100 GiB autoscaling storage is an availability-first baseline. | Review CPU, free memory, connections, read/write latency, storage growth and backup retention weekly. Increase class or storage before sustained saturation; add read replicas only for measured read pressure. Connection limits must be budgeted across maximum API replicas and pool size. |
| NAT gateway | Hourly gateway charge and per-GB processing. The current single NAT is low-cost but is a cross-AZ availability and transfer-cost trade-off. | Production should use one NAT per AZ when availability needs justify it. First add gateway/interface VPC endpoints for high-volume AWS traffic (for example S3, ECR API/DKR, STS, CloudWatch Logs and Secrets Manager where applicable), then compare remaining NAT GB and cross-AZ traffic. |
| ALB, Route 53, ACM and WAF | ALB hours/LCUs, DNS zones/queries, WAF Web ACL/rules/requests and logging destination. ACM public certificates have no certificate fee; logs can dominate at high volume. | Keep WAF managed/rate rules minimal and intentional; review LCU dimensions and WAF request/rule counts monthly. Sample/redact and retain WAF/ALB/application logs according to the approved retention policy, not indefinitely. |
| Observability | CloudWatch metric, ingestion, retention, query, trace and alarm charges grow with cardinality and volume. | Use the bounded-cardinality signals in `docs/observability.md`; exclude secrets and unbounded identifiers. Set retention per log class and alert on ingestion anomalies. |

Secrets Manager, AWS Load Balancer Controller, ExternalDNS y EKS Pod Identity
forman parte de la línea base aprobada. Operador de secretos externos y
Las claves KMS administradas por el cliente están intencionalmente fuera del alcance y no deben
añadido silenciosamente a las estimaciones.
## Política de escalamiento y barreras de seguridad
El gráfico Helm utiliza un HPA con límites de producción de 3 a 20 réplicas y un 60 %.
Objetivo de la CPU. Ese objetivo es sólo una hipótesis de partida: validarlo bajo un
prueba de carga representativa después de que el servidor de métricas y el aprovisionamiento de capacidad sean
presente. Empareje el HPA con el escalamiento de la capacidad del nodo; HPA por sí sola no puede programar una
pod en un grupo de nodos completo.
Antes de aumentar `maxReplicas`, calcule el límite de conexión de la base de datos:
`maximum API replicas × Hikari maximumPoolSize + admin/migration reserve < RDS max connections`
Establecer un grupo Hikari conservador explícitamente para la clase RDS elegida, reservar
conexiones para operaciones y migraciones, y latencia del proveedor de pruebas de carga.
Se prefieren la contrapresión, los tiempos de espera y la interrupción del circuito a los grupos ilimitados.
o reintentos incontrolados. PDB `minAvailable: 2` protege una réplica de tres
despliegue de producción durante interrupciones voluntarias; revisarlo junto con
objetivos de disponibilidad y recuento de réplicas.
Las revisiones de capacidad utilizan latencia p95/p99, tasa de error, aceleración de la CPU y memoria.
conjunto de trabajo/OOM, réplicas HPA deseadas versus actuales, pods pendientes, nodo
recursos asignables/solicitados, conexiones RDS/latencia/almacenamiento y NAT/WAF/
volumen de registro. Se acepta un cambio sólo cuando mejora un cuello de botella medido.
sin vulnerar la base de datos ni los presupuestos de los proveedores.
## Datos y evolución asincrónica
El punto final del historial de transacciones ya utiliza paginación de conjunto de claves determinista
(`createdAt DESC, id DESC`) y tiene un índice de base de datos coincidente. Guárdalo en su lugar
de paginación desplazada a medida que la tabla crece: evita el escaneo progresivo y
descartando páginas anteriores y es estable cuando llegan nuevas transacciones.
Kafka no es una dependencia básica. Introducirlo sólo cuando el acoplamiento esté medido.
entre la ruta de transacción sincrónica y las causas de los efectos secundarios posteriores
fallas de latencia, disponibilidad o rendimiento. Utilice un patrón de bandeja de salida, idempotente
consumidores, gobernanza de esquema/versión, retención y propiedad de reproducción/runbook;
De lo contrario, Kafka agrega costos operativos y modos de falla sin resolver un problema.
restricción actual.
## Puntos de control de decisión
| When | Decision |
| --- | --- |
| Before production | Pricing Calculator estimate, load test, RDS connection budget, log retention, NAT endpoint analysis and an owner for EKS upgrades/add-ons. |
| At sustained 60–70% utilization or latency SLO risk | Right-size pod requests/nodes and RDS from measurements; do not scale replicas blindly. |
| At AZ availability requirement | Move from the single development NAT to NAT per AZ and validate endpoint coverage/egress paths. |
| At material read volume or history growth | Re-check index/query plans, partitioning/archive policy and read-replica economics. |
| At asynchronous side-effect pressure | Evaluate outbox + Kafka only with a quantified SLO/cost case and operational owner. |
