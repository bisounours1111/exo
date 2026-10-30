#!/usr/bin/env bash
# backup.sh: logical dump (pg_dump -Fc) and raw copy of the PostgreSQL volume, 7 most recent kept.
# Everything runs in containers: no psql client needed on the host.
#   ./backup.sh                      # starter stack (PostgreSQL 14)
#   COMPOSE_FILE=... ./backup.sh     # another stack with a "db" service
set -euo pipefail
cd "$(dirname "$0")"
export MSYS_NO_PATHCONV=1

COMPOSE_FILE="${COMPOSE_FILE:-starter/compose.yml}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
KEEP="${KEEP:-7}"
DB_USER="${DB_USER:-shop}"
DB_NAME="${DB_NAME:-shop}"
compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
host_path() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else echo "$1"; fi; }

mkdir -p "$BACKUP_DIR"
ts=$(date +%Y%m%d-%H%M%S)

# 1. Logical dump, consistent while the database is running (single transaction snapshot).
compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$BACKUP_DIR/$DB_NAME-$ts.dump"
echo "dump: $BACKUP_DIR/$DB_NAME-$ts.dump ($(wc -c < "$BACKUP_DIR/$DB_NAME-$ts.dump") bytes)"

# 2. Raw copy of the volume. PostgreSQL is stopped during the copy: copying the files of a running
#    server gives an inconsistent snapshot.
container=$(compose ps -q db)
volume=$(docker inspect "$container" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')
compose stop db >/dev/null
docker run --rm -v "$volume":/data:ro -v "$(host_path "$PWD/$BACKUP_DIR")":/backup alpine:3.20 \
  tar czf "/backup/$volume-$ts.tar.gz" -C /data .
compose start db >/dev/null
echo "raw:  $BACKUP_DIR/$volume-$ts.tar.gz (volume $volume)"

# 3. Retention: the KEEP most recent of each kind.
for pattern in "$DB_NAME-*.dump" "$volume-*.tar.gz"; do
  # shellcheck disable=SC2012
  ls -1t "$BACKUP_DIR"/$pattern 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f -- "$old"
    echo "pruned: $old"
  done
done
