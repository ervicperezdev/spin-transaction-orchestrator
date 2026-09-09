# ADR-004: Amazon EKS sobre ECS Fargate
**Estado:** Aceptado
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
---
## Contexto
El orquestador de transacciones debe implementarse en una plataforma de orquestación de contenedores. Existen dos opciones principales dentro del ecosistema de AWS: Amazon EKS (Kubernetes administrado) y Amazon ECS (con Fargate). La elección afecta la complejidad operativa, la expresividad de los controles de seguridad y la amplitud de las capacidades de ingeniería de plataformas que se pueden demostrar.
---
## Decisión
Apunte a **Amazon EKS** con grupos de nodos administrados cuando la infraestructura esté
aprovisionado. Este ADR registra una elección de plataforma prevista, no una afirmación de que una
El entorno EKS existe actualmente.
El principal impulsor de este contexto es la capacidad de demostrar toda la amplitud de los controles de seguridad de Kubernetes:
- `NetworkPolicy` para la segmentación del tráfico a nivel de pod (denegar todo por defecto, reglas de permiso explícitas)
- `PodSecurityContext` con `runAsNonRoot`, `readOnlyRootFilesystem`, `seccompProfile: RuntimeDefault`
- Controlador de admisión **Kyverno** que aplica políticas de seguridad en todo el clúster (bloquea pods privilegiados, aplica política de extracción de imágenes, exige límites de recursos)
- **IRSA** (roles de IAM para cuentas de servicio) para acceso a la API de AWS con privilegios mínimos sin credenciales a nivel de nodo
- **Helm** para implementaciones reproducibles y controladas por versiones
- **HPA** (Horizontal Pod Autoscaler) para escalado basado en carga
---
## Consecuencias
**Positivo:**
- Superficie primitiva de seguridad completa de Kubernetes: NetworkPolicy, Pod Security Admission, Kyverno, IRSA, perfiles seccomp.
- Los gráficos de timón proporcionan una infraestructura revisable y con plantillas como código.
- Integración de observabilidad más rica: métricas de Prometheus, paneles de Grafana, envío de registros estructurados.
- Demuestra la profundidad de la ingeniería de seguridad de K8 relevante para los roles de la plataforma fintech.
**Negativo:**
- Complejidad operativa significativamente mayor que ECS Fargate: actualizaciones de clústeres, administración de grupos de nodos, ciclo de vida de complementos (CoreDNS, kube-proxy, VPC CNI).
- Costo base más alto que Fargate (capacidad de nodo siempre activo frente a facturación por tarea).
- Requiere experiencia de K8 en el equipo de operaciones; un equipo sin él se enfrenta a una pronunciada curva de aprendizaje.
---
## Alternativas consideradas
| Alternative | Reason Rejected (for this context) |
|---|---|
| **ECS Fargate** | Simpler and lower-cost for a single service; lacks NetworkPolicy, Kyverno, and the full K8s security primitive surface. **Preferred for a single-service production system without K8s expertise on the team.** |
| **AWS Lambda** | Event-driven model does not map naturally to synchronous REST + persistent database connection pooling; cold starts add latency variance unacceptable for payment SLAs |

> **Nota de compensación:** Para un sistema de producción de servicio único donde el equipo no tiene experiencia en Kubernetes, **ECS Fargate sería la opción recomendada**: menor complejidad, menor costo y AWS administra el plano de control por completo. EKS se elige aquí específicamente para demostrar la profundidad de la seguridad de la plataforma.
