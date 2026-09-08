# Dependency vulnerability remediation

## Method

The affected artifacts were inspected with Maven's dependency tree before and
after remediation. Jackson, Micrometer, Tomcat, Spring Framework and Spring
Data are transitive dependencies managed by the Spring Boot parent BOM; none is
declared directly in this project. The only direct version override in the POM
is the PostgreSQL JDBC driver.

The parent was upgraded from Spring Boot 3.5.14 to 3.5.16, the latest compatible
3.5.x maintenance release. This preserves Java 21 and lets the Spring Boot BOM
move the managed dependency set as a coherent unit.

## Resolved dependencies

| Dependency | Before | After | Management | Remediates |
| --- | --- | --- | --- | --- |
| `jackson-core` / `jackson-databind` | 2.21.2 | 2.21.4 | Spring Boot BOM | GHSA-r7wm-3cxj-wff9, CVE-2026-54512, CVE-2026-54513 |
| `micrometer-core` | 1.15.11 | 1.15.12 | Spring Boot BOM | CVE-2026-40983, CVE-2026-40984 |
| `spring-data-commons` | 3.5.11 | 3.5.13 | Spring Boot BOM | CVE-2026-41695, CVE-2026-41716 |
| `spring-expression` / `spring-webmvc` | 6.2.18 | 6.2.19 | Spring Boot BOM | CVE-2026-41850, CVE-2026-41842, CVE-2026-41845 |
| `tomcat-embed-*` | 10.1.54 | 10.1.55 | Spring Boot BOM | Findings whose fixed version is 10.1.55 |

## Remaining Tomcat findings

The scan calls for Tomcat 10.1.58 for part of its remaining findings. Maven
Central does not publish `org.apache.tomcat.embed:tomcat-embed-{core,el,websocket}:10.1.58`;
attempting that version fails dependency resolution. Spring Boot 3.5.16 manages
the latest available compatible Tomcat 10.1 artifact, 10.1.55. No override or
Trivy ignore rule is used.

The residual findings therefore remain visible and fail the security gate until
an upstream, resolvable patched Tomcat version is available through a compatible
Spring Boot release. This service uses embedded Tomcat for HTTP ingress, so the
findings are treated as applicable; mitigate operationally by keeping the
service behind the platform ingress/WAF, restricting actuator exposure, and
updating the BOM promptly when a patched release is published.
