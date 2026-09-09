# Modelo de amenazas: Spin Transaction Orchestrator
**Fecha:** 2026-09-08
**Autor:** Líder de ingeniería y seguridad
**Metodología:** STRIDE
---
> **Alcance:** Este es un modelo de amenazas en tiempo de diseño. Entradas que describen WAF, ALB,
> EKS, RDS, IRSA, Kyverno, CloudTrail o la fijación de certificados son objetivos o
> controles de la hoja de ruta a menos que se verifiquen en un entorno implementado; no son un
> afirmar que esos servicios están activos.
## Descripción general del sistema
Diagrama de flujo de datos basado en texto:
```
[Internet Client]
       |
       v  (HTTPS)
[AWS WAF]  ← trust boundary: Internet / WAF
       |
       v  (HTTPS)
[Application Load Balancer]  ← trust boundary: ALB
       |
       v  (HTTP internal)
[EKS Cluster — transaction-api pod]  ← trust boundary: EKS cluster namespace
       |                   |
       v  (JDBC/TLS)       v  (HTTPS)
[RDS PostgreSQL]    [External Payment Provider]
← trust boundary:
  RDS private subnet
```

**Límites de confianza:**
| Boundary | Description |
|---|---|
| Internet / WAF | Untrusted external clients enter through AWS WAF; all traffic is filtered before reaching ALB |
| ALB | Routes authenticated HTTPS traffic into the EKS cluster; terminates TLS from external clients |
| EKS cluster | Internal pod-to-pod and pod-to-RDS communication; protected by NetworkPolicy and IRSA |
| RDS private subnet | Isolated subnet not reachable from the internet; accessible only from within the cluster VPC |

---
## Activos a proteger
| Asset | Classification | Impact if Compromised |
|---|---|---|
| Transaction data (amounts, types, IDs) | Confidential | Financial fraud, regulatory violation |
| Account IDs | Confidential | Account enumeration, targeted attacks |
| Payment credentials / tokens | Secret | Direct financial loss |
| Provider API keys | Secret | Unauthorized charges to provider account |
| DB credentials | Secret | Full data breach |
| AWS IAM roles / IRSA policies | Secret | Lateral movement, data exfiltration |
| CI/CD secrets (GitHub OIDC, env vars) | Secret | Supply chain compromise |

---
## Análisis STRIDE
### S — Suplantación de identidad
| Threat | Risk | Control | Residual Risk |
|---|---|---|---|
| Unauthenticated client submitting transactions | Medium | AWS WAF IP rules + (production) OAuth2/JWT authentication | Low after auth is enforced |
| Provider impersonation via MITM on outbound HTTPS | Medium | TLS certificate verification on outbound calls + Certificate pinning roadmap | Low |

---
### T - Manipulación
| Threat | Risk | Control | Residual Risk |
|---|---|---|---|
| Manipulating `amount`, `type`, or `accountId` in transit | High | TLS in transit + `@Valid` input validation + `BigDecimal` (NUMERIC precision) | Low |
| SQL injection via transaction fields | High | JPA parameterized queries + input validation annotations | Low |
| Malicious Flyway migration via supply chain compromise | High | Branch protection + mandatory PR review + Gitleaks in CI pre-push | Medium |

---
### R — Repudio
| Threat | Risk | Control | Residual Risk |
|---|---|---|---|
| Client denies submitting a transaction | Medium | Structured audit logs + `traceId` correlation + `Idempotency-Key` persistence | Low |
| No cryptographic non-repudiation when auth is absent | Medium | AWS CloudTrail + application logs + future client authentication (JWT/mTLS) | Medium |

---
### I — Divulgación de información
| Threat | Risk | Control | Residual Risk |
|---|---|---|---|
| Financial data leaked in error responses | High | `GlobalExceptionHandler` returns opaque error codes; stack traces never exposed | Low |
| Secrets appearing in application logs | High | Sensitive-field logging review + Gitleaks in CI to prevent accidental log commits | Low |
| Container exposing internal build tools or binaries | Medium | Distroless base image (no shell, no package manager, no debug tools) | Low |

---
### D - Denegación de servicio
| Threat | Risk | Control | Residual Risk |
|---|---|---|---|
| API flooding / volumetric DDoS | High | AWS WAF rate-limiting rules + ALB connection limits | Medium |
| Provider timeout saturation (thread pool exhaustion) | Medium | Resilience4j circuit breaker + 3 s read / 2 s connect timeout | Low |
| DB connection pool exhaustion | Medium | HikariCP connection pool sizing + Kubernetes HPA for pod scaling | Medium |

---
### E - Elevación de privilegios
| Threat | Risk | Control | Residual Risk |
|---|---|---|---|
| Compromised pod → root access on node | High | `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `seccompProfile: RuntimeDefault` in Pod spec | Low |
| Pod granted excessive AWS permissions | High | IRSA least-privilege policy + Kyverno policy to block wildcard IAM | Low |
| Stolen CI credentials enabling infrastructure changes | High | GitHub OIDC (no static AWS access keys) + branch protection + required reviews | Low |

---
## Escenarios adicionales específicos de Fintech
| Scenario | Attack Vector | Control |
|---|---|---|
| Replay attack | Attacker captures and resends a valid HTTP request | `Idempotency-Key` stored with UNIQUE constraint; duplicate key returns cached result |
| Duplicate transaction on network retry | Client retries on timeout, re-submitting identical payload | `Idempotency-Key` guard prevents double execution |
| Provider timeout after execution | Provider processed charge; API crashed before persisting result | Reconciliation job (roadmap) + idempotency reduces partial duplicates |
| Malicious dependency (supply chain) | Compromised transitive dependency introduces backdoor | Dependabot automated updates + Trivy SCA in CI + SBOM generation + Cosign image signing |
| SSRF via provider URL | Attacker manipulates a URL parameter to redirect outbound call | Provider URL is fixed in application configuration; never user-controlled |
| Secret leakage via git history | Developer accidentally commits credentials | Gitleaks pre-push hook in CI + `.gitignore` for `.env` files + AWS Secrets Manager |

---
## Matriz de Aceptación de Riesgos
| Threat | Likelihood | Impact | Risk Level | Control | Owner |
|---|---|---|---|---|---|
| API flooding / DDoS | High | High | Critical | WAF rate rules + ALB limits | Platform Engineer |
| SQL injection | Low | High | High | JPA parameterized queries | Application Engineer |
| Secret leakage via git | Medium | High | High | Gitleaks + Secrets Manager | Security Lead |
| Malicious Flyway migration | Low | High | High | Branch protection + PR review | Security Lead |
| Pod privilege escalation | Low | High | High | seccomp + non-root + readOnly FS | Platform Engineer |
| Provider MITM | Low | High | High | TLS verification + cert pinning (roadmap) | Application Engineer |
| Replay / duplicate transaction | Medium | High | High | Idempotency-Key constraint | Application Engineer |
| Ambiguous provider state on timeout | Medium | High | High | Reconciliation job (roadmap) | Application Engineer |
| DB connection pool exhaustion | Medium | Medium | Medium | HikariCP tuning + HPA | Platform Engineer |
| No non-repudiation without auth | High | Medium | Medium | Audit logs + future JWT | Security Lead |
| Client spoofing (no auth in demo) | High | Medium | Medium | OAuth2/JWT (production roadmap) | Security Lead |
| Malicious dependency | Low | High | Medium | Trivy SCA + SBOM + Cosign | Security Lead |
