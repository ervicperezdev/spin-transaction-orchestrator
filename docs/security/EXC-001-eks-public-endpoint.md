# EXC-001 — Acceso público temporal al API de EKS para el challenge

## Registro de decisión

| Campo | Registro |
| --- | --- |
| Identificador | EXC-001; este documento versionado es el registro de seguimiento. |
| Fecha | 2026-09-09 |
| Disposición | Aceptación temporal de riesgo propuesta para la demostración de desarrollo; no es un falso positivo. |
| Estado | Configuración pública y exclusión puntual declaradas en la integración. La aprobación formal y la evidencia del despliegue siguen pendientes. |
| Responsable propuesto | Ervic Pérez, propietario del repositorio; responsable de verificar, revisar y cerrar la excepción. |
| Autoridad de aprobación | Líder de seguridad o responsable delegado, según la [política de riesgos](vulnerability-risk-assessment.md). Registrar identidad y revisión fechada del PR. |
| Alcance | Solo el API EKS de `dev`: `module.eks.aws_eks_cluster.this`, definido en `terraform/modules/eks/main.tf`. No autoriza producción. |
| Revisión propuesta | 2026-09-16 y antes de cualquier cambio de acceso o despliegue. |
| Vencimiento propuesto | 2026-09-23, fin de la demostración o introducción de datos reales, lo que ocurra primero. La aprobación debe confirmar o acortar la vigencia; desplegar no reinicia el plazo. |
| Regla | `terraform.lang.security.eks-public-endpoint-enabled.eks-public-endpoint-enabled` |
| Fuente | Log de CI proporcionado por el propietario: `returntocorp/semgrep:1.99.0`, digest `sha256:ae27024c16f7848cdbfd49c24ed0b78b13f13b85fcd7b87c679aaa8b0c0dce98`. Faltan URL de ejecución y SHA del commit afectado. |

## Justificación y límites técnicos

El challenge demuestra el despliegue automatizado desde runners estándar de
GitHub, `ubuntu-latest`. El job no dispone de conectividad privada hacia la VPC
ni de una IP de salida estática dedicada. Un endpoint privado requiere añadir
esa conectividad o ejecutar el despliegue desde un runner dentro de la VPC.
Esa infraestructura adicional se difiere durante la demostración temporal.

La integración declara `endpoint_public_access = true` y mantiene
`endpoint_private_access = true`. Los CIDRs efectivos proceden de las variables
del ambiente y deben verificarse en AWS. Si se utiliza `0.0.0.0/0`, la aceptación
debe cubrir explícitamente **todas las direcciones de origen IPv4**, no describir
el acceso como exclusivo de GitHub. Una IP administrativa `/32` no habilita al
runner público. Esta excepción no cubre acceso IPv6 universal ni otros ambientes.

La documentación inicial se redactó sobre una base con endpoint privado. La
integración de `feature/docs-espanol` cambia ese comportamiento declarativo; no
constituye evidencia de un `apply`. La validación heredada rechaza `0.0.0.0/1`,
pero no `0.0.0.0/0`: no debe presentarse como una protección efectiva contra
exposición universal. Cualquier cambio a esa validación debe revisarse junto
con el alcance temporal de desarrollo.

El API de administración de Kubernetes es independiente del ALB, DNS y TLS de
la aplicación. Autenticarse mediante OIDC en AWS o ejecutar
`aws eks update-kubeconfig` no demuestra autorización en Kubernetes.

## Evaluación del riesgo

El hallazgo es válido cuando se habilita el endpoint público. La exposición
permite llegar a la frontera de autenticación desde Internet y aumenta la
superficie de reconocimiento, intentos de acceso, ataques de disponibilidad y
abuso de credenciales autorizadas robadas. Un atacante autenticado podría
modificar cargas y consultar datos según los permisos del principal; comprometer
un administrador afecta al clúster completo.

El riesgo residual cualitativo se considera **alto hasta verificar los
controles**. No es una severidad del escáner ni una puntuación CVSS. La duración
limitada y los datos sintéticos reducen el impacto previsto de negocio, pero
no eliminan el riesgo técnico. No se presume eficaz ningún control sin evidencia.

WAF, el security group del ALB y las NetworkPolicies de los pods **no protegen
el endpoint público de EKS**. No se consideran controles compensatorios de este
hallazgo. Los registros permiten detectar actividad, no impedirla.

## Controles requeridos y evidencia

