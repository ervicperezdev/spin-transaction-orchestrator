# syntax=docker/dockerfile:1
FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /workspace

COPY pom.xml ./
RUN mvn --batch-mode --no-transfer-progress dependency:go-offline

COPY src ./src
RUN mvn --batch-mode --no-transfer-progress package -DskipTests

FROM gcr.io/distroless/java21-debian13:nonroot

WORKDIR /app

COPY --from=build --chown=nonroot:nonroot /workspace/target/spin-transaction-orchestrator-0.0.1-SNAPSHOT.jar /app/app.jar

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/usr/bin/java", "-jar", "/app/app.jar"]
