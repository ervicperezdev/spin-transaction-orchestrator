# Spin Transaction Orchestrator

Backend MVP para la orquestación de transacciones. Usa Java 21, Spring Boot, Maven y PostgreSQL.

## Documentación

- Arquitectura y registros de decisiones: `docs/architecture.md` y `docs/adr/`
- Fuente OpenAPI versionada: `docs/openapi.yaml` (la aplicación expone `/v3/api-docs`)
- Modelo de seguridad y riesgos conocidos: `docs/security.md`, `docs/threat-model.md` y `SECURITY.md`
- Catálogo de señales y límite operativo: `docs/observability.md`
- Supuestos de capacidad, factores de costo y decisiones de escalabilidad: `docs/finops-scalability.md`
- Diseño de triage para CloudTrail, GuardDuty, Security Hub y logs de AWS WAF: `docs/cloud-security-operations.md`
- Mapeo de controles de cumplimiento, evidencia del repositorio y brechas operativas: `docs/compliance-mapping.md`
- Limitaciones actuales, roadmap y declaración de uso de IA: `docs/limitations-roadmap-ai.md`
- Gobierno trunk-based, ambientes y catálogo de workflows: `docs/trunk-based-and-ci-governance.md`

## Prerrequisitos

- JDK 21
- Docker con Docker Compose v2

## Ejecución local

Inicia PostgreSQL y el provider mock reproducible:

```bash
docker compose up -d
```

Ejecuta la API:

```bash
./mvnw spring-boot:run
```

Verifica la aplicación y la conexión a la base de datos:

```bash
curl http://localhost:8080/actuator/health
```

URLs locales de operación y documentación de API:

- Health: `http://localhost:8080/actuator/health`
- OpenAPI JSON: `http://localhost:8080/v3/api-docs`
- Swagger UI: `http://localhost:8080/swagger-ui/index.html`

Solo se exponen los endpoints de health y metrics de Actuator. Health no incluye detalles de componentes; endpoints de configuración como `/actuator/env` no están disponibles.

Detén la base de datos local preservando los datos:

```bash
docker compose down
```

Para eliminar también los datos locales, ejecuta `docker compose down --volumes`.

## Configuración

Los valores locales predeterminados no contienen secretos y son solo para desarrollo. Sobrescríbelos con variables de entorno cuando sea necesario:

| Variable | Valor predeterminado |
| --- | --- |
| `DB_URL` | `jdbc:postgresql://localhost:5432/transactions` |
| `DB_USERNAME` | `transactions_app` |
| `DB_PASSWORD` | `transactions_app` |
| `SERVER_PORT` | `8080` |
| `PAYMENT_PROVIDER_BASE_URL` | `http://localhost:9090` |
| `PAYMENT_PROVIDER_CONNECT_TIMEOUT` | `2s` |
| `PAYMENT_PROVIDER_READ_TIMEOUT` | `3s` |

## Contrato del payment provider

El outbound adapter envía `POST /provider/v1/execute` con `accountId`, `type`, `amount` (decimal) y `currency`. Una aprobación incluye `transactionId`, `balance` y `executedAt`; una respuesta `REJECTED` persiste el identificador, código y motivo recibidos. Errores HTTP 4xx/5xx, respuestas malformadas, timeouts y errores de red devuelven `503 PAYMENT_PROVIDER_UNAVAILABLE` y no persisten un éxito ficticio.

Ejemplo de transacción aprobada con el mock local:

```bash
curl -X POST http://localhost:8080/transactions -H 'Content-Type: application/json' \
  -d '{"accountId":"acct-123","description":"Purchase order 1042","type":"DEBIT","amount":25.50,"currency":"MXN"}'
```

La respuesta incluye `id`, `accountId`, `description`, `status`, `providerTransactionId`, `balanceAfter` y `createdAt`. El Deployment de WireMock solo se crea con `values-dev.yaml` como `ClusterIP`; no existe plantilla Ingress para el mock.

## Batería HTTP del challenge

