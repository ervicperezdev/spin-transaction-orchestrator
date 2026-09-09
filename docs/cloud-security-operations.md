# Operaciones de seguridad y nube — diseño de señales y escalada
## Propósito y límite
Este documento define el diseño de detección y la respuesta SOC para el
perímetro `Route 53 → WAF regional → ALB → AWS Load Balancer Controller →
Service → pods`, RDS PostgreSQL, EKS Pod Identity y Secrets Manager. Es un
artefacto de diseño: este repositorio **no habilita ni opera** CloudTrail,
GuardDuty, Security Hub, destinos de registros, reglas de cotización, alarmas,
SNS/PagerDuty ni integraciones con SIEM.
El propietario de la plataforma debe implementar los prerrequisitos en la
cuenta AWS y validar permisos, retención, coste, región y rutas de escalada
antes de activar alertas. Los eventos y consultas no deben contener valores de
secretos, cuerpos, importaciones, referencias de pago, IDs de transacción,
claves de idempotencia ni datos personales. Para activación se usa el identificador
de incidente, el `eventID` de CloudTrail y el `traceId` UUID ya saneado de la
aplicación, cuando se aplica.
## Fuentes y cobertura propuesta
| Fuente | Cobertura requerida | Señales de triage | Conservación y acceso |
| --- | --- | --- | --- |
| CloudTrail (management events) | Todas las regiones; lectura/escritura de IAM, STS, EKS, RDS, Secrets Manager, WAFv2, Route 53 y CloudTrail | `AccessDenied`, cambios de IAM/roles/policies, `AssumeRole` inusual, cambios de logging, lectura anómala de secretos, cambios de ACL/reglas WAF, modificaciones RDS/EKS | Trail centralizado e inmutable con cifrado AWS-managed; acceso de sólo lectura para SOC y mínimo privilegio para administración. Retención conforme a política corporativa. |
| CloudTrail data events | Sólo los secretos de aplicación explícitamente aprobados; no activar una captura amplia sin análisis de volumen/coste | `GetSecretValue` fuera del rol/ventana esperados, enumeración o fallos repetidos | Misma cuenta de logs/retención; excluir valores de `requestParameters` de exportaciones y tickets. |
| GuardDuty | Cuenta y regiones de producción; hallazgos de IAM, credenciales, EKS y RDS cuando el plan/telemetría aplicable lo soporte | uso de credenciales comprometidas, API calls maliciosas, comportamiento anómalo de pods/nodos, exfiltración | Fuente de detección; los hallazgos se conservan y enrutan vía Security Hub/SIEM. No se cierran automáticamente. |
| Security Hub | Agregador de hallazgos de GuardDuty, controles AWS habilitados por la organización y hallazgos de terceros aprobados | severidad normalizada, recursos afectados, cuenta/región, workflow y evidencia vinculada | SOC es propietario del workflow; los hallazgos no se resuelven sólo por cerrar un ticket. |
| WAF regional logging | Web ACL del ALB, en destino central aprobado (CloudWatch Logs, S3 o Firehose); métricas y sampled requests complementan, no sustituyen logs | bloqueos por regla, rate limit, patrones de URI/User-Agent, IP o ASN; falsos positivos | Aplicar redacción WAF de headers/cookies/campos sensibles antes de enviar. Acceso limitado a SOC/IR. |
| ALB, RDS, EKS y aplicación | Métricas/logs operativos existentes como contexto, no como fuente de auditoría de identidad | 5xx/targets unhealthy, presión de RDS, eventos de control plane/pods, `traceId` | Respetar el catálogo `docs/observability.md`; nunca elevar acceso a secretos para telemetría. |

### Dependencias de diseño
- Centralizar los registros de CloudTrail y WAF en una cuenta/destino de registro aprobado,
  con cifrado y protección contra borrado definidos por la organización.
- Habilitar GuardDuty y Security Hub de forma organizacional y agregar los
  hallazgos de las cuentas/regiones que alojan la carga.
- Autorizar explícitamente al rol de SOC a consultar evidencia, sin otorgarle
  permisos de modificación sobre producción de forma predeterminada.
- Mantener Secrets Manager como fuente de verdad y Pod Identity para los
  controladores EKS; no introducir ESO, Kubernetes Secrets ni claves AWS
  estáticas por motivos de observabilidad.
## Normalización y severidad
La gravedad se asigna por impacto confirmada y contexto; la gravedad nativa
de GuardDuty/Security Hub es una entrada, no una decisión final. El SOC abre
un incidente y conserva enlaces a los hallazgos/eventos originales.
| Prioridad | Criterio de escalación | Ejemplos | Objetivo inicial |
| --- | --- | --- | --- |
| P1 / crítica | Compromiso confirmado, exfiltración, modificación no autorizada de controles/identidad, o indisponibilidad/fraude activo de alto impacto | `GetSecretValue` no autorizado seguido de uso válido; rol admin creado; CloudTrail desactivado; GuardDuty de credencial comprometida; WAF evadido con impacto | Page inmediato a IC, Security Lead y Platform on-call; respuesta en 15 min. |
| P2 / alta | Sospecha creíble de compromiso o degradación de seguridad/servicio sin impacto confirmado | picos de `AccessDenied` a secretos, `AssumeRole` fuera de patrón, cambio WAF no aprobado, bloqueos WAF masivos, hallazgo GuardDuty alto | Crear incidente y avisar a Security Lead + Platform on-call; triage en 1 h. |
| P3 / media | Anomalía aislada, control fallido sin exposición demostrada o hallazgo medio/bajo que requiere investigación | rate limit aislado, intento denegado de IAM, recomendación de Security Hub, variación limitada de 4xx WAF | Cola SOC; triage en 4 h hábiles y corrección con dueño/fecha. |

