# Guía de respuesta a incidentes: Spin Transaction Orchestrator
**Fecha:** 2026-09-08
**Alcance:** Incidentes operativos y de seguridad para la API de transacciones que se ejecuta en EKS con RDS PostgreSQL
---
## Proceso de respuesta
```
Detect → Triage → Contain → Eradicate → Recover → Lessons Learned
```

| Phase | Goal | Key Actions |
|---|---|---|
| **Detect** | Identify that an incident has occurred | Alerts from CloudWatch, WAF metrics, Gitleaks, Dependabot |
| **Triage** | Classify severity and assign responders | Determine P1/P2/P3, page Incident Commander |
| **Contain** | Limit blast radius immediately | Isolate pods, escalate WAF rules, revoke credentials |
| **Eradicate** | Remove the root cause | Patch, rotate secrets, block sources |
| **Recover** | Restore normal service safely | Verify health, re-enable traffic, validate data integrity |
| **Lessons Learned** | Prevent recurrence | Postmortem document, action items, runbook updates |

---
## Niveles de gravedad
| Severity | Label | Definition | Examples |
|---|---|---|---|
| P1 | Critical | Active data breach, system fully down, financial fraud in progress | RDS data exfiltration, all pods crash-looping, credentials confirmed stolen |
| P2 | High | Degraded service, potential data exposure, elevated error rate | Circuit breaker open, WAF blocking legitimate traffic, secret scan alert |
| P3 | Medium | Non-critical anomaly, low-impact issue, informational alert | Unusual but non-malicious traffic pattern, dependency vulnerability with no exploit |

---
## Funciones y responsabilidades
| Role | Responsibilities |
|---|---|
| **Incident Commander** | Coordinates overall response, drives the timeline, communicates status to stakeholders, declares incident closed |
| **Security Lead** | Threat analysis, determines containment strategy, authorizes credential revocation, leads postmortem |
| **Platform Engineer** | EKS/AWS operations: pod restarts, scaling, WAF rule changes, CloudWatch investigation |
| **Application Engineer** | Code-level log analysis, hotfix development, idempotency and transaction state verification |
| **Database Engineer** | RDS integrity checks, connection analysis, query audit, point-in-time recovery if needed |
| **Communications** | Stakeholder and customer notification when required by severity or regulation; manages external comms |

---
## Objetivos de SLA
| Severity | Detection → Response | Resolution Target |
|---|---|---|
| P1 | < 15 minutes | < 4 hours |
| P2 | < 1 hour | < 24 hours |
| P3 | < 4 hours | < 1 week |

---
## Guía de incidentes: volumen de transacciones anormales
**Activador:** Se detectó un aumento de bloqueo de AWS WAF O un aumento de la métrica `transaction_rejected_total` en las alarmas de CloudWatch.
### 1. Detección
- La alarma de CloudWatch se activa cuando `transaction_rejected_total` supera el umbral.
- El panel WAF muestra un aumento en el recuento de bloques en la regla de limitación de velocidad.
- El ingeniero de plataforma de guardia recibe una alerta de PagerDuty/SNS.
### 2. Triaje (líder de seguridad)
- Extraiga una muestra de solicitud bloqueada de WAF: examine las IP de origen, los patrones de agente de usuario y las rutas de solicitud.
- Verifique los registros del pod de EKS para conocer los patrones de solicitud: IP distribuidas → DDoS; patrón de cuenta única → intento de fraude; Tráfico válido uniforme → posible error en la regla de tarifas.
- Asignar P1 (fraude activo/DDoS que afecta la disponibilidad) o P2 (elevado pero no crítico).
### 3. Contención| Option | When to Use |
|---|---|
| Escalate WAF rate rule threshold | Volumetric DDoS confirmed |
| Temporarily scale down replicas + enable maintenance page | System instability; need to drain cleanly |
| Manually trip Resilience4j circuit breaker via actuator | Provider being overwhelmed by retries |
| Block specific IP ranges in WAF | Identified attack source |

