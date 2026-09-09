# Incident Response Playbook — Spin Transaction Orchestrator

**Date:** 2026-09-08
**Scope:** Security and operational incidents for the transaction API running on EKS with RDS PostgreSQL

---

## Response Process

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

## Severity Levels

| Severity | Label | Definition | Examples |
|---|---|---|---|
| P1 | Critical | Active data breach, system fully down, financial fraud in progress | RDS data exfiltration, all pods crash-looping, credentials confirmed stolen |
| P2 | High | Degraded service, potential data exposure, elevated error rate | Circuit breaker open, WAF blocking legitimate traffic, secret scan alert |
| P3 | Medium | Non-critical anomaly, low-impact issue, informational alert | Unusual but non-malicious traffic pattern, dependency vulnerability with no exploit |

---

## Roles and Responsibilities

| Role | Responsibilities |
|---|---|
| **Incident Commander** | Coordinates overall response, drives the timeline, communicates status to stakeholders, declares incident closed |
| **Security Lead** | Threat analysis, determines containment strategy, authorizes credential revocation, leads postmortem |
| **Platform Engineer** | EKS/AWS operations: pod restarts, scaling, WAF rule changes, CloudWatch investigation |
| **Application Engineer** | Code-level log analysis, hotfix development, idempotency and transaction state verification |
| **Database Engineer** | RDS integrity checks, connection analysis, query audit, point-in-time recovery if needed |
| **Communications** | Stakeholder and customer notification when required by severity or regulation; manages external comms |

---

## SLA Targets

| Severity | Detection → Response | Resolution Target |
|---|---|---|
| P1 | < 15 minutes | < 4 hours |
| P2 | < 1 hour | < 24 hours |
| P3 | < 4 hours | < 1 week |

---

## Incident Playbook: Abnormal Transaction Volume

**Trigger:** AWS WAF blocking surge detected OR `transaction_rejected_total` metric spike in CloudWatch Alarms.

### 1. Detection
- CloudWatch Alarm fires on `transaction_rejected_total` exceeding threshold.
- WAF dashboard shows block count spike on the rate-limiting rule.
- On-call Platform Engineer receives PagerDuty/SNS alert.

### 2. Triage (Security Lead)
- Pull WAF blocked-request sample: examine source IPs, User-Agent patterns, request paths.
- Check EKS pod logs for request patterns: distributed IPs → DDoS; single account pattern → fraud attempt; uniform valid traffic → potential bug in rate rule.
- Assign P1 (active fraud/DDoS impacting availability) or P2 (elevated but not critical).

### 3. Containment
| Option | When to Use |
|---|---|
| Escalate WAF rate rule threshold | Volumetric DDoS confirmed |
| Temporarily scale down replicas + enable maintenance page | System instability; need to drain cleanly |
| Manually trip Resilience4j circuit breaker via actuator | Provider being overwhelmed by retries |
| Block specific IP ranges in WAF | Identified attack source |

### 4. Investigation
- **CloudTrail:** Review API Gateway / ALB access logs for unusual call patterns.
- **EKS pod logs:** `kubectl logs -l app=transaction-api --since=30m` — look for repeated `accountId`, unusual `amount` values, idempotency key reuse.
- **RDS:** Check for unusual write volume or locked rows in `transactions` table.
- **Application Engineer:** Verify idempotency guard is functioning; check for any recent deploy that changed rate-sensitive logic.

### 5. Eradication
- Block confirmed attacker IPs/CIDRs permanently in WAF Managed Rules.
- If a bug caused the spike, deploy hotfix via normal PR → CI → rolling update.
- If fraud: freeze affected `accountId`s pending manual review.

### 6. Recovery
- Verify pod health: all replicas `Running`, readiness probes passing.
- Confirm circuit breaker is `CLOSED` (healthy state) before re-enabling full traffic.
- Adjust WAF rate rule to reflect confirmed traffic baseline.
- Monitor `transaction_success_total` and `transaction_rejected_total` for 30 min post-recovery.

### 7. Postmortem
- Document: timeline, affected accounts, transaction count, financial impact estimate.
- Decision log: why each containment action was taken and by whom.
- Action items: rule tuning, monitoring improvements, runbook updates.
- Owner assigned for each action item with due date.

---

## Incident Playbook: Suspected Secret Leakage

**Trigger:** Gitleaks CI scan alert OR developer reports accidental credential commit OR anomalous CloudTrail API activity.

### Steps

1. **Detect:** Gitleaks fails the CI pipeline on the affected branch, or a developer notices a `.env` or credentials file in a commit.

2. **Immediate revocation (Security Lead + Platform Engineer):**
   - Identify the exact secret type (AWS key, DB password, provider API key).
   - Revoke immediately via the issuing system (AWS IAM console, provider dashboard, RDS password reset) — do NOT wait for root cause analysis.

3. **Rotate in AWS Secrets Manager:**
   - Update the affected secret in AWS Secrets Manager.
   - Trigger External Secrets Operator reconciliation to push new value to K8s Secret.
   - Perform rolling restart of affected pods to pick up new credentials.

4. **Audit CloudTrail:**
   - Search for API calls using the revoked credential in the window from commit time to revocation.
   - Look for: unauthorized resource creation, data reads/exports, IAM role assumption.
   - If unauthorized calls found → escalate to P1 data breach protocol.

5. **Remove from git history:**
   - Use `git filter-repo` or BFG Repo Cleaner to purge secret from all commits.
   - Force-push cleaned history (requires repository admin; coordinate with team).
   - Invalidate all local developer clones (require re-clone).

6. **Eradication:**
   - Add pattern to `.gitignore` and update pre-commit Gitleaks config to detect similar patterns.
   - Review PR that introduced the leak for other sensitive data.

7. **Lessons Learned:**
   - Add the leaked pattern to Gitleaks custom rules.
   - Conduct brief team awareness session on secret hygiene.
   - Verify all `.env*` files are in `.gitignore`.

---

## Communication Templates

### P1 — Internal Status Update (every 30 min)
```
[INCIDENT-P1] Spin Transaction API — <short description>
Status: Contained / Investigating / Recovering
Impact: <number of transactions affected / systems down>
Last action: <what was just done>
Next action: <what is happening now>
ETA to resolution: <estimate or TBD>
IC: <name>
```

### P1 — Customer-Facing Notification (if applicable)
```
We are currently experiencing an issue affecting transaction processing.
Our team is actively investigating. We will provide an update within 30 minutes.
Transactions submitted during this window will be reconciled; no duplicate charges will occur.
```
