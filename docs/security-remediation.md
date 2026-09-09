# Corrección de vulnerabilidad de dependencia
## Método
Los artefactos afectados fueron inspeccionados con el árbol de dependencia de Maven antes y
después de la remediación. Jackson, Micrómetro, Tomcat, Spring Framework y Spring
Los datos son dependencias transitivas administradas por la lista de materiales principal de Spring Boot; ninguno lo es
declarado directamente en este proyecto. La única anulación de versión directa en el POM
es el controlador JDBC de PostgreSQL.
El padre se actualizó de Spring Boot 3.5.14 a 3.5.16, la última versión compatible
Versión de mantenimiento 3.5.x. Esto preserva Java 21 y permite que Spring Boot BOM
mover el conjunto de dependencias gestionadas como una unidad coherente.
## Dependencias resueltas
| Dependency | Before | After | Management | Remediates |
| --- | --- | --- | --- | --- |
| `jackson-core` / `jackson-databind` | 2.21.2 | 2.21.4 | Spring Boot BOM | GHSA-r7wm-3cxj-wff9, CVE-2026-54512, CVE-2026-54513 |
| `micrometer-core` | 1.15.11 | 1.15.12 | Spring Boot BOM | CVE-2026-40983, CVE-2026-40984 |
| `spring-data-commons` | 3.5.11 | 3.5.13 | Spring Boot BOM | CVE-2026-41695, CVE-2026-41716 |
| `spring-expression` / `spring-webmvc` | 6.2.18 | 6.2.19 | Spring Boot BOM | CVE-2026-41850, CVE-2026-41842, CVE-2026-41845 |
| `tomcat-embed-{core,el,websocket}` | 10.1.54 | 10.1.59 | Spring Boot BOM property override | CVE-2026-65182, CVE-2026-65905, CVE-2026-68525 |

## Hallazgos restantes de Tomcat
El escaneo requiere Tomcat 10.1.58 para parte de los hallazgos restantes. eso
La versión no se lanzó a Maven Central, pero el mantenimiento compatible posterior
La versión `10.1.59` se publica para todos los módulos Tomcat integrados. Bota de primavera
De lo contrario, 3.5.16 administra 10.1.55, por lo que es compatible con `tomcat.version`
La anulación de propiedad hace avanzar a toda la familia Tomcat integrada. esto es
limitado a la línea de mantenimiento ascendente de Tomcat y fue verificado por Maven
árbol de dependencia; no se declara directamente ningún módulo Tomcat individual.
No se utiliza ninguna regla de ignorar de Trivy. Este servicio utiliza Tomcat integrado para el ingreso HTTP,
por lo que los hallazgos se tratan según corresponda y el artefacto actualizado debe ser
reescaneado en la imagen final del contenedor.