Con el deployment actualizado, ejecuta todos los casos por HTTP (aprobación, rechazo, error/timeout del provider, validación HTTP y reglas de dominio):

```bash
BASE_URL=https://spin.ervic.pro ./scripts/challenge-api-tests.sh
```

Los escenarios especiales del mock se seleccionan con `accountId`: `acct-provider-rejected`, `acct-provider-error` y `acct-provider-timeout`. Ninguno expone el mock; las peticiones siguen entrando únicamente por la API pública.

Copia `.env.example` únicamente por comodidad local; `.env` se ignora y nunca debe contener credenciales de producción.

## Convenciones de paquetes

El código está bajo `com.spin.transactionorchestrator`. Las funcionalidades futuras deben mantener transport, application use cases, domain logic e infrastructure adapters en paquetes separados. Esto mantiene simple la estructura del MVP y deja límites claros para el provider adapter y la persistencia.

## Errores de validación de transacciones

Antes de invocar un payment provider, la aplicación valida la entrada con estos códigos estables de domain error: `INVALID_TRANSACTION_TYPE`, `INVALID_AMOUNT`, `UNSUPPORTED_CURRENCY` y `DEBIT_AMOUNT_LIMIT_EXCEEDED`. El transport adapter actual todavía no los expone por HTTP; cuando se agregue, deberá mapearlos sin modificarlos.

## Listado de transacciones

`GET /transactions` devuelve una respuesta paginada y nunca expone entidades de persistencia. Sus valores predeterminados son `page=0` y `size=20`; `page` comienza en cero y `size` debe estar entre 1 y 100. Se pueden combinar los filtros opcionales `status` (`PENDING`, `APPROVED`, `REJECTED`) y `type` (`DEBIT`, `CREDIT`). Los resultados se ordenan por `createdAt` descendente y luego por `id` descendente para una paginación determinista.

```json
{"items": [], "page": 0, "size": 20, "totalItems": 0, "totalPages": 0}
```

Los valores inválidos de paginación o filtros devuelven HTTP 400 con `code: "INVALID_QUERY_PARAMETER"`. El documento OpenAPI describe los contratos de request, success, paginación/filtro y error; está disponible en `/v3/api-docs`, con documentación interactiva en `/swagger-ui/index.html`.

## Build y pruebas

```bash
./mvnw verify
```

El proyecto compila con Java 21. El desarrollo local no requiere datos financieros reales ni credenciales.

## Imagen de contenedor y smoke test

Construye la imagen de producción desde un checkout limpio:

```bash
docker build --tag spin-transaction-orchestrator:local .
```

La etapa de build usa Maven con Java 21. La etapa de runtime es `gcr.io/distroless/java21-debian12:nonroot`, por lo que solo contiene la aplicación y el runtime de Java; Maven y las herramientas de build no se incluyen. La aplicación se ejecuta como el usuario sin privilegios `nonroot` de la imagen.

Inicia la base de datos local y ejecuta la imagen con el hostname de la base de datos configurado al nombre del servicio de Compose:

```bash
docker compose up -d postgres
docker run --rm --name spin-transaction-orchestrator \
  --network spin-transaction-orchestrator_default \
  --publish 8080:8080 \
  --env DB_URL=jdbc:postgresql://postgres:5432/transactions \
  --env DB_USERNAME=transactions_app \
  --env DB_PASSWORD=transactions_app \
  spin-transaction-orchestrator:local
```

En otra terminal, confirma el smoke test HTTP:

```bash
curl --fail http://localhost:8080/actuator/health
```

Detén el contenedor con `docker stop spin-transaction-orchestrator`; usa `docker compose down` para detener la base de datos local.

En CI, el workflow usa `.github/compose.artifact-smoke.yml` sobre la misma imagen
local que acaba de construir: espera PostgreSQL, verifica `/actuator/health` y
hace un `GET /transactions?page=0&size=1` de solo lectura. Si falla, publica los
logs de Compose y siempre elimina contenedores y volúmenes.

