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
| `tomcat-embed-{core,el,websocket}` | 10.1.54 | 10.1.59 | Spring Boot BOM property override | CVE-2026-65182, CVE-2026-65905, CVE-2026-68525 |

## Remaining Tomcat findings

The scan calls for Tomcat 10.1.58 for part of its remaining findings. That
version was not released to Maven Central, but the later compatible maintenance
release `10.1.59` is published for all embedded Tomcat modules. Spring Boot
3.5.16 otherwise manages 10.1.55, so the one supported `tomcat.version`
property override advances the entire embedded Tomcat family together. This is
limited to the upstream Tomcat maintenance line and was verified by the Maven
dependency tree; no individual Tomcat module is declared directly.

No Trivy ignore rule is used. This service uses embedded Tomcat for HTTP ingress,
so the findings are treated as applicable and the upgraded artifact must be
rescanned in the final container image.
