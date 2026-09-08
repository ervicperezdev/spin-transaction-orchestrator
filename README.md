# Spin Transaction Orchestrator

MVP backend for transaction orchestration. It uses Java 21, Spring Boot, Maven and PostgreSQL.

## Prerequisites

- JDK 21
- Docker with Docker Compose v2

## Run locally

Start PostgreSQL:

```bash
docker compose up -d postgres
```

Run the API:

```bash
./mvnw spring-boot:run
```

Verify the application and database connection:

```bash
curl http://localhost:8080/actuator/health
```

Stop the local database while preserving data:

```bash
docker compose down
```

To remove local database data too, run `docker compose down --volumes`.

## Configuration

The local defaults are intentionally non-secret development values. Override them with environment variables when needed:

| Variable | Default |
| --- | --- |
| `DB_URL` | `jdbc:postgresql://localhost:5432/transactions` |
| `DB_USERNAME` | `transactions_app` |
| `DB_PASSWORD` | `transactions_app` |
| `SERVER_PORT` | `8080` |
| `PAYMENT_PROVIDER_BASE_URL` | `http://localhost:9090` |
| `PAYMENT_PROVIDER_CONNECT_TIMEOUT` | `2s` |
| `PAYMENT_PROVIDER_READ_TIMEOUT` | `3s` |

## Payment provider contract

The outbound adapter sends `POST /payments` with `transactionId`, `type`, `amount`, and
`currency`. It expects an `APPROVED` response containing `reference`, or a `REJECTED`
response containing `rejectionReason`. HTTP 4xx/5xx responses, malformed responses, and
network failures are translated to `PaymentProviderUnavailableException`; they never leak
HTTP client types into the domain or application port.

Copy `.env.example` only for local convenience; `.env` is ignored and must never contain production credentials.

## Package conventions

Code lives below `com.spin.transactionorchestrator`. Future features should keep transport, application use cases, domain logic and infrastructure adapters in separate packages. This keeps the MVP structure simple while leaving clear seams for the provider adapter and persistence work.

## Transaction validation errors

Before calling a payment provider, the application validates transaction input with the
following stable domain error codes: `INVALID_TRANSACTION_TYPE`, `INVALID_AMOUNT`,
`UNSUPPORTED_CURRENCY`, and `DEBIT_AMOUNT_LIMIT_EXCEEDED`. The current transport adapter
does not yet expose them over HTTP; it must map these codes without changing them when added.

## List transactions

`GET /transactions` returns a paged response and never exposes persistence entities. It defaults to
`page=0` and `size=20`; `page` is zero-based and `size` must be between 1 and 100. Optional
`status` (`PENDING`, `APPROVED`, `REJECTED`) and `type` (`DEBIT`, `CREDIT`) filters can be combined.
Results are ordered by `createdAt` descending and then `id` descending for deterministic pagination.

```json
{"items": [], "page": 0, "size": 20, "totalItems": 0, "totalPages": 0}
```

Invalid paging or filter values return HTTP 400 with `code: "INVALID_QUERY_PARAMETER"`.
The interactive OpenAPI documentation is available at `/swagger-ui/index.html` when the application is running.

## Build and test

```bash
./mvnw verify
```

The project compiles with Java 21. No real financial data or credentials are required for local development.

## Container image and smoke test

Build the production image from a clean checkout:

```bash
docker build --tag spin-transaction-orchestrator:local .
```

The build stage uses Maven with Java 21. The runtime stage is
`gcr.io/distroless/java21-debian12:nonroot`, so it contains only the application
and Java runtime; Maven and build tools are not shipped. The application runs as
the image's unprivileged `nonroot` user.

Start the local database, then run the image with the database hostname set to
the Compose service name:

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

In a second terminal, confirm the HTTP smoke test:

```bash
curl --fail http://localhost:8080/actuator/health
```

Stop the container with `docker stop spin-transaction-orchestrator`; use
`docker compose down` to stop the local database.

## Container security checks

The `Container security` GitHub Actions workflow runs for pull requests to
`main` and for updates to `main`. It uses fixed tool image versions and has two
independent gates:

- **Hadolint** evaluates `Dockerfile` using `.hadolint.yaml`. The policy fails
  on errors and currently has no ignored rules. A future exception must be
  recorded in that file with its reason and reviewed in the corresponding PR.
- **Trivy** builds the image locally in the runner, exports it to a temporary
  tarball, and scans both OS/application vulnerabilities and embedded secrets.
  It fails the job for any `HIGH` or `CRITICAL` finding, including unfixed
  findings; the scan does not receive registry credentials, build secrets, or
  application configuration.

Run the same checks from a clean checkout (Docker is required):

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

Do not suppress exploitable critical findings. If a finding needs temporary
triage, capture its package, installed/fixed versions, reachability, owner and
remediation date in the PR or issue; keep the failing gate until an approved
exception is documented and time-bounded. Never pass secrets as Docker build
arguments or commit them into the image.
