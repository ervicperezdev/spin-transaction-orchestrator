## Gobierno de ramas, trunk-based development y CI/CD

Este repositorio usa **trunk-based development**: `main` es la única rama de
integración estable y protegida. La política busca reducir el riesgo de
integraciones largas sin convertir los despliegues de producción en un efecto
secundario de cada validación de pull request.

### Flujo de cambio

1. Cree una rama desde `main` y abra un pull request (PR) de vuelta a `main`.
   No se permiten pushes directos a `main`.
2. Mantenga la rama con una vida ideal de uno o dos días y sincronícela con
   `main` con frecuencia. Divida trabajos grandes en PRs pequeños, revisables
   e integrables de forma independiente.
3. Resuelva todas las conversaciones y espere el check requerido antes de hacer
   merge. Las revisiones de otras personas son recomendadas para cambios de
   riesgo, pero no son obligatorias: el propietario puede integrar sus propios
   PRs tras completar el gate.
4. Integre con squash merge o merge commit según la convención acordada por el
   equipo, conservando un mensaje que explique el cambio. Evite mantener ramas
   de integración compartidas o divergentes.

Convenciones de nombre:

| Propósito | Patrón | Ejemplo |
| --- | --- | --- |
| Funcionalidad | `feature/<tema>` | `feature/idempotency-metrics` |
| Corrección no urgente | `fix/<tema>` | `fix/retry-timeout` |
| Seguridad urgente | `hotfix/<tema>` | `hotfix/cve-library` |
| Documentación | `docs/<tema>` | `docs/ci-governance` |
| Mantenimiento | `chore/<tema>` | `chore/dependency-update` |

Use feature flags para cambios que no puedan quedar completos dentro de un PR
pequeño, para activaciones graduales o para separar despliegue de exposición.
El código bajo un flag debe ser seguro por defecto, tener propietario y fecha o
criterio de retirada. Un flag no sustituye pruebas, revisión ni el control de
acceso.

### Hotfixes y releases

Un hotfix sigue el mismo PR y gate que cualquier cambio: se crea una rama
`hotfix/*` desde el `main` actual, se valida, revisa y fusiona a `main`. No hay
excepción para push directo, force-push o borrado de `main`. Si una mitigación
operativa urgente exige una acción fuera del repositorio, debe registrar el
incidente y reconciliar el cambio mediante PR inmediatamente después.

Las releases versionadas se inician exclusivamente con un tag `v*` creado
sobre un commit ya integrado en `main`; no existe una rama `release/*`
permanente. Esto conserva una sola línea de integración y una procedencia
trazable del artefacto.

### Regla de protección de `main`

La protección se configura en GitHub, no en un archivo del repositorio. Su
configuración verificable exige: PR, resolución de conversaciones, estado
actualizado respecto de la rama base, bloqueo de force-push y bloqueo de
eliminación. No se requiere aprobación externa: GitHub no permite que el autor
apruebe su propio PR, por lo que exigir una aprobación bloquearía al
propietario cuando trabaja solo. La invalidación de revisiones obsoletas se
mantiene configurada para que una aprobación opcional no sobreviva a cambios
del `HEAD`. La regla también se aplica a administradores para que no haya una
ruta de bypass silenciosa.

Todos los checks que se ejecutan para cada PR a `main` son requeridos antes del
merge. Los nombres exactos configurados son: **`Compile`**, **`Unit &
Integration Tests`**, **`Gitleaks – Secret Scan`**, **`Semgrep – SAST`**,
**`Trivy – SCA (Dependency Scan)`**, **`Checkov – IaC Scan`**, **`Helm Lint`**,
**`Hadolint – Dockerfile Lint`**, **`Quality Gate`**, **`Lint Dockerfile`** y
**`Scan container image`**. Los nueve primeros proceden de
[`PR Validation`](../.github/workflows/pr-validation.yml), y los dos últimos
de [`Container security`](../.github/workflows/container-security.yml).
`Quality Gate` se mantiene como agregador defensivo de los controles críticos;
los checks individuales hacen visible y obligatorio cada resultado en GitHub.

### Inventario de GitHub Actions

| Workflow | Archivo | Disparador | Permisos declarados | Rol frente al merge |
| --- | --- | --- | --- | --- |
| PR Validation | [`.github/workflows/pr-validation.yml`](../.github/workflows/pr-validation.yml) | `pull_request` a `main` | `contents: read` | **Checks requeridos:** Compile, Unit & Integration Tests, Gitleaks, Semgrep, Trivy SCA, Checkov, Helm Lint, Hadolint y Quality Gate. Checkov conserva `soft-fail` en sus escaneos y Helm Lint puede omitir el paso si no hay chart, pero sus jobs deben completar correctamente. |
| Container security | [`.github/workflows/container-security.yml`](../.github/workflows/container-security.yml) | `pull_request` y `push` a `main` | `contents: read` | **Checks requeridos en PR:** Lint Dockerfile y Scan container image; además genera SBOM. |
| Terraform static validation | [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml) | PR y push a `main`, sólo cambios `terraform/**` | `contents: read` | Operativa/específica de ruta; no puede ser requerida globalmente porque no corre en todos los PR. |
| Build & Release | [`.github/workflows/build-release.yml`](../.github/workflows/build-release.yml) | `push` a `main` | `contents: read`, `id-token: write` | Posterior al merge: empaqueta, escanea, genera SBOM, publica/firma en ECR y despliega a EKS. No es gate de merge. |
| Release | [`.github/workflows/release.yml`](../.github/workflows/release.yml) | tag `v*` | `contents: read`, `packages: write`, `id-token: write` | Posterior a la integración: publica, firma y atestigua una imagen de release. No es gate de merge. |
| Dependabot Updates | [`.github/dependabot.yml`](../.github/dependabot.yml) | programación gestionada por Dependabot | N/A (configuración de Dependabot) | Abre actualizaciones; sus PRs pasan el mismo `Quality Gate` y revisión humana. |

### Límites y revisión

La protección no sustituye una política de CODEOWNERS, ambientes con
aprobaciones, verificación de firmas en el clúster ni gestión de incidentes.
La ausencia de una aprobación obligatoria es una concesión explícita para un
repositorio de propietario único; se debe restablecer al menos una aprobación
externa al incorporar colaboradores con capacidad de revisión.
Los workflows de publicación/despliegue se mantienen fuera del merge gate
porque dependen de AWS/ECR/EKS y sólo se ejecutan tras `push` a `main`.
Cualquier cambio a la regla, a los nombres de checks requeridos o a sus
triggers debe revisarse junto con esta documentación. GitHub no ofrece una
regla comodín segura para "todo check futuro": al agregar, renombrar o quitar
un job que corra en cada PR se debe actualizar explícitamente esta lista. Los
workflows con filtros de ruta, de `push` o de tags no se incluyen para evitar
bloquear PRs válidos en los que no se ejecutan.
