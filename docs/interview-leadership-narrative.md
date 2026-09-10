# Guion de presentación — Engineering / Platform Security Lead

Este guion presenta el challenge como lo haría un Engineering Lead para una
plataforma transaccional: parte del riesgo de negocio, muestra decisiones
reversibles y termina con la forma de operar y evolucionar el sistema. No
atribuye como desplegado aquello que el repositorio sólo define como IaC o
roadmap.

## Mensaje de apertura (45 segundos)

> Construí un MVP de orquestación de transacciones con una prioridad clara:
> preservar la corrección financiera antes de optimizar por complejidad o
> escala. El servicio separa dominio, casos de uso e infraestructura; persiste
> importes exactos en PostgreSQL y usa idempotencia para evitar duplicados en
> reintentos del cliente. Sobre esa base, dejé una ruta de plataforma en AWS
> que es reproducible y segura por defecto: borde con Route 53, WAF y ALB con
> TLS, EKS, secretos montados desde Secrets Manager y entrega sin claves AWS
> persistentes. Mi enfoque como lead es explicitar los límites: el código y los
> artefactos están en el repositorio, pero un entorno AWS real debe verificarse
> antes de declarar esos controles operativos.

## Orden recomendado para una entrevista (12–15 minutos)

| Tiempo | Tema | Mensaje que debe quedar |
| --- | --- | --- |
| 0:00–1:00 | Problema y criterio | En pagos, integridad, trazabilidad y recuperación segura valen más que entregar muchas funcionalidades. |
| 1:00–3:00 | Flujo crítico y arquitectura | El dominio no depende de HTTP, JPA ni AWS; los límites hacen las reglas auditables y testeables. |
| 3:00–5:00 | Correctitud financiera | `BigDecimal`/`NUMERIC(19,2)`, Flyway e idempotencia con restricción única reducen errores y duplicados. |
| 5:00–7:00 | Plataforma y seguridad | Route 53 → WAF → ALB/ACM → AWS Load Balancer Controller → Service → pods; mínimo privilegio y secretos fuera de Kubernetes Secrets. |
| 7:00–9:00 | Delivery y supply chain | PRs, pruebas, imagen non-root, escaneo, SBOM y firma keyless mediante OIDC protegen el camino a producción. |
| 9:00–11:00 | Operación, incidentes y coste | Señales sin PII, severidad accionable, capacidad medida y límites de conexión antes de escalar. |
| 11:00–13:00 | Riesgos y roadmap | No oculto estados ambiguos: conciliación/outbox, authz y validación operativa de AWS son los siguientes hitos. |
| 13:00–15:00 | Cierre | Conecto decisiones técnicas con ownership, riesgo residual y criterio para cambiar de dirección. |

## 1. Problema y límites del MVP

**Contexto.** Una API recibe una instrucción, valida reglas de negocio, llama a
un proveedor de pagos y registra un resultado aprobado o rechazado. El fallo
más costoso no es un `500`: es cobrar dos veces o afirmar éxito sin evidencia.

**Decisión.** Mantener un servicio síncrono y pequeño, con PostgreSQL como
fuente de verdad; no introducir Kafka, CQRS ni microservicios sin una presión
medida de disponibilidad, latencia o desacoplamiento.

**Coste/beneficio.** Se sacrifica una apariencia de arquitectura “grande” a
cambio de menor superficie operativa, menor coste y una historia de corrección
que el equipo puede comprobar de punta a punta.

**Cómo cerrarlo.** “Primero garantizo que cada decisión financiera sea
explicable; después escalo el componente que una métrica demuestre que es el
cuello de botella.”

## 2. Arquitectura y decisiones de datos

**Arquitectura hexagonal.** REST traduce solicitudes a casos de uso; el dominio
contiene validación y máquina de estados; PostgreSQL/JPA y el proveedor HTTP son
adaptadores. Esto permite probar reglas críticas sin levantar Spring y cambiar
un adaptador sin contaminar el dominio.

**PostgreSQL.** Los importes son `BigDecimal` y `NUMERIC(19,2)`, no punto
flotante. Flyway versiona el esquema. La restricción única de
`idempotency_key` es una última defensa contra carreras concurrentes.

**Trade-off.** PostgreSQL favorece ACID y precisión sobre escalado horizontal
ilimitado. Para este dominio es el intercambio correcto; si creciera la lectura,
primero mediría índices, paginación determinista, retención y réplicas antes de
particionar o cambiar de motor.

## 3. Idempotencia, fallos y reintentos

**Lo que sí resuelve hoy.** Con una `Idempotency-Key` repetida, se devuelve la
transacción persistida sin volver a ejecutar la lógica ni llamar al proveedor.

