# Arquitectura
## Implementación actual
El servicio es una API REST Java 21/Spring Boot con persistencia PostgreSQL.
Sigue una estructura de puertos y adaptadores:
```text
HTTP REST controller -> application use cases -> domain model
                                  |                    |
                         repository/provider ports     |
                                  |                    |
                    JPA/PostgreSQL and HTTP provider adapters
```

- `domain`: estado de transacción y reglas de validación, sin importaciones de framework.
- `application`: comandos, consultas, casos de uso y puertos de entrada/salida.
- `adapter/in/rest`: mapeo de solicitudes, validación, mapeo de errores y anotaciones OpenAPI.
- `infrastructure`: cableado Spring, persistencia JPA/Flyway y adaptador de proveedor de pago HTTP.
La ruta de escritura síncrona es: validar solicitud, buscar una idempotencia opcional
tecla, llame al proveedor configurado, transfiera la transacción a `APPROVED` o
`REJECTED`, luego persista. `GET /transactions` lee una página determinista
(tiempo creado descendente, luego id descendente).
## Intención de implementación frente a evidencia presente
El perímetro de Internet previsto es Route 53 → ALB protegido por AWS WAF (HTTPS terminado
con ACM) → AWS Load Balancer Controller → Kubernetes Service → pods. El
controller y ExternalDNS usan EKS Pod Identity; los detalles están en
`docs/edge-architecture.md`.
El repositorio contiene plantillas de Helm, políticas de Kyverno, Terraform y GitHub.
Definiciones de flujo de trabajo de acciones. Son artefactos desplegables, no evidencia de que
una cuenta de AWS, un clúster de EKS, un WAF, una instancia de RDS, una pila de monitoreo o una admisión
El controlador está actualmente ejecutándose. Esos controles ambientales deben verificarse.
en el momento del despliegue.
La imagen del contenedor se construye a partir de una etapa Maven y ejecuta el JAR empaquetado como el
Usuario `nonroot` de la imagen sin distribución. Helm también declara sondas, valores de recursos,
un contexto de seguridad, AWS Secrets Store CSI `SecretProviderClass`, y
Plantillas de política de red.
## Registros de decisiones
El fundamento de las principales opciones se encuentra en `docs/adr/`:
- ADR-001 — puertos y adaptadores.
- ADR-002 — PostgreSQL y almacenamiento decimal exacto.
- ADR-003: claves de idempotencia proporcionadas por el cliente.
- ADR-004: EKS como opción de implementación de Kubernetes prevista.
- ADR-005: la política de reintento/disyuntor es una decisión de la hoja de ruta, no el código actual.
