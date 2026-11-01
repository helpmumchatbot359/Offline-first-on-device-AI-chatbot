#!/usr/bin/env bash
# Tests login + the 3 sync endpoints. Needs: curl and python3.
# Usage:
#   export API_KEY="your-key"
#   export USER_EMAIL="you@example.com"
#   export USER_PASSWORD="your-password"
#   bash test_api.sh
set -u

# NOTE: no trailing slash! "https://x.net/" + "/user/login" => "//user/login" => 404/403
BASE_URL="${BASE_URL:-https://d2g5avlpkj63xl.cloudfront.net}"
BASE_URL="${BASE_URL%/}"

: "${API_KEY:?Set API_KEY first (export API_KEY=...)}"
: "${USER_EMAIL:?Set USER_EMAIL first}"
: "${USER_PASSWORD:?Set USER_PASSWORD first}"

# Same header the Flutter app sends (X-API-KEY) -- your original commands forgot it.
COMMON=(-sS -H "X-API-KEY: $API_KEY" -H "Content-Type: application/json")

echo "== 1) Login"
LOGIN_JSON=$(curl "${COMMON[@]}" -X POST "$BASE_URL/user/login" \
  -d "{\"email\":\"$USER_EMAIL\",\"password\":\"$USER_PASSWORD\"}")
TOKEN=$(printf '%s' "$LOGIN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
if [ -z "$TOKEN" ]; then echo "Login failed. Server said: $LOGIN_JSON"; exit 1; fi
echo "Got token (${#TOKEN} chars)"

post() { # name path json
  echo; echo "== $1"
  code=$(curl "${COMMON[@]}" -H "Authorization: Bearer $TOKEN" -o /tmp/resp.txt -w '%{http_code}' \
    -X POST "$BASE_URL$2" -d "$3")
  echo "HTTP $code"; cat /tmp/resp.txt; echo
  [ "$code" = "200" ] && echo "PASS" || echo "FAIL (expected 200)"
}

post "2) chat sync" /v1/chats/sync \
 '{"verify-chat-001":[{"message":"API verification message","ai_response":"API verification response","date":"2026-10-26T12:00:00Z"}]}'

post "3) telemetry" /v1/telemetry \
 '[{"event_uuid":"verify-event-001","event_type":"offline_started","chat_id":"verify-chat-001","date":"2026-10-26T12:00:00Z","connectivity":"offline","metadata":{"source":"api-verification"}}]'

post "4) diagnostic logs" /v1/diagnostic-logs \
 '{"offline_cycle_id":"verify-cycle-001","records":[{"log_id":"verify-log-001","timestamp":"2026-10-26T12:00:00Z","log_type":"memory_measurement","network_state":"no_internet","metrics":{"source":"api-verification"}}]}'