**Riesgo residual declarado.** Si el proveedor ejecuta el cargo y la aplicación
falla antes de persistirlo, el resultado queda ambiguo. La idempotencia local no
prueba qué ocurrió fuera del servicio.

**Decisión de resiliencia.** Los timeouts de lectura y errores 5xx ambiguos no
se reintentan automáticamente. Sólo errores donde sabemos que el proveedor no
fue alcanzado —por ejemplo conexión rechazada— o un 503 explícito serían
candidatos a un retry acotado con backoff y circuit breaker. Esa política está
propuesta, no implementada aún.

**Siguiente hito.** Registrar una operación/outbox antes de la interacción,
propagar idempotencia al proveedor cuando éste la soporte y ejecutar
conciliación. Es preferible exponer incertidumbre que automatizar un doble cargo.

## 4. Plataforma AWS y seguridad de Kubernetes

**Baseline diseñada en el repositorio.** La ruta prevista es:

```text
Internet → Route 53 → WAF → ALB + ACM → AWS Load Balancer Controller → Service → pods
```

Terraform declara los security groups: Internet sólo llega al ALB por 80/443,
el ALB llega a nodos por 8080 y RDS acepta 5432 desde los nodos. Son referencias
grupo-a-grupo, no listas IP frágiles. RDS y Secrets Manager usan KMS administrado
por AWS.

**Identidad y secretos.** GitHub Actions usa OIDC con un subject limitado para
asumir un rol de despliegue, sin claves AWS de larga duración. Los add-ons de
EKS (AWS Load Balancer Controller y ExternalDNS) usan EKS Pod Identity. La API
usa un rol de workload limitado a los ARNs de secretos aprobados; el Secrets
Store CSI Driver los monta como archivos de sólo lectura y no los sincroniza a
Kubernetes Secrets.

**Hardening de carga.** Helm y Kyverno declaran ejecución non-root, filesystem
de sólo lectura, `seccomp` por defecto, límites de recursos, probes,
`NetworkPolicy` y políticas contra imágenes no aprobadas, privilegiadas o sin
tag fijo.

**Límite importante.** Estos son artefactos desplegables, no evidencia de una
cuenta AWS, clúster, WAF o controlador de admisión actualmente operando. En una
entrevista lo digo de forma explícita y describo la validación post-despliegue.

## 5. Delivery, supply chain y gobierno

La entrega ocurre mediante Pull Request hacia `main`, con CI como punto de
control. La imagen final es distroless y non-root; el pipeline realiza pruebas,
Hadolint, Trivy para vulnerabilidades y secretos, genera SBOM SPDX y, para un
release de producción aprobado, firma imagen y attestación SBOM con Cosign
keyless/OIDC. La verificación se hace contra identidad de workflow y digest.

La política no es “pasar el pipeline a cualquier coste”: hallazgos HIGH/CRITICAL
fallan; una excepción temporal debe ser concreta, aprobada y fechada. Un
admission controller que exija firma/SBOM es una evolución pendiente, no una
afirmación de control activo.

## 6. Operación, incidentes y FinOps

**Observabilidad segura.** La API emite métricas de resultado/latencia del
proveedor y logs JSON mínimos con `traceId`; no registra importes, cuerpos,
claves de idempotencia, identificadores de proveedor ni secretos. El catálogo
propone correlación con WAF, ALB, EKS y RDS, pero dashboards, alarmas, SIEM y
SOC aún requieren habilitación por el propietario de la plataforma.

**Incidentes.** P1 representa compromiso confirmado, fraude activo o impacto
alto: se pagina de inmediato a Incident Commander, Security Lead y Platform.
P2 es sospecha creíble y se trata en una hora. Antes de contener, se preserva
evidencia; después se rota, aísla o revierte mediante un cambio autorizado.

**FinOps y escala.** El HPA de producción parte de 3–20 réplicas con CPU al 60%,
pero no se incrementa a ciegas. Antes se calcula:

```text
réplicas máximas × Hikari maximumPoolSize + reserva de admin/migraciones < conexiones máximas de RDS
```

Se revisan p95/p99, errores, presión de CPU/memoria, pods pendientes,
conexiones/latencia RDS y coste de NAT, WAF y logs. Para desarrollo, un NAT por
coste es una concesión conocida; una necesidad multi-AZ requiere NAT por zona o
endpoints privados aprobados.

## 7. Riesgos, roadmap y criterio de liderazgo

Presenta el backlog por reducción de riesgo, no por moda tecnológica:

