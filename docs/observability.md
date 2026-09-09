# Catálogo de señales de observabilidad
## Alcance y límite de seguridad
Este repositorio instrumenta la API de transacciones y proporciona algunas métricas de AWS.
fuentes a través de Terraform. **No** implementa un transportista de registros, OpenTelemetry
recopilador, paneles o alarmas de CloudWatch. Esas integraciones productivas son
P3 funciona y debe ser operado por el propietario de la plataforma.
La detección correspondiente de CloudTrail, GuardDuty, Security Hub y WAF-log
La estrategia está documentada en `docs/cloud-security-operations.md`. También es un
solo diseño: sin seguimiento de auditoría, agregador de búsqueda, destino de registro o enrutamiento SOC
es proporcionado por este repositorio.
Secrets Manager es la fuente de confianza para las credenciales. Valores secretos montados por
el controlador CSI de AWS Secrets Store, las credenciales del proveedor de pagos, los ID de transacciones,
claves de idempotencia, referencias de proveedores, importes, monedas, solicitud/respuesta
Los cuerpos y los motivos de rechazo están prohibidos en registros, métricas y seguimientos.
## Señales de aplicación
| Signal | Type | Dimensions / fields | Purpose | Safety |
| --- | --- | --- | --- | --- |
| `payment.provider.requests` | Counter | `outcome`: `approved`, `rejected`, `http_error`, `unavailable`, `invalid_response` | Provider availability and business-result rate | No transaction or provider identifiers |
| `payment.provider.request.duration` | Timer | Same bounded `outcome` | Provider latency by result class | No request payload or URL |
| `payment_provider_request_completed` | Structured log event | `traceId` MDC field, `outcome` | Correlate a provider attempt to the inbound request | No exception stack, status body, or financial fields |
| `X-Correlation-ID` | Response header / MDC `traceId` | UUID only; supplied valid UUID is echoed, otherwise generated | Request-to-log correlation | Header values are validated to avoid log injection |
| `/actuator/health` | Health probe | Overall status only | ALB/Kubernetes liveness and readiness | Component details are disabled |
| `/actuator/metrics` | Actuator metric discovery | Metric names and meter measurements | Restricted operational metric readout | `/actuator/env` and other sensitive endpoints remain unexposed |

Los registros de la consola utilizan el formato JSON estructurado Logstash de Spring Boot. el emitido
`traceId` es un identificador de correlación, no un seguimiento distribuido de OpenTelemetry;
La propagación/exportación de OTel se difiere explícitamente a P3.
## Señales de AWS y Kubernetes
| Source | Signal family | Use | Ownership / status |
| --- | --- | --- | --- |
| Route 53 | DNS health checks and query/health-check metrics | Detect DNS resolution and endpoint-health issues | AWS source; collection/alarms are not created here |
| AWS WAF regional | Allowed/blocked requests, rate-based rule matches | Detect attack traffic and false-positive blocks | Terraform enables WAF CloudWatch metric names; alerts are not created here |
| ALB / ACM | ALB 4xx/5xx, target health, latency, TLS certificate expiry | Detect edge and certificate failures | AWS source; dashboards/alarms are not created here |
| EKS | Control-plane, node, pod, deployment, and container resource signals | Detect cluster/workload health and saturation | EKS source; managed collection is out of repository scope |
| RDS PostgreSQL | CPU, connections, storage, latency, failover events | Detect database capacity and availability risks | RDS source; alarms are not created here |

AWS Load Balancer Controller y ExternalDNS conservan EKS Pod Identity. Cualquiera
La futura integración de telemetría no debe ampliar esos roles ni utilizar aplicaciones.
secretos como credenciales de telemetría.
## Guía del operador
Restringir el acceso del Actuador a la red de operaciones/clúster; no es publico
API. Cree paneles y alertas a partir del catálogo anterior únicamente con etiquetas delimitadas.
Como mínimo, página sobre indisponibilidad sostenida de proveedores, objetivos insalubres de ALB,
Agotamiento de recursos RDS, aumentos repentinos de bloques WAF y certificados ACM que caducan. sintonizar
umbrales desde las líneas base de producción antes de habilitar la paginación.
