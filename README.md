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

Copy `.env.example` only for local convenience; `.env` is ignored and must never contain production credentials.

## Package conventions

Code lives below `com.spin.transactionorchestrator`. Future features should keep transport, application use cases, domain logic and infrastructure adapters in separate packages. This keeps the MVP structure simple while leaving clear seams for the provider adapter and persistence work.

## Build and test

```bash
./mvnw verify
```

The project compiles with Java 21. No real financial data or credentials are required for local development.