1. OAuth2/JWT, autorización y auditoría para cerrar el límite de identidad.
2. Outbox, conciliación e idempotencia en el proveedor para resolver estados ambiguos.
3. Retry seguro, circuit breaker, alertas y pruebas de fallo/carga.
4. Provisión y evidencia operativa de los controles AWS/EKS/RDS ya definidos en IaC.
5. Pruebas de contrato del proveedor, backup/restore y ejercicios de incidente.

La IA se utilizó para acelerar documentación y revisión, nunca como autoridad
de seguridad ni con secretos o datos productivos. Mantener esta declaración
refuerza una postura de gobierno responsable.

## Preguntas probables y respuestas de dos minutos

### ¿Por qué EKS y no ECS Fargate?

Para un único servicio y un equipo sin experiencia Kubernetes, elegiría ECS
Fargate: reduce coste y carga operativa. EKS se eligió aquí porque el objetivo
del challenge es demostrar controles de plataforma que necesito poder gobernar:
NetworkPolicy, Kyverno, hardening de pods, Helm y una integración rica de
observabilidad. Acepto el coste de ciclo de vida de clúster y add-ons porque hay
una razón concreta; no lo vendería como opción universal. La decisión se
revisaría con tamaño de equipo, SLOs, coste base y madurez de operación.

### ¿La idempotencia elimina el riesgo de doble cargo?

No por sí sola. El índice único protege reintentos concurrentes que vuelven a
mi base de datos y evita repetir una transacción ya persistida. Pero si el
proveedor cobra y el proceso cae antes de guardar el resultado, no tengo un
hecho suficiente para repetir con seguridad. Por eso no reintento timeouts de
lectura automáticamente: los clasifico como ambiguos y priorizo outbox,
idempotencia propagada y conciliación. Prefiero devolver una incertidumbre
manejable a ocultar una posible duplicación financiera.

### ¿Cómo pruebas que la seguridad funciona si está en Terraform/Helm?

Separaría validación estática de evidencia operativa. En CI valido formato,
políticas y artefactos; antes de producción aplico en una cuenta controlada y
compruebo identidad efectiva, security groups, Ingress/ACM/WAF, montaje CSI sin
Kubernetes Secrets, NetworkPolicies y los controles de admisión. También ejecuto
smoke desde la red correcta y pruebas de detección para CloudTrail, GuardDuty,
Security Hub y logs WAF. Hasta reunir esa evidencia, describo el repositorio
como diseño implementable, no como control desplegado.

### ¿Qué harías ante un posible acceso anómalo a un secreto?

Primero preservaría y correlacionaría evidencia: identidad/rol, región,
`eventID` de CloudTrail, lecturas posteriores y hallazgos de GuardDuty/Security
Hub, sin copiar valores secretos al ticket. Si hay éxito fuera de la identidad
esperada, lo trataría como P1: coordino con Incident Commander, Security y
Platform para rotar el secreto, invalidar credenciales aguas abajo y aislar la
carga de trabajo de forma aprobada. Después valido recuperación, impacto en
transacciones y cierro sólo con evidencia y acciones correctivas con dueño y
fecha.

### ¿Cómo evitarías que el escalado degrade la base de datos?

El HPA no es una autorización para abrir conexiones ilimitadas. Defino requests
y límites, el máximo de réplicas y un pool Hikari conservador a partir del
presupuesto real de conexiones de RDS, dejando reserva para operaciones y
migraciones. Luego pruebo carga observando p95/p99, conexiones, latencia y pods
pendientes. Si el proveedor se degrada, aplico backpressure, timeout y circuit
breaker; escalar pods frente a un proveedor o RDS saturado sólo multiplica el
problema.

## Cierre (30 segundos)

> Mi aporte no es sólo elegir herramientas. Es hacer explícita la relación entre
> una decisión, el riesgo que reduce, su coste operativo y la evidencia necesaria
> para confiar en ella. En un sistema transaccional, ese rigor —incluidos los
> límites y el riesgo residual— es lo que permite entregar rápido sin normalizar
> sorpresas de seguridad o corrección.

## Referencias del repositorio

- `docs/architecture.md` y `docs/adr/ADR-001-hexagonal-architecture.md`
- `docs/adr/ADR-002-postgresql-over-nosql.md` y `docs/adr/ADR-003-idempotency-key.md`
- `docs/adr/ADR-004-eks-over-ecs.md`, `docs/edge-architecture.md` y `docs/iam-secrets-deployment-guide.md`
- `docs/security.md`, `docs/threat-model.md` y `docs/cloud-security-operations.md`
- `docs/observability.md`, `docs/incident-response.md`, `docs/finops-scalability.md`
- `docs/limitations-roadmap-ai.md` y `docs/trunk-based-and-ci-governance.md`
