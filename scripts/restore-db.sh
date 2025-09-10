#!/usr/bin/env bash
set -euo pipefail

# Restore a MediaWiki MariaDB dump into the running Docker Compose stack.
#
# Usage:
#   scripts/restore-db.sh /path/to/dump.sql
#   scripts/restore-db.sh /path/to/dump.sql.gz   # gz compressed dump supported
#
# What it does:
# - Stops the mediawiki web container to avoid writes during import
# - Backs up the current DB to ./data/backup-YYYYmmdd-HHMMSS.sql
# - Imports the given dump into the configured database (MW_DB_NAME)
# - Runs maintenance/update.php to ensure schema matches the current code
# - Starts mediawiki again
#
# Requirements:
# - docker compose available on PATH
# - ./.env present with MW_DB_NAME and MW_DB_ROOT_PASSWORD

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
cd "$repo_root"

if [ $# -ne 1 ]; then
  echo "Usage: $0 /path/to/dump.sql[.gz]" >&2
  exit 1
fi

DUMP_PATH="$1"
if [ ! -f "$DUMP_PATH" ]; then
  echo "Dump file not found: $DUMP_PATH" >&2
  exit 1
fi

# Load DB settings from .env
if [ ! -f .env ]; then
  echo ".env not found in repo root; copy .env.example to .env first." >&2
  exit 1
fi

# shellcheck disable=SC1091
source ./.env

: "${MW_DB_NAME:=wikidb}"
: "${MW_DB_ROOT_PASSWORD:=root_pass}"

DB_NAME="$MW_DB_NAME"
DB_ROOT_PASS="$MW_DB_ROOT_PASSWORD"

timestamp() { date +%Y%m%d-%H%M%S; }

echo "[restore] Using DB: $DB_NAME"

# Quick sanity: ensure db service is up
echo "[restore] Checking that 'db' service is running..."
if ! docker compose ps db --format json >/dev/null 2>&1; then
  echo "Docker Compose not running here or 'db' service missing. Ensure you run from the repo root." >&2
  exit 1
fi

echo "[restore] Stopping mediawiki (to prevent writes during import)..."
docker compose stop mediawiki >/dev/null

backup_file="data/backup-$(timestamp).sql"
echo "[restore] Backing up current database to $backup_file ..."
mkdir -p data
docker compose exec -T db sh -lc "mysqldump -u root -p'${DB_ROOT_PASS}' '${DB_NAME}'" > "$backup_file"
echo "[restore] Backup completed: $backup_file"

echo "[restore] Importing dump from $DUMP_PATH into database '${DB_NAME}' ..."

# Detect compression and choose stream command
case "$DUMP_PATH" in
  *.gz)   READ_CMD=(gzip -dc -- "$DUMP_PATH") ;;
  *.sql)  READ_CMD=(cat -- "$DUMP_PATH") ;;
  *)
    echo "Unsupported dump extension. Use .sql or .sql.gz" >&2
    exit 1
    ;;
esac

# If the dump contains CREATE DATABASE/USE statements for a different DB, they can
# hijack the target. To avoid this, strip those directives on the fly.
# For very large dumps, the stream filter is still efficient.

if grep -E -m1 -n '^(CREATE DATABASE|USE )' "$DUMP_PATH" >/dev/null 2>&1; then
  echo "[restore] Stripping CREATE DATABASE/USE directives from dump stream (to target ${DB_NAME})..."
  FILTER_CMD=(sed -E '/^(CREATE DATABASE|USE )/d')
else
  FILTER_CMD=(cat)
fi

# Perform the import
set -o pipefail
"${READ_CMD[@]}" | "${FILTER_CMD[@]}" | docker compose exec -T db sh -lc "mysql -u root -p'${DB_ROOT_PASS}' '${DB_NAME}'"
set +o pipefail

echo "[restore] Import completed. Running maintenance/update.php ..."
docker compose exec mediawiki php maintenance/update.php --quick

echo "[restore] Starting mediawiki ..."
docker compose start mediawiki >/dev/null

echo "[restore] Done. Visit your wiki to verify content."
