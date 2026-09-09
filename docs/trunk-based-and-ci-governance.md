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
3. Obtenga una aprobación, resuelva todas las conversaciones y espere el check
   requerido antes de hacer merge. Un nuevo commit en el PR descarta las
   aprobaciones previas; la revisión debe confirmar el nuevo `HEAD`.
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
configuración verificable exige: PR, una aprobación, descarte de aprobaciones
obsoletas, resolución de conversaciones, estado actualizado respecto de la
rama base, bloqueo de force-push y bloqueo de eliminación. También se aplica a
administradores para que no haya una ruta de bypass silenciosa.

El único check requerido es **`Quality Gate`**, producido por
[`PR Validation`](../.github/workflows/pr-validation.yml). Es un agregador que
falla si fallan compilación, pruebas, Gitleaks, Semgrep, Trivy SCA o Hadolint.
Usar este nombre exacto evita acoplar la regla a jobs internos y a checks que
no se ejecutan para todos los PR.

### Inventario de GitHub Actions

| Workflow | Archivo | Disparador | Permisos declarados | Rol frente al merge |
| --- | --- | --- | --- | --- |
| PR Validation | [`.github/workflows/pr-validation.yml`](../.github/workflows/pr-validation.yml) | `pull_request` a `main` | `contents: read` | **Gate requerido:** `Quality Gate`; agrega Compile, Unit & Integration Tests, Gitleaks, Semgrep, Trivy SCA y Hadolint. Checkov y Helm Lint informan pero hoy usan `soft-fail` o se omiten si no hay archivos. |
| Container security | [`.github/workflows/container-security.yml`](../.github/workflows/container-security.yml) | `pull_request` y `push` a `main` | `contents: read` | Validación complementaria (Hadolint, imagen con Trivy y SBOM). No es requerida para no duplicar el gate y porque su resultado no es el agregador estable del PR. |
| Terraform static validation | [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml) | PR y push a `main`, sólo cambios `terraform/**` | `contents: read` | Operativa/específica de ruta; no puede ser requerida globalmente porque no corre en todos los PR. |
| Build & Release | [`.github/workflows/build-release.yml`](../.github/workflows/build-release.yml) | `push` a `main` | `contents: read`, `id-token: write` | Posterior al merge: empaqueta, escanea, genera SBOM, publica/firma en ECR y despliega a EKS. No es gate de merge. |
| Release | [`.github/workflows/release.yml`](../.github/workflows/release.yml) | tag `v*` | `contents: read`, `packages: write`, `id-token: write` | Posterior a la integración: publica, firma y atestigua una imagen de release. No es gate de merge. |
| Dependabot Updates | [`.github/dependabot.yml`](../.github/dependabot.yml) | programación gestionada por Dependabot | N/A (configuración de Dependabot) | Abre actualizaciones; sus PRs pasan el mismo `Quality Gate` y revisión humana. |

### Límites y revisión

La protección no sustituye una política de CODEOWNERS, ambientes con
aprobaciones, verificación de firmas en el clúster ni gestión de incidentes.
Los workflows de publicación/despliegue se mantienen fuera del merge gate
porque dependen de AWS/ECR/EKS y sólo se ejecutan tras `push` a `main`.
Cualquier cambio a la regla, al nombre del check requerido o a sus triggers
debe revisarse junto con esta documentación para evitar bloquear PRs válidos o
dejar cambios sin validación.
