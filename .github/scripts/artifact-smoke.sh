#!/usr/bin/env bash
set -Eeuo pipefail

: "${ARTIFACT_IMAGE:?Set ARTIFACT_IMAGE to the locally built image tag}"
COMPOSE_PROJECT_NAME="artifact-smoke-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
COMPOSE=(docker compose --project-name "$COMPOSE_PROJECT_NAME" -f compose.yaml -f .github/compose.artifact-smoke.yml)

cleanup() {
  local result=$?
  if (( result != 0 )); then
    echo 'Artifact smoke failed; container logs follow.' >&2
    "${COMPOSE[@]}" logs --no-color || true
  fi
  "${COMPOSE[@]}" down --volumes --remove-orphans || true
  exit "$result"
}
trap cleanup EXIT

"${COMPOSE[@]}" up --detach --wait postgres
"${COMPOSE[@]}" up --detach app

for attempt in {1..30}; do
  if curl --fail --silent --show-error --max-time 3 http://127.0.0.1:18080/actuator/health; then
    break
  fi
  if (( attempt == 30 )); then
    echo 'Application did not become healthy within 90 seconds.' >&2
    exit 1
  fi
  sleep 3
done

# Read-only, bounded request: exercises Spring MVC and PostgreSQL without
# creating a financial transaction or contacting a payment provider.
curl --fail --silent --show-error --max-time 5 \
  'http://127.0.0.1:18080/transactions?page=0&size=1' >/dev/null