| Control | Evidencia requerida |
| --- | --- |
| Demostración temporal y aislada | Cuenta, clúster, ambiente, responsable y fecha de retirada; solo transacciones sintéticas y credenciales de prueba. |
| Credenciales CI temporales | Confianza OIDC restringida al repositorio/ref y audiencia previstos; ARN real del rol asumido; ausencia de claves AWS estáticas en Actions. |
| Acceso Kubernetes | Entrada EKS o mapeo admitido para el rol CI, con permisos de despliegue limitados a `transaction-api`; administración de plataforma separada y pruebas de denegación fuera del alcance. |
| Origen confiable | Disparadores y protección real de ramas; código de PR no confiable sin acceso a la identidad de despliegue. Un workflow no acredita la configuración de GitHub. |
| Conectividad interna | `endpointPrivateAccess = true`, subredes privadas de aplicaciones y aislamiento de RDS. No restringe por sí mismo el API público. |
| Detección y revisión | Entrega de logs API, audit y authenticator a CloudWatch, retención y responsable de revisar accesos fallidos/cambios privilegiados antes y después de la demostración. |
| Cambio controlado | Plan revisado, resultado de aplicación y CIDRs reales. El rol de despliegue de la aplicación no debe poder ampliar la exposición del endpoint. |

No se verificaron estos controles en AWS al preparar el documento. Conservar
enlaces a evidencia sin publicar tokens, credenciales de kubeconfig, estado
Terraform ni planes sin depurar que contengan secretos.

| Artefacto de auditoría | Estado |
| --- | --- |
| Ejecución de origen, commit y hallazgo completo | Pendiente; disponible solo el fragmento de log proporcionado. |
| Aprobador, fecha y PR revisado | Pendiente. |
| ARN del clúster, revisión desplegada y CIDRs | Pendiente. |
| Plan revisado y resultado de despliegue | Pendiente. |
| IAM/OIDC, permisos EKS y pruebas de denegación | Pendiente. |
| Logs, protección de ramas y datos sintéticos | Pendiente. |
| Resultado de revisión y evidencia de cierre | Pendiente. |

## Tratamiento en Semgrep

Por solicitud explícita del propietario, se conserva una anotación `nosemgrep`
inmediatamente antes de `aws_eks_cluster.this` en `terraform/modules/eks/main.tf`.
Solo afecta a la regla identificada, referencia EXC-001 y vence el 2026-09-23.
La exclusión no acredita aprobación formal ni configuración efectiva en AWS.

Se conserva `--error` y el bloqueo de los demás hallazgos. No excluir el
directorio Terraform, desactivar el job ni añadir `continue-on-error`.
Reejecutar el escáner original y demostrar que los demás hallazgos siguen
bloqueando. La caducidad requiere seguimiento manual: CI no evalúa estas fechas.

## Remediación y cierre

1. Establecer conectividad privada del despliegue mediante un runner en la VPC
   o una conexión autenticada desde el runner hospedado. Para administración,
   proporcionar VPN o un host administrado mediante SSM.
2. Verificar DNS, rutas, HTTPS en security groups y autorización EKS para ambas
   identidades antes de deshabilitar el endpoint público. Una IP estática de
   runner permite restringir CIDRs como medida intermedia; no satisface el
   criterio de endpoint privado.
3. Aplicar `endpoint_public_access = false` conservando acceso privado, o
   retirar el ambiente de demostración mediante el proceso revisado.
4. Retirar la exclusión de Semgrep y cualquier excepción de validación; repetir
   el análisis y conservar el resultado en el commit de cierre.
5. Conservar configuración real y despliegue privado exitoso, o evidencia de
   eliminación del clúster de demostración.

Cerrar al primer vencimiento aplicable. Un indicio de compromiso, acceso
inesperado, ausencia de controles o uso en producción requiere reevaluación
inmediata y restricción según el proceso de incidentes. Extender la excepción
requiere revisión fechada, justificación y nueva caducidad; nunca es automático.
Deshabilitar el endpoint público antes de preparar conectividad privada
interrumpirá los despliegues desde los runners actuales.

## Referencias

- [Acceso al endpoint EKS](https://docs.aws.amazon.com/eks/latest/userguide/config-cluster-endpoint.html)
- [Direcciones IP de runners de GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Política de vulnerabilidades y excepciones](vulnerability-risk-assessment.md)
- [Operación de seguridad cloud](../cloud-security-operations.md)
- [Respuesta a incidentes](../incident-response.md)
