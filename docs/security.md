# Arquitectura de seguridad: Spin Transaction Orchestrator
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
---
> **Alcance:** Este documento distingue los controles del repositorio de la implementación.
> intención. Las definiciones de Helm, Kyverno, Terraform y workflows están versionadas en
> este repositorio; su aplicación en un entorno AWS/EKS no ha sido
> verificado aquí. La validación a nivel de aplicación, el mapeo de errores y el contenedor.
> Dockerfile se puede inspeccionar y probar localmente.
## Capas de defensa en profundidad
La implementación de destino aplica controles de seguridad en cada capa de la pila. No
el control único se considera suficiente; cada capa asume que la anterior puede
ser omitido.
```
Internet
   │
   ▼ [1] AWS WAF
   │  Rate limiting, IP reputation, OWASP managed rules
   │
   ▼ [2] Application Load Balancer
   │  TLS termination, connection limits, access logging
   │
   ▼ [3] Kubernetes NetworkPolicy
   │  Deny-all default; explicit allow: ingress from ALB only,
   │  egress to RDS subnet and provider endpoint only
   │
   ▼ [4] IRSA (IAM Roles for Service Accounts)
   │  Pod-level AWS identity; least-privilege policy;
   │  no node-level credentials accessible to the pod
   │
   ▼ [5] Application Validation
   │  @Valid Bean Validation on all inputs; GlobalExceptionHandler
   │  returns opaque errors; BigDecimal for monetary arithmetic
   │
   ▼ [6] Distroless Container Image
      No shell, no package manager, no debug tools;
      runAsNonRoot + readOnlyRootFilesystem + seccomp RuntimeDefault
```

### Resumen de capas
| Layer | Control | Threat Addressed |
|---|---|---|
| AWS WAF | Rate limiting, IP reputation, OWASP rules | DDoS, volumetric attacks, known exploit patterns |
| ALB | TLS termination, connection limits | Man-in-the-middle, connection floods |
| K8s NetworkPolicy | Deny-all + explicit allow rules | Lateral movement within cluster, pod escape |
| IRSA | Least-privilege IAM policy per pod | Excessive AWS permissions, credential theft from node metadata |
| App validation | `@Valid`, `GlobalExceptionHandler`, `BigDecimal` | Injection, data corruption, information disclosure via errors |
| Distroless | No shell/tools + security context | Container escape, privilege escalation, post-exploitation tooling |

---
## Seguridad de la cadena de suministro
Las amenazas al proceso de compilación se tratan con el mismo rigor que las amenazas en tiempo de ejecución.
| Stage | Control | Purpose |
|---|---|---|
| Pre-push / CI | **Gitleaks** | Detect secrets accidentally committed to source control |
| CI — dependencies | **SCA (Trivy filesystem scan)** | Identify known CVEs in Maven dependencies |
| CI — container | **Trivy image scan** | Detect vulnerabilities in the final Docker image layers |
| CI — artifacts | **SBOM generation** (CycloneDX) | Full inventory of all components in the image for audit and compliance |
| Registry | **Cosign image signing** | Cryptographic provenance: only CI-built, verified images are deployed |
| Dependencies | **Dependabot** | Automated PRs for dependency version updates with CVE context |

La canalización aplica una política **a prueba de fallos**: un hallazgo de Trivy de alta gravedad o una detección de Gitleaks bloquea la fusión.
La salida del escáner se clasifica como un hallazgo, no se acepta automáticamente como tiempo de ejecución
riesgo. La prioridad consciente del contexto, SLA de corrección, excepción y verificación
Los requisitos se definen en
[`vulnerability-risk-assessment.md`](security/vulnerability-risk-assessment.md).
---
## Gestión secreta
Los secretos nunca se almacenan en el código fuente, imágenes de Docker o manifiestos de Kubernetes enviados a git.
```
AWS Secrets Manager  (source of truth)
        │
        ▼  (AWS Secrets Store CSI driver)
Read-only pod volume  (no Kubernetes Secret copy)
        │
        ▼  (Spring Boot configtree import)
Application process  (reads mounted files; never logs secret values)
```

| Secret Type | Storage | Rotation |
|---|---|---|
| RDS credentials | AWS Secrets Manager | RDS managed rotation (automated) |
| Provider API key | AWS Secrets Manager | Manual rotation on compromise; planned periodic rotation |
| TLS certificates | ACM (ALB) | ACM automatic renewal |
| Application credentials | Mounted directly from Secrets Manager using CSI | Restart pods after rotation to reload configuration |

**Lo que nunca se hace:**
- Secretos en archivos `.env` comprometidos con git (se aplica `.gitignore`; Gitleaks detecta infracciones)
- Secretos integrados en las imágenes de Docker (verificados mediante escaneo de imágenes de Trivy)
- Claves de acceso estáticas de AWS en GitHub Actions (OIDC las elimina)
---
## Identidad y Acceso
### CI/CD: GitHub Actions
GitHub Actions se autentica en AWS mediante **OIDC** (OpenID Connect). No se almacenan claves de acceso estáticas de AWS como secretos de GitHub. La política de confianza de OIDC limita los permisos al repositorio y a la sucursal específicos, evitando la escalada de privilegios entre repositorios.
### Pods: IRSA (roles de IAM para cuentas de servicio)
Cada pod asume una función de IAM vinculada a su cuenta de servicio de Kubernetes a través de IRSA. La política de rol sigue el privilegio mínimo: solo el ARN de Secrets Manager específico que el pod necesita leer y el recurso RDS específico al que se conecta. El aislamiento a nivel de pod significa que un pod comprometido no puede acceder a las credenciales de otros servicios.
RDS y Secrets Manager utilizan claves KMS administradas por AWS; la plataforma no crea
o administrar claves KMS de clientes para estos recursos.
### Clúster: Admission controller de Kyverno
Las políticas de Kyverno imponen invariantes de seguridad en todo el clúster:
- Bloquear pods solicitando `privileged: true`
- Requiere `runAsNonRoot: true` en todos los pods
- Requerir recurso `limits` en todos los contenedores.
- Aplicar `imagePullPolicy: Always` para evitar imágenes almacenadas en caché obsoletas
Estas políticas se aplican a todos los espacios de nombres, incluidos los servicios futuros agregados al clúster.
