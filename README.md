# Orquestador de transacciones de giro
Backend MVP para la orquestación de transacciones. Utiliza Java 21, Spring Boot, Maven y PostgreSQL.
## Documentación
- Registros de arquitectura y decisión: `docs/architecture.md` y `docs/adr/`
- Fuente OpenAPI versionada: `docs/openapi.yaml` (la aplicación en ejecución expone `/v3/api-docs`)
- Modelo de seguridad y riesgos conocidos: `docs/security.md`, `docs/threat-model.md` y `SECURITY.md`
- Catálogo de señales y límite operativo: `docs/observability.md`
- Supuestos de capacidad, factores de costos y decisiones de escalamiento: `docs/finops-scalability.md`
- Diseño de clasificación de registros WAF y CloudTrail, GuardDuty, Security Hub: `docs/cloud-security-operations.md`
- Mapeo de control de cumplimiento, evidencia de repositorio y brechas operativas: `docs/compliance-mapping.md`
- Limitaciones actuales, hoja de ruta y declaración de uso de IA: `docs/limitations-roadmap-ai.md`
## Requisitos previos
-JDK 21
- Docker con Docker Compose v2
## Ejecutar localmente
Inicie PostgreSQL:
```bash
docker compose up -d postgres
```

Ejecute la API:
```bash
./mvnw spring-boot:run
```

Verifique la conexión de la aplicación y la base de datos:
```bash
curl http://localhost:8080/actuator/health
```

URL de documentación API y operativa local:
- Salud: `http://localhost:8080/actuator/health`
- OpenAPI JSON: `http://localhost:8080/v3/api-docs`
- Swagger UI: `http://localhost:8080/swagger-ui/index.html`
Solo se exponen los puntos finales de métricas y de estado del actuador. La salud no incluye
detalles de los componentes; Los puntos finales de configuración como `/actuator/env` siguen no disponibles.
Detenga la base de datos local mientras conserva los datos:
```bash
docker compose down
```

Para eliminar también los datos de la base de datos local, ejecute `docker compose down --volumes`.
## Configuración
Los valores predeterminados locales son valores de desarrollo intencionalmente no secretos. Anúlelos con variables de entorno cuando sea necesario:
| Variable | Default |
| --- | --- |
| `DB_URL` | `jdbc:postgresql://localhost:5432/transactions` |
| `DB_USERNAME` | `transactions_app` |
| `DB_PASSWORD` | `transactions_app` |
| `SERVER_PORT` | `8080` |
| `PAYMENT_PROVIDER_BASE_URL` | `http://localhost:9090` |
| `PAYMENT_PROVIDER_CONNECT_TIMEOUT` | `2s` |
| `PAYMENT_PROVIDER_READ_TIMEOUT` | `3s` |

## Contrato de proveedor de pagos
El adaptador de salida envía `POST /payments` con `transactionId`, `type`, `amount` y
`currency`. Espera una respuesta `APPROVED` que contenga `reference` o `REJECTED`.
respuesta que contiene `rejectionReason`. Respuestas HTTP 4xx/5xx, respuestas con formato incorrecto y
las fallas de red se traducen a `PaymentProviderUnavailableException`; nunca gotean
El cliente HTTP escribe en el dominio o puerto de la aplicación.
Copie `.env.example` sólo para conveniencia local; `.env` se ignora y nunca debe contener credenciales de producción.
## Convenciones de paquetes
El código se encuentra debajo de `com.spin.transactionorchestrator`. Las funciones futuras deberían mantener el transporte, los casos de uso de aplicaciones, la lógica de dominio y los adaptadores de infraestructura en paquetes separados. Esto mantiene la estructura de MVP simple y al mismo tiempo deja costuras claras para el adaptador del proveedor y el trabajo de persistencia.
## Errores de validación de transacciones
Antes de llamar a un proveedor de pago, la aplicación valida la entrada de la transacción con el
siguientes códigos de error de dominio estable: `INVALID_TRANSACTION_TYPE`, `INVALID_AMOUNT`,
`UNSUPPORTED_CURRENCY` y `DEBIT_AMOUNT_LIMIT_EXCEEDED`. El adaptador de transporte actual
aún no los expone a través de HTTP; debe asignar estos códigos sin cambiarlos cuando se agregan.
## Listar transacciones
`GET /transactions` devuelve una respuesta paginada y nunca expone entidades de persistencia. Por defecto es
`page=0` y `size=20`; `page` tiene base cero y `size` debe estar entre 1 y 100. Opcional
Los filtros `status` (`PENDING`, `APPROVED`, `REJECTED`) y `type` (`DEBIT`, `CREDIT`) se pueden combinar.
Los resultados se ordenan mediante `createdAt` descendente y luego `id` descendente para una paginación determinista.
```json
{"items": [], "page": 0, "size": 20, "totalItems": 0, "totalPages": 0}
```

