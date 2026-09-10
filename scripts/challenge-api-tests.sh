#!/usr/bin/env bash
set -euo pipefail

base_url="${BASE_URL:-https://spin.ervic.pro}"
run_id="$(date +%s)"

request() {
  local expected="$1" method="$2" path="$3" payload="${4:-}"
  local output code
  output="$(mktemp)"
  if [[ -n "$payload" ]]; then
    code="$(curl -sS -o "$output" -w '%{http_code}' -X "$method" "$base_url$path" -H 'Content-Type: application/json' -H "Idempotency-Key: challenge-$run_id-$expected" --data "$payload")"
  else
    code="$(curl -sS -o "$output" -w '%{http_code}' -X "$method" "$base_url$path")"
  fi
  [[ "$code" == "$expected" ]] || { cat "$output"; rm "$output"; echo "Expected HTTP $expected, got $code" >&2; exit 1; }
  cat "$output"; rm "$output"
}

echo 'Health and transaction history'
request 200 GET /actuator/health
request 200 GET '/transactions?page=0&size=5'

echo 'Approved transaction'
request 201 POST /transactions '{"accountId":"acct-provider-approved","description":"challenge approved","type":"DEBIT","amount":25.50,"currency":"MXN"}'

echo 'Rejected transaction is persisted'
request 201 POST /transactions '{"accountId":"acct-provider-rejected","description":"challenge rejected","type":"DEBIT","amount":25.50,"currency":"MXN"}'

echo 'Provider HTTP error -> API 503'
request 503 POST /transactions '{"accountId":"acct-provider-error","description":"challenge provider error","type":"DEBIT","amount":25.50,"currency":"MXN"}'

echo 'Provider timeout -> API 503 (can take about 3 seconds)'
request 503 POST /transactions '{"accountId":"acct-provider-timeout","description":"challenge timeout","type":"DEBIT","amount":25.50,"currency":"MXN"}'

echo 'Request validation -> API 400 and domain rule -> API 422'
request 400 POST /transactions '{"type":"DEBIT","amount":25.50,"currency":"MXN"}'
request 422 POST /transactions '{"accountId":"acct-invalid","type":"DEBIT","amount":1.00,"currency":"MXN"}'

echo 'All challenge HTTP cases passed.'
