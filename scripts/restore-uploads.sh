#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage: $0 <archive.(zip|tar.gz|tgz)> [--service SERVICE] [--zip-encoding ENC] [--yes]

Restores a MediaWiki uploads/images archive into the running container.

Examples:
  bash $0 images.zip
  bash $0 uploads.tar.gz --service mediawiki
USAGE
}

SERVICE="mediawiki"
YES=0
ARCHIVE=""
ZIP_ENCODING="${MW_ZIP_ENCODING:-}"

while (( "$#" )); do
  case "$1" in
    --service)
      shift; SERVICE="${1:-mediawiki}" ;;
    --zip-encoding)
      shift; ZIP_ENCODING="${1:-}" ;;
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

if [[ "$TYPE" == zip && -n "$ZIP_ENCODING" ]]; then
  echo "==> ZIP encoding specified ($ZIP_ENCODING); extracting on host to preserve names..."
  HOST_WORK="$(mktemp -d ./uploads.restore.XXXXXX)" || exit 1
  if ! unzip -q -I "$ZIP_ENCODING" "$ARCHIVE" -d "$HOST_WORK"; then
    echo "Error: unzip on host does not support -I or encoding '$ZIP_ENCODING' failed." >&2
    exit 2
  fi
  echo "==> Creating tarball from host-extracted files..."
  TAR_HOST="${HOST_WORK}.tar.gz"
  tar -C "$HOST_WORK" -czf "$TAR_HOST" .
  echo "==> Copying tarball into container..."
  docker compose cp "$TAR_HOST" "$SERVICE:/tmp/uploads.tar.gz"
  echo "==> Restoring uploads inside container from tarball..."
  docker compose exec -T "$SERVICE" sh -lc "set -eu; \
    ARCH='/tmp/uploads.tar.gz'; TYPE='tar'; \
    WORK=\"\$(mktemp -d /tmp/uploads.extract.XXXXXX)\"; TARGET=/var/www/html/images; \
    echo 'Creating workdir' ; mkdir -p \"\$TARGET\"; \
    if [ \"\$(ls -A \"\$TARGET\" 2>/dev/null | wc -l)\" -gt 0 ]; then \
      ts=\"\$(date +%Y%m%d-%H%M%S)\"; echo \"Backing up existing images to /var/www/html/images.bak-\$ts\"; \
      cp -a \"\$TARGET\" \"/var/www/html/images.bak-\$ts\"; \
    fi; \
    tar -xzf \"\$ARCH\" -C \"\$WORK\"; \
    copied=0; \
    for d in \"\$WORK\"/mediawiki-*/images; do \
      if [ -d \"\$d\" ]; then \
        echo \"Detected layout: mediawiki-*/images\"; \
        cp -a \"\$d\"/. \"\$TARGET\"/; copied=1; \
      fi; \
    done; \
    if [ \"\$copied\" -eq 0 ] && [ -d \"\$WORK/images\" ]; then \
      echo \"Detected layout: images/\"; \
      cp -a \"\$WORK/images\"/. \"\$TARGET\"/; copied=1; \
    fi; \
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
  rm -rf "$HOST_WORK" "$TAR_HOST" || true
else
  echo "==> Copying archive into container..."
  docker compose cp "$ARCHIVE" "$SERVICE:$REMOTE_NAME"
  echo "==> Restoring uploads inside container... (this may take a while)"
  docker compose exec -T "$SERVICE" sh -lc "set -eu; \
    ARCH='$REMOTE_NAME'; TYPE='$TYPE'; \
    WORK=\"\$(mktemp -d /tmp/uploads.extract.XXXXXX)\"; TARGET=/var/www/html/images; \
    echo 'Creating workdir' ; mkdir -p \"\$TARGET\"; \
    if [ \"\$(ls -A \"\$TARGET\" 2>/dev/null | wc -l)\" -gt 0 ]; then \
      ts=\"\$(date +%Y%m%d-%H%M%S)\"; echo \"Backing up existing images to /var/www/html/images.bak-\$ts\"; \
      cp -a \"\$TARGET\" \"/var/www/html/images.bak-\$ts\"; \
    fi; \
    if [ \"\$TYPE\" = tar ]; then \
      tar -xzf \"\$ARCH\" -C \"\$WORK\"; \
    else \
      unzip -q -o \"\$ARCH\" -d \"\$WORK\" || echo 'unzip returned non-zero; continuing'; \
    fi; \
    copied=0; \
    for d in \"\$WORK\"/mediawiki-*/images; do \
      if [ -d \"\$d\" ]; then \
        echo \"Detected layout: mediawiki-*/images\"; \
        cp -a \"\$d\"/. \"\$TARGET\"/; copied=1; \
      fi; \
    done; \
    if [ \"\$copied\" -eq 0 ] && [ -d \"\$WORK/images\" ]; then \
      echo \"Detected layout: images/\"; \
      cp -a \"\$WORK/images\"/. \"\$TARGET\"/; copied=1; \
    fi; \
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
fi

echo "Done. Visit Special:ListFiles to verify."