## Controles de seguridad del contenedor

El job `Container Image Security` del workflow `Pull Request CI` se ejecuta para cada Pull Request hacia `main`. Usa versiones fijas de imágenes de herramientas e incluye dos gates independientes:

- **Hadolint** evalúa `Dockerfile` con `.hadolint.yaml`. La política falla ante errores y actualmente no ignora reglas. Toda excepción futura debe registrarse en ese archivo con su justificación y revisarse en el PR correspondiente.
- **Trivy** construye la imagen localmente en el runner, la exporta a un tarball temporal y analiza vulnerabilidades de OS/aplicación y secretos embebidos. El job falla ante cualquier hallazgo `HIGH` o `CRITICAL`, incluidos los no corregidos; el escaneo no recibe credenciales de registry, build secrets ni configuración de la aplicación.

Ejecuta los mismos controles desde un checkout limpio (requiere Docker):

```bash
docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile
docker build --tag spin-transaction-orchestrator:security .
docker save --output image.tar spin-transaction-orchestrator:security
docker run --rm \
  --volume "$PWD:/workspace:ro" \
  aquasec/trivy:0.58.1 image \
  --input /workspace/image.tar \
  --scanners vuln,secret \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress
rm image.tar
```

No suprimas hallazgos críticos explotables. Si un hallazgo requiere triage temporal, documenta en el PR o issue el paquete, versiones instalada/corregida, alcance, responsable y fecha de remediación; conserva el gate fallido hasta que exista una excepción aprobada y acotada en el tiempo. Nunca pases secretos como argumentos de Docker build ni los incluyas en la imagen.

El mismo job genera un SBOM (Software Bill of Materials) en formato SPDX-JSON a partir del mismo tarball usando Syft y lo publica como artifact del workflow (`sbom-<sha>`). Para ejecutarlo localmente:

```bash
docker build --tag spin-transaction-orchestrator:security .
docker save --output image.tar spin-transaction-orchestrator:security
docker run --rm \
  --volume "$PWD:/workspace" \
  anchore/syft:v1.18.1 \
  docker-archive:/workspace/image.tar \
  -o spdx-json=/workspace/sbom.spdx.json
rm image.tar
```

## Firma de imagen y attestación de SBOM (producción)

El workflow `Production Release` se activa con un tag protegido `v*` o manualmente indicando ese mismo tag. El GitHub Environment `production` debe requerir aprobación antes de que el job publique en `ghcr.io`, firme la imagen y genere la attestación del SBOM con Cosign usando una identidad OIDC efímera y keyless. El repositorio y la imagen no almacenan claves privadas ni tokens permanentes.

Verifica la firma de una imagen publicada (requiere `cosign`):

```bash
cosign verify \
  --certificate-identity-regexp \
    "https://github.com/ervicperezdev/spin-transaction-orchestrator/.github/workflows/production-release.yml" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/ervicperezdev/spin-transaction-orchestrator:<tag>
```

Verifica y extrae la attestación del SBOM:

```bash
cosign verify-attestation \
  --type spdxjson \
  --certificate-identity-regexp \
    "https://github.com/ervicperezdev/spin-transaction-orchestrator/.github/workflows/production-release.yml" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/ervicperezdev/spin-transaction-orchestrator:<tag> \
  | jq -r '.payload | @base64d | fromjson | .predicate'
```

El SBOM corresponde al digest de la imagen publicada. La aplicación de políticas de firma y SBOM mediante un admission controller es una evolución de infraestructura independiente y no está implementada aquí.

## Excepción temporal del endpoint EKS

La integración conserva el endpoint público de desarrollo para los runners hospedados de GitHub. [EXC-001](docs/security/EXC-001-eks-public-endpoint.md) registra el alcance, los controles, la evidencia pendiente y el vencimiento del 23 de septiembre de 2026. La exclusión de Semgrep se limita a la regla y al recurso indicados; no equivale a verificar la configuración desplegada.
