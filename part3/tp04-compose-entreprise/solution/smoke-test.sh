#!/usr/bin/env bash
# Smoke test of the running stack, through Traefik.
set -euo pipefail
cd "$(dirname "$0")"

BASE_URL="${BASE_URL:-http://api.localhost}"

echo "== /ready"
curl -fsS "$BASE_URL/ready"; echo

echo "== /products (second call must be a cache HIT)"
curl -fsS -o /dev/null "$BASE_URL/products"
cache=$(curl -fsS -D - -o /dev/null "$BASE_URL/products" | tr -d '\r' | awk -F': ' 'tolower($1) == "x-cache" {print $2}')
[ "$cache" = "HIT" ] || { echo "FAIL: X-Cache=$cache"; exit 1; }
echo "X-Cache: $cache"

echo "== POST /orders"
curl -fsS -X POST -H 'Content-Type: application/json' -d '{"productId": 1, "quantity": 2}' "$BASE_URL/orders"; echo

echo "== order confirmed by the worker"
for _ in $(seq 1 20); do
  status=$(docker compose exec -T db psql -U shop -d shop -tAc "SELECT status FROM orders ORDER BY id DESC LIMIT 1")
  [ "$status" = "confirmed" ] && { echo "status: $status"; echo "OK"; exit 0; }
  sleep 0.5
done
echo "FAIL: last order status is '$status'"
exit 1