Un P2/P3 se eleva a P1 si aparece evidencia de acceso exitoso, cambio de
permisos, extracción de datos, propagación a otra cuenta/región o impacto en
transacciones/servicio. Un bloqueo WAF por sí solo no es evidencia de brecha;
conservarlo como evidencia y evaluar volumen, regla, patrón y efecto en ALB.
## Flujo de triaje y escalada
```text
Fuente AWS/WAF → Security Hub o SIEM → SOC valida y deduplica
  → clasifica P1/P2/P3 + abre incidente
  → Security Lead determina amenaza/alcance
  → Platform ejecuta contención aprobada; App/DB validan impacto
  → IC coordina recuperación, comunicaciones y postmortem
```

1. **Validar (SOC):** confirmar cuenta, región, recurso, tiempo, actor y
   evento original; deduplicar por `eventID`/finding ID. No copiar cargas útiles
   sensibles al billete.
2. **Enriquecer:** correlacionar la identidad y ventana temporal con
   `AssumeRole`, cambios IAM, CloudTrail, WAF/ALB, actividad EKS, RDS y
   accede a Secrets Manager. Distinguir roles esperados de carga de trabajo, Carga
   AWS Load Balancer Controller y ExternalDNS de accesos anómalos.
3. **Clasificar:** aplicar la tabla anterior y registrar hipótesis, alcance,
   evidencia y dueño. Si hay datos de clientes o secretos potenciales
   expuestos, trate como P1 hasta que Security Lead descarte impacto.
4. **Escalar:** P1 página al Comandante de Incidentes, Líder de Seguridad y Plataforma
   de guardia; P2 notifica a Security Lead y Platform de guardia; P3 queda en cola
   SOC con dueño. Ingeniería de aplicaciones/bases de datos se suma sólo cuando el
   recurso o impacto lo requiera.
5. **Contener con autorización:** La plataforma puede aislar cargas de trabajo, retirar
   acceso, ajustar WAF o rotar secretos después de la aprobación del Security
   Lead/IC, salvo el procedimiento de emergencia corporativa. Preservar
   evidencia antes de cambios cuando sea seguro hacerlo.
6. **Cerrar:** Security Lead valida la erradicación y el riesgo residual; el
   IC confirma recuperación. Security Hub se resuelve sólo con evidencia de
   corrección. P1/P2 requiere post mortem, acciones con dueño/fecha y revisión
   de reglas de detección.
## Runbooks por señal
| Disparador | Primeras comprobaciones | Contención candidata | Escalación |
| --- | --- | --- | --- |
| CloudTrail: IAM/STS inusual o `AccessDenied` repetido | actor, source IP, región, `AssumeRole`, cambios de policy y éxito posterior | revocar sesiones/credenciales, limitar policy o rol afectado | P2; P1 si hubo uso exitoso privilegiado o cambio no autorizado |
| CloudTrail: `GetSecretValue` anómalo | secreto afectado, rol Pod Identity esperado, región, éxito, lecturas posteriores | rotar en Secrets Manager, invalidar credenciales aguas abajo, reiniciar pods de forma controlada | P1 si éxito fuera de identidad esperada; P2 si sólo denegado/sospechoso |
| GuardDuty: credential/IAM/EKS/RDS | finding ID, recurso, CloudTrail asociado, alcance y actividad lateral | aislar identidad/pod/nodo según playbook corporativo | P1 para alta severidad con evidencia; P2 mientras se confirma |
| Security Hub: control crítico o finding agregado | producto originador, severidad, recurso, estado y evidencia | remediar mediante cambio aprobado; no suprimir sin excepción fechada | según impacto; P3 para recomendación sin exposición |
| WAF: subida de bloqueos o rate limit | regla, URI, IP/ASN, tasa, ALB 4xx/5xx y targets; revisar redacción | bloqueo temporal específico o ajuste de regla aprobado | P2 si afecta clientes o indica ataque; P1 si disponibilidad/fraude activo |
| ALB/RDS/EKS con señal de seguridad | salud de targets, 5xx, conexiones RDS, eventos de control plane/pods | escalar/aislar/revertir cambio aprobado | P2; P1 si hay indisponibilidad amplia o evidencia de compromiso |

## Validación previa a operación
Antes de declarar el diseño operativo, el propietario de la plataforma debe hacer
un ejercicio controlado que compruebe: llegada de un evento de gestión a la
cuenta central; hallazgo de prueba de GuardDuty/Security Hub; entrega de un
evento WAF con campos redactados; creación/deduplicación de un incidente;
escalada P1/P2 a los turnos correctos; y que SOC no pueda leer valores de
secretos ni modificar producción fuera del flujo aprobado. registrador los
resultados, retención acordada y contactos reales en la documentación operada,
no en este repositorio.
