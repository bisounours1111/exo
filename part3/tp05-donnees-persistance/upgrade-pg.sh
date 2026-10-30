#!/usr/bin/env bash
# upgrade-pg.sh: PostgreSQL 14 -> 16 by dump and restore on a new volume.
# Rollback: docker compose -f starter/compose.yml up -d   (PostgreSQL 14 on the untouched pgdata volume)
set -euo pipefail
cd "$(dirname "$0")"

OLD=(-f starter/compose.yml)
NEW=(-f starter/compose.yml -f compose.pg16.yml)
BACKUP_DIR=backups
CHECKSUM_SQL="SELECT count(*) || ' ' || md5(string_agg(id::text || status, ',' ORDER BY id)) FROM orders"
mkdir -p "$BACKUP_DIR"
ts=$(date +%Y%m%d-%H%M%S)
checksum() { docker compose "$@" exec -T db psql -U shop -d shop -tAc "$CHECKSUM_SQL"; }

echo "== 1. checksum on $(docker compose "${OLD[@]}" exec -T db postgres --version)"
before=$(checksum "${OLD[@]}")
echo "before: $before"

echo "== 2. dumps"
docker compose "${OLD[@]}" exec -T db pg_dumpall -U shop > "$BACKUP_DIR/upgrade-$ts.dumpall.sql"
docker compose "${OLD[@]}" exec -T db pg_dump -U shop -d shop -Fc > "$BACKUP_DIR/upgrade-$ts.dump"
ls -l "$BACKUP_DIR/upgrade-$ts".*

echo "== 3. stop PostgreSQL 14 (volume pgdata kept)"
docker compose "${OLD[@]}" stop db

echo "== 4. PostgreSQL 16 on the new volume pgdata16"
docker compose "${NEW[@]}" up -d --wait db
docker compose "${NEW[@]}" exec -T db postgres --version

echo "== 5. restore"
docker compose "${NEW[@]}" exec -T db pg_restore -U shop -d shop --no-owner --exit-on-error < "$BACKUP_DIR/upgrade-$ts.dump"

echo "== 6. checksum on PostgreSQL 16"
after=$(checksum "${NEW[@]}")
echo "after:  $after"

if [ "$before" = "$after" ]; then
  echo "VERDICT: OK, identical data on PostgreSQL 16"
else
  echo "VERDICT: FAILED, rolling back to PostgreSQL 14"
  docker compose "${OLD[@]}" up -d --wait db
  exit 1
fi