### 4. Investigación
- **CloudTrail:** Revise los registros de acceso de API Gateway/ALB para detectar patrones de llamadas inusuales.
- **Registros del pod de EKS:** `kubectl logs -l app=transaction-api --since=30m`: busca `accountId` repetidos, valores inusuales de `amount` y reutilización de claves de idempotencia.
- **RDS:** Compruebe si hay un volumen de escritura inusual o filas bloqueadas en la tabla `transactions`.
- **Ingeniero de aplicaciones:** Verifique que la protección de idempotencia esté funcionando; verifique si hay alguna implementación reciente que haya cambiado la lógica sensible a la velocidad.
### 5. Erradicación
- Bloquear IP/CIDR de atacantes confirmados de forma permanente en las reglas administradas de WAF.
- Si un error provocó el pico, implemente la revisión mediante PR → CI → actualización continua normal.
- En caso de fraude: congelar los `accountId` afectados en espera de revisión manual.
### 6. Recuperación
- Verificar el estado del pod: todas las réplicas `Running`, sondas de preparación aprobadas.
- Confirme que el disyuntor esté en `CLOSED` (estado saludable) antes de volver a habilitar el tráfico total.
- Ajustar la regla de tarifas WAF para reflejar la línea base de tráfico confirmado.
- Monitoree `transaction_success_total` y `transaction_rejected_total` durante 30 minutos después de la recuperación.
### 7. Post mortem
- Documento: cronograma, cuentas afectadas, recuento de transacciones, estimación de impacto financiero.
- Registro de decisiones: por qué se tomó cada acción de contención y por quién.
- Elementos de acción: ajuste de reglas, mejoras de monitoreo, actualizaciones de runbook.
- Propietario asignado para cada elemento de acción con fecha de vencimiento.
---
## Guía de incidentes: sospecha de filtración secreta
**Desencadenante:** Alerta de escaneo de CI de Gitleaks O el desarrollador informa una confirmación accidental de credenciales O actividad anómala de la API de CloudTrail.
### Pasos
1. **Detección:** Gitleaks falla en la canalización de CI en la rama afectada, o un desarrollador detecta un archivo `.env` o de credenciales en una confirmación.
2. **Revocación inmediata (Líder de seguridad + Ingeniero de plataforma):**
   - Identifique el tipo de secreto exacto (clave AWS, contraseña de base de datos, clave API del proveedor).
   - Revocar inmediatamente a través del sistema emisor (consola de AWS IAM, panel del proveedor, restablecimiento de contraseña de RDS); NO espere el análisis de la causa raíz.
3. **Girar en AWS Secrets Manager:**
   - Actualice el secreto afectado en AWS Secrets Manager.
   - Verifique que la versión rotada sea legible desde Secrets Manager mediante la función API IRSA.
   - Realice un reinicio continuo de los pods afectados para volver a montar y recargar las credenciales.
4. **Auditar CloudTrail:**
   - Busque llamadas API utilizando la credencial revocada en la ventana desde el momento de la confirmación hasta la revocación.
   - Busque: creación de recursos no autorizados, lecturas/exportaciones de datos, asunción de roles de IAM.
   - Si se encuentran llamadas no autorizadas → escalar al protocolo de violación de datos P1.
5. **Eliminar del historial de git:**
   - Utilice `git filter-repo` o BFG Repo Cleaner para eliminar el secreto de todas las confirmaciones.
   - Forzar el historial de limpieza (requiere administrador del repositorio; coordinar con el equipo).
   - Invalidar todos los clones de desarrolladores locales (es necesario volver a clonarlos).
6. **Erradicación:**
   - Agregue un patrón a `.gitignore` y actualice la configuración de Gitleaks previa a la confirmación para detectar patrones similares.
   - Revisar las relaciones públicas que introdujeron la filtración en busca de otros datos confidenciales.
7. **Lecciones aprendidas:**
   - Agregue el patrón filtrado a las reglas personalizadas de Gitleaks.
   - Realizar una breve sesión de concientización del equipo sobre higiene secreta.
   - Verifique que todos los archivos `.env*` estén en `.gitignore`.
---
## Plantillas de comunicación
### P1 — Actualización de estado interno (cada 30 min)```
[INCIDENT-P1] Spin Transaction API — <short description>
Status: Contained / Investigating / Recovering
Impact: <number of transactions affected / systems down>
Last action: <what was just done>
Next action: <what is happening now>
ETA to resolution: <estimate or TBD>
IC: <name>
```

### P1: Notificación de cara al cliente (si corresponde)```
We are currently experiencing an issue affecting transaction processing.
Our team is actively investigating. We will provide an update within 30 minutes.
Transactions submitted during this window will be reconciled; no duplicate charges will occur.
```