Los valores de filtro o paginación no válidos devuelven HTTP 400 con `code: "INVALID_QUERY_PARAMETER"`.
El documento OpenAPI describe los contratos de solicitud, éxito, paginación/filtro y error;
está disponible en `/v3/api-docs`, con documentación interactiva en `/swagger-ui/index.html`.
## Construir y probar
```bash
./mvnw verify
```

El proyecto se compila con Java 21. No se requieren credenciales ni datos financieros reales para el desarrollo local.
## Imagen del contenedor y prueba de humo.
Cree la imagen de producción a partir de una caja limpia:
```bash
docker build --tag spin-transaction-orchestrator:local .
```

La etapa de compilación utiliza Maven con Java 21. La etapa de ejecución es
`gcr.io/distroless/java21-debian12:nonroot`, por lo que contiene sólo la aplicación
y tiempo de ejecución de Java; Maven y las herramientas de compilación no se envían. La aplicación se ejecuta como
El usuario `nonroot` sin privilegios de la imagen.
Inicie la base de datos local, luego ejecute la imagen con el nombre de host de la base de datos configurado en
el nombre del servicio de redacción:
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

En una segunda terminal, confirme la prueba de humo HTTP:
```bash
curl --fail http://localhost:8080/actuator/health
```

Detenga el contenedor con `docker stop spin-transaction-orchestrator`; usar
`docker compose down` para detener la base de datos local.
## Controles de seguridad de contenedores
El flujo de trabajo de GitHub Actions `Container security` se ejecuta para solicitudes de extracción para
`main` y para actualizaciones de `main`. Utiliza versiones de imágenes de herramientas fijas y tiene dos
puertas independientes:
- **Hadolint** evalúa `Dockerfile` usando `.hadolint.yaml`. La política fracasa
  basado en errores y actualmente no tiene reglas ignoradas. Una futura excepción debe ser
  registrado en dicho expediente con su motivo y revisado en el PR correspondiente.
- **Trivy** crea la imagen localmente en el corredor y la exporta a un archivo temporal.
  tarball y escanea tanto las vulnerabilidades del sistema operativo/aplicaciones como los secretos integrados.
  Falla el trabajo para cualquier hallazgo `HIGH` o `CRITICAL`, incluidos los no reparados.
  hallazgos; el escaneo no recibe credenciales de registro, secretos de compilación o
  configuración de la aplicación.
Ejecute las mismas comprobaciones desde un checkout limpio (se requiere Docker):
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

No suprima los hallazgos críticos explotables. Si un hallazgo necesita temporal
clasificación, captura de su paquete, versiones instaladas/reparadas, accesibilidad, propietario y
fecha de remediación en el PR o emisión; Mantenga la puerta defectuosa hasta que se apruebe
La excepción está documentada y tiene un límite de tiempo. Nunca pases secretos mientras construye Docker
argumentos o plasmarlos en la imagen.
El flujo de trabajo `Container security` también genera una SBOM (Software Bill of
Materials) en formato SPDX-JSON desde el mismo tarball de imagen usando Syft y
lo carga como un artefacto de flujo de trabajo (`sbom-<sha>`). Ejecutar localmente con:
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

## Firma de imágenes y certificación SBOM (lanzamiento)
El flujo de trabajo de GitHub Actions `Release` se activa en etiquetas de versión (`v*`). eso
construye y empuja a `ghcr.io`, luego firma la imagen y certifica el SBOM
usando Cosign con una identidad OIDC efímera sin llave emitida por GitHub Actions.
No se almacenan claves privadas ni tokens en el repositorio ni en la imagen.
Verifique una firma de imagen publicada (requiere `cosign` instalado):
```bash
cosign verify \
  --certificate-identity-regexp \
    "https://github.com/ervicperezdev/spin-transaction-orchestrator/.github/workflows/release.yml" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/ervicperezdev/spin-transaction-orchestrator:<tag>
```

Verifique y extraiga la certificación SBOM:
```bash
cosign verify-attestation \
  --type spdxjson \
  --certificate-identity-regexp \
    "https://github.com/ervicperezdev/spin-transaction-orchestrator/.github/workflows/release.yml" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/ervicperezdev/spin-transaction-orchestrator:<tag> \
  | jq -r '.payload | @base64d | fromjson | .predicate'
```

El SBOM corresponde al digest de la imagen publicada. La aplicación mediante un admission controller
La aplicación de las políticas de firma y SBOM es una infraestructura separada.
evolución y no se implementa aquí.
