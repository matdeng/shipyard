#!/usr/bin/env bash
# Usage: scripts/smoke-test.sh http://localhost:8080
set -euo pipefail
URL="${1:-http://localhost:8080}"
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; exit 1; }

echo "Smoke testing $URL"
curl -fsS "$URL/" | grep -q "Shipyard"                       && pass "frontend served by nginx" || fail "frontend"
curl -fsS "$URL/nginx-health" >/dev/null 2>&1 || true
info=$(curl -fsS "$URL/api/info")                              && pass "API reachable through nginx" || fail "API"
echo "$info" | grep -q '"storage":"redis"'                     && pass "API is using Redis" || fail "storage is not redis: $info"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d '{"name":"smoke","text":"smoke test"}' "$URL/api/messages")
[[ "$code" == "201" ]]                                         && pass "can post to the ship log" || fail "post returned $code"
echo "All checks passed."
