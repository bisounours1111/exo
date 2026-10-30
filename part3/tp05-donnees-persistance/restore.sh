#!/usr/bin/env bash
# restore.sh DUMP: restores a pg_dump -Fc file into the "db" service, then prints the checksum.
#   ./restore.sh backups/shop-20261030-101500.dump
set -euo pipefail
cd "$(dirname "$0")"

DUMP="${1:?usage: restore.sh DUMP}"
COMPOSE_FILE="${COMPOSE_FILE:-starter/compose.yml}"
DB_USER="${DB_USER:-shop}"
DB_NAME="${DB_NAME:-shop}"
compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

compose up -d --wait db >/dev/null
compose exec -T db pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists --no-owner --exit-on-error < "$DUMP"
echo "restored: $DUMP"
compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT count(*) AS orders, md5(string_agg(id::text || status, ',' ORDER BY id)) AS checksum FROM orders"
