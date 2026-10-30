#!/usr/bin/env bash
# load.sh [N] [CONCURRENCY]: load test of the TP04 API, run with hey from a container on shop_front.
#   ./load.sh 1000                 # mixed load through Traefik: 80% /products, 10% /orders, 10% /ready
#   PAYLOAD_KB=97 ./load.sh 6000 1000
#                                  # POST /orders only, with a ~97 KB JSON body (memory pressure)
# TARGET defaults to Traefik (Host: api.localhost); TARGET=http://<api ip>:3000 hits one replica.
set -euo pipefail
export MSYS_NO_PATHCONV=1

N="${1:-1000}"
CONCURRENCY="${2:-20}"
PAYLOAD_KB="${PAYLOAD_KB:-0}"
TARGET="${TARGET:-http://traefik}"
HEY_IMAGE=williamyeh/hey@sha256:6e63ae9c5801204cf7abe22c9ddf82d1bcbc7140ffd206a9bd83a8a643dcd6f2

# Status codes as printed by hey, errors grouped by type (hey prints one line per connection).
summarize() {
  awk -v path="$1" '
    /Status code distribution/ { sec = "status"; next }
    /Error distribution/       { sec = "error"; next }
    /^$/                       { sec = ""; next }
    sec == "status" && /\[/    { print "  " path "\t" $1 "\t" $2; next }
    sec == "error" && /\[/     { n = $1; gsub(/[^0-9]/, "", n); $1 = ""; msg = $0
                                 gsub(/ (read|write|dial) tcp [^:]*:[0-9]+(->[^:]*:[0-9]+)?:/, "", msg)
                                 sub(/.*: /, "", msg); err[msg] += n }
    END { for (m in err) print "  " path "\terror\t" err[m] "\t" m }'
}

# Runs hey from a container and prints its summary.
hey() {
  local n=$1 path=$2; shift 2
  docker run --rm --network shop_front --entrypoint sh "$HEY_IMAGE" -c "
    printf '{\"productId\": 1, \"quantity\": 1, \"note\": \"%s\"}' \"\$(head -c $((PAYLOAD_KB * 1024)) /dev/zero | tr '\\\\0' a)\" > /tmp/order.json
    /hey -n $n -c $(( CONCURRENCY < n ? CONCURRENCY : n )) -host api.localhost $* $TARGET$path" \
    | summarize "$path"
}

if [ "$PAYLOAD_KB" -gt 0 ]; then
  hey "$N" /orders -m POST -T application/json -D /tmp/order.json
else
  hey $((N * 8 / 10)) /products &
  hey $((N / 10)) /orders -m POST -T application/json -D /tmp/order.json &
  hey $((N / 10)) /ready &
  wait
fi
