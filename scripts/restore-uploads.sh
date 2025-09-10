#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage: $0 <archive.(zip|tar.gz|tgz)> [--service SERVICE] [--yes]

Restores a MediaWiki uploads/images archive into the running container.

Examples:
  bash $0 images.zip
  bash $0 uploads.tar.gz --service mediawiki
USAGE
}

SERVICE="mediawiki"
YES=0
ARCHIVE=""

while (( "$#" )); do
  case "$1" in
    --service)
      shift; SERVICE="${1:-mediawiki}" ;;
    -y|--yes)
      YES=1 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)
      if [[ -z "$ARCHIVE" ]]; then ARCHIVE="$1"; else echo "Unexpected arg: $1" >&2; usage; exit 2; fi ;;
  esac
  shift || true
done

if [[ -z "$ARCHIVE" ]]; then
  echo "Error: missing archive path." >&2
  usage; exit 2
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Error: archive not found: $ARCHIVE" >&2
  exit 2
fi

TYPE=""
REMOTE_NAME=""
case "$ARCHIVE" in
  *.tar.gz|*.tgz)
    TYPE="tar"; REMOTE_NAME="/tmp/uploads.tar.gz" ;;
  *.zip)
    TYPE="zip"; REMOTE_NAME="/tmp/uploads.zip" ;;
  *)
    echo "Unsupported archive type. Use .zip or .tar.gz/.tgz" >&2
    exit 2 ;;
esac

echo "Service: $SERVICE"
echo "Archive: $ARCHIVE ($TYPE)"

if [[ $YES -ne 1 ]]; then
  read -r -p "Proceed to restore uploads into container '$SERVICE'? [y/N] " ans
  case "${ans,,}" in
    y|yes) : ;; 
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "==> Copying archive into container..."
docker compose cp "$ARCHIVE" "$SERVICE:$REMOTE_NAME"

echo "==> Restoring uploads inside container... (this may take a while)"
docker compose exec -T "$SERVICE" sh -lc "set -eu; \
  ARCH='$REMOTE_NAME'; TYPE='$TYPE'; \
  WORK=\"\$(mktemp -d /tmp/uploads.extract.XXXXXX)\"; TARGET=/var/www/html/images; \
  echo 'Creating workdir' ; mkdir -p \"\$TARGET\"; \
  # Backup non-empty images dir
  if [ \"\$(ls -A \"\$TARGET\" 2>/dev/null | wc -l)\" -gt 0 ]; then \
    ts=\"\$(date +%Y%m%d-%H%M%S)\"; echo \"Backing up existing images to /var/www/html/images.bak-\$ts\"; \
    cp -a \"\$TARGET\" \"/var/www/html/images.bak-\$ts\"; \
  fi; \
  # Extract
  if [ \"\$TYPE\" = tar ]; then \
    tar -xzf \"\$ARCH\" -C \"\$WORK\"; \
  else \
    unzip -q -o \"\$ARCH\" -d \"\$WORK\"; \
  fi; \
  copied=0; \
  # Layout 1: mediawiki-*/images
  for d in \"\$WORK\"/mediawiki-*/images; do \
    if [ -d \"\$d\" ]; then \
      echo \"Detected layout: mediawiki-*/images\"; \
      cp -a \"\$d\"/. \"\$TARGET\"/; copied=1; \
    fi; \
  done; \
  # Layout 2: images/ at root
  if [ \"\$copied\" -eq 0 ] && [ -d \"\$WORK/images\" ]; then \
    echo \"Detected layout: images/\"; \
    cp -a \"\$WORK/images\"/. \"\$TARGET\"/; copied=1; \
  fi; \
  # Layout 3: hashed subdirs only
  if [ \"\$copied\" -eq 0 ]; then \
    echo \"Detected layout: hashed subdirs at root\"; \
    cp -a \"\$WORK\"/. \"\$TARGET\"/; copied=1; \
  fi; \
  echo 'Fixing ownership and permissions'; \
  chown -R www-data:www-data \"\$TARGET\"; \
  find \"\$TARGET\" -type d -exec chmod 755 {} +; \
  find \"\$TARGET\" -type f -exec chmod 644 {} +; \
  echo 'Refreshing image metadata (may take time)'; \
  php maintenance/refreshImageMetadata.php --force; \
  php maintenance/rebuildImages.php --missing || echo 'rebuildImages reported errors; continuing'; \
  rm -rf \"\$WORK\"; \
  echo 'Uploads restore complete.' \
"

echo "Done. Visit Special:ListFiles to verify."
