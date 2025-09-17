#!/usr/bin/env bash
set -euo pipefail

MW_DIR="/var/www/html"
cd "${MW_DIR}"

# Defaults if not provided via environment
: "${MW_SITE_NAME:=MyWiki}"
: "${MW_LANG:=en}"
: "${MW_ADMIN_USER:=Admin}"
: "${MW_ADMIN_PASS:=changeme123!}"
: "${MW_DB_HOST:=db}"
: "${MW_DB_NAME:=wikidb}"
: "${MW_DB_USER:=wiki}"
: "${MW_DB_PASS:=wiki_pass}"
: "${MW_DB_ROOT_PASSWORD:=root_pass}"
: "${MW_SITE_SERVER:=http://localhost:9090}"
: "${MW_ENABLE_SMW:=1}"
: "${MW_MAX_IMAGE_AREA:=100000000}"
: "${MW_SVG_MAX_SIZE:=4096}"
: "${MW_SVG_CONVERTER:=auto}"
: "${MW_MERMAID_THEME:=forest}"
: "${MW_RL_DEBUG:=0}"

# Optional auto-restore on first boot
: "${MW_RESTORE_ON_INIT:=0}"
: "${MW_RESTORE_DB_DUMP:=}"
: "${MW_RESTORE_UPLOADS_ARCHIVE:=}"
: "${MW_FORCE_DB_RESTORE:=0}"
: "${MW_ZIP_ENCODING:=}"

echo "[init] Waiting for database at ${MW_DB_HOST}..."
until mysqladmin ping -h"${MW_DB_HOST}" -u"${MW_DB_USER}" -p"${MW_DB_PASS}" --silent; do
  sleep 2
done
echo "[init] Database is up."

# Helper: detect whether the target database already has core MW tables
db_is_initialized() {
  mysql -h"${MW_DB_HOST}" -u"${MW_DB_USER}" -p"${MW_DB_PASS}" \
    -e "SELECT 1 FROM ${MW_DB_NAME}.page LIMIT 1" >/dev/null 2>&1
}

# Normalize booleans from env
normalize_bool() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) echo 1 ;;
    *) echo 0 ;;
  esac
}

# Perform optional one-time DB and uploads restore from /data paths
do_auto_restore() {
  WANT_RESTORE=$(normalize_bool "$MW_RESTORE_ON_INIT")
  [ "$WANT_RESTORE" = "1" ] || return 0

  # DB restore
  if [ -n "${MW_RESTORE_DB_DUMP}" ] && [ -f "${MW_RESTORE_DB_DUMP}" ]; then
    base=$(basename -- "${MW_RESTORE_DB_DUMP}")
    marker="/data/.restored-db.${base}"
    if [ ! -f "$marker" ]; then
      echo "[restore:init] Preparing to restore DB from ${MW_RESTORE_DB_DUMP}"
      if db_is_initialized; then
        if [ "$(normalize_bool "$MW_FORCE_DB_RESTORE")" = "1" ]; then
          echo "[restore:init] Dropping and recreating database ${MW_DB_NAME} (MW_FORCE_DB_RESTORE=1)"
          mysql -h"${MW_DB_HOST}" -u root -p"${MW_DB_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${MW_DB_NAME}\`; CREATE DATABASE \`${MW_DB_NAME}\` CHARACTER SET binary;"
        else
          echo "[restore:init] Database already has tables; skipping DB import (set MW_FORCE_DB_RESTORE=1 to overwrite)."
          :
        fi
      fi

      if ! db_is_initialized; then
        echo "[restore:init] Importing SQL dump into ${MW_DB_NAME} ... (this may take a while)"
        case "$base" in
          *.sql.gz|*.gz) gzip -dc "${MW_RESTORE_DB_DUMP}" | mysql -h"${MW_DB_HOST}" -u root -p"${MW_DB_ROOT_PASSWORD}" "${MW_DB_NAME}" ;;
          *.sql)        mysql -h"${MW_DB_HOST}" -u root -p"${MW_DB_ROOT_PASSWORD}" "${MW_DB_NAME}" < "${MW_RESTORE_DB_DUMP}" ;;
          *) echo "[restore:init] Unsupported DB dump extension: $base" ;;
        esac
        echo "[restore:init] DB import complete."
      fi

      # Ensure a LocalSettings.php exists to run update.php (use minimal one if none provided)
      if [ ! -f /data/LocalSettings.php ]; then
        echo "[restore:init] Seeding LocalSettings.php from minimal upgrade config"
        if [ -f /data/LocalSettings.upgrade.php ]; then
          cp -f /data/LocalSettings.upgrade.php /data/LocalSettings.php || true
        elif [ -f /opt/mediawiki/LocalSettings.minimal.php ]; then
          cp -f /opt/mediawiki/LocalSettings.minimal.php /data/LocalSettings.php
        else
          cat <<'PHP' > /data/LocalSettings.php
<?php
if ( !defined( 'MEDIAWIKI' ) ) {
    exit;
}

$wgSitename = getenv( 'MW_SITE_NAME' ) ?: 'MyWiki';
$wgMetaNamespace = str_replace( ' ', '_', $wgSitename );
$wgServer = rtrim( getenv( 'MW_SITE_SERVER' ) ?: 'http://localhost:9090', '/' );
$wgScriptPath = '';
$wgResourceBasePath = $wgScriptPath;
$wgArticlePath = '/$1';

$wgEmergencyContact = 'admin@example.com';
$wgPasswordSender = 'admin@example.com';
$wgEnotifUserTalk = false;
$wgEnotifWatchlist = false;
$wgEmailAuthentication = false;

$wgDBtype = 'mysql';
$wgDBserver = getenv( 'MW_DB_HOST' ) ?: 'db';
$wgDBname = getenv( 'MW_DB_NAME' ) ?: 'wikidb';
$wgDBuser = getenv( 'MW_DB_USER' ) ?: 'wiki';
$wgDBpassword = getenv( 'MW_DB_PASS' ) ?: 'wiki_pass';
$wgDBprefix = '';
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=binary';

$wgLanguageCode = getenv( 'MW_LANG' ) ?: 'en';
$wgDefaultSkin = 'vector';
$wgEnableUploads = true;

$wgSecretKey = getenv( 'MW_SECRET_KEY' ) ?: 'change-me-secret-key';
$wgUpgradeKey = getenv( 'MW_UPGRADE_KEY' ) ?: 'change-me-upgrade-key';

$wgMainCacheType = CACHE_NONE;
$wgParserCacheType = CACHE_NONE;
$wgCacheDirectory = false;

wfLoadSkin( 'Vector' );
PHP
        fi
      fi
      if [ -f /data/LocalSettings.php ]; then
        cp -f /data/LocalSettings.php LocalSettings.php
        echo "[restore:init] Running maintenance/update.php after DB import..."
        php maintenance/update.php --quick || true
      fi
      date > "$marker"
    else
      echo "[restore:init] DB already restored earlier (marker present: $(basename "$marker"))"
    fi
  fi

  # Uploads restore
  if [ -n "${MW_RESTORE_UPLOADS_ARCHIVE}" ] && [ -f "${MW_RESTORE_UPLOADS_ARCHIVE}" ]; then
    base=$(basename -- "${MW_RESTORE_UPLOADS_ARCHIVE}")
    marker="/data/.restored-uploads.${base}"
    if [ ! -f "$marker" ]; then
      echo "[restore:init] Restoring uploads from ${MW_RESTORE_UPLOADS_ARCHIVE} ..."
      WORK=$(mktemp -d /tmp/uploads.extract.XXXXXX)
      TARGET="${MW_DIR}/images"
      mkdir -p "$TARGET"
      # Backup existing images dir if non-empty
      if [ "$(ls -A "$TARGET" 2>/dev/null | wc -l)" -gt 0 ]; then
        ts=$(date +%Y%m%d-%H%M%S)
        echo "[restore:init] Backing up existing images to ${TARGET}.bak-${ts}"
        cp -a "$TARGET" "${TARGET}.bak-${ts}"
      fi
      case "$base" in
        *.tar.gz|*.tgz)
          tar -xzf "${MW_RESTORE_UPLOADS_ARCHIVE}" -C "$WORK" ;;
        *.zip)
          if [ -n "$MW_ZIP_ENCODING" ]; then
            echo "[restore:init] Attempting unzip with encoding: $MW_ZIP_ENCODING"
            if unzip -hh 2>/dev/null | grep -q "-I CHARSET"; then
              unzip -q -I "$MW_ZIP_ENCODING" "${MW_RESTORE_UPLOADS_ARCHIVE}" -d "$WORK" || unzip -q -o "${MW_RESTORE_UPLOADS_ARCHIVE}" -d "$WORK"
            else
              echo "[restore:init] Warning: unzip in container lacks -I encoding support; extracting without encoding hint (filenames may break). Prefer tar.gz or run scripts/restore-uploads.sh --zip-encoding on host."
              unzip -q -o "${MW_RESTORE_UPLOADS_ARCHIVE}" -d "$WORK"
            fi
          else
            unzip -q -o "${MW_RESTORE_UPLOADS_ARCHIVE}" -d "$WORK"
          fi ;;
        *) echo "[restore:init] Unsupported uploads archive extension: $base" ;;
      esac
      copied=0
      for d in "$WORK"/mediawiki-*/images; do
        if [ -d "$d" ]; then
          echo "[restore:init] Detected layout: mediawiki-*/images"
          cp -a "$d"/. "$TARGET"/
          copied=1
        fi
      done
      if [ "$copied" -eq 0 ] && [ -d "$WORK/images" ]; then
        echo "[restore:init] Detected layout: images/"
        cp -a "$WORK/images"/. "$TARGET"/
        copied=1
      fi
      if [ "$copied" -eq 0 ]; then
        echo "[restore:init] Detected layout: hashed subdirs at root"
        cp -a "$WORK"/. "$TARGET"/
        copied=1
      fi
      echo "[restore:init] Fixing ownership and permissions"
      chown -R www-data:www-data "$TARGET"
      find "$TARGET" -type d -exec chmod 755 {} +
      find "$TARGET" -type f -exec chmod 644 {} +
      echo "[restore:init] Refreshing image metadata"
      php maintenance/refreshImageMetadata.php --force || true
      php maintenance/rebuildImages.php --missing || true
      rm -rf "$WORK"
      date > "$marker"
      echo "[restore:init] Uploads restore complete"
    else
      echo "[restore:init] Uploads already restored earlier (marker present: $(basename "$marker"))"
    fi
  fi
}

# Run auto-restore before installer logic so we avoid web UI and preserve imports
do_auto_restore

# Ensure MsUpload extension exists (clone if missing)
if [ ! -d "${MW_DIR}/extensions/MsUpload" ]; then
  echo "[init] Fetching MsUpload extension..."
  if ! git clone --depth 1 -b REL1_41 https://github.com/wikimedia/mediawiki-extensions-MsUpload "${MW_DIR}/extensions/MsUpload"; then
    echo "[init] Warning: failed to fetch MsUpload (will proceed without)."
  fi
fi

# If LocalSettings.php exists in /data, ensure a real file exists in webroot (avoid symlink issues)
if [ -f /data/LocalSettings.php ]; then
  if [ -L LocalSettings.php ]; then
    rm -f LocalSettings.php
  fi
  if [ ! -f LocalSettings.php ]; then
    echo "[init] Copying existing /data/LocalSettings.php into webroot..."
    cp -f /data/LocalSettings.php LocalSettings.php
  fi
fi

# If LocalSettings.php exists but DB is empty (fresh DB), run the installer to create schema
if [ -f LocalSettings.php ] && ! db_is_initialized; then
  echo "[init] Detected LocalSettings.php but database lacks core tables; running installer to initialize schema..."
  # Backup any existing LocalSettings.php (both locations)
  [ -f LocalSettings.php ] && mv LocalSettings.php LocalSettings.php.preinstall || true
  [ -f /data/LocalSettings.php ] && mv /data/LocalSettings.php /data/LocalSettings.php.preinstall || true

  php maintenance/install.php \
    --dbtype mysql \
    --dbserver "${MW_DB_HOST}" \
    --dbname "${MW_DB_NAME}" \
    --dbuser "${MW_DB_USER}" \
    --dbpass "${MW_DB_PASS}" \
    --server "${MW_SITE_SERVER%/}" \
    --scriptpath "" \
    --lang "${MW_LANG}" \
    --pass "${MW_ADMIN_PASS}" \
    "${MW_SITE_NAME}" "${MW_ADMIN_USER}"

  echo "[init] Installer finished (DB init). Persisting LocalSettings.php to /data and syncing webroot..."
  mkdir -p /data
  if [ -f LocalSettings.php ]; then
    cp -f LocalSettings.php /data/LocalSettings.php
    cp -f /data/LocalSettings.php LocalSettings.php
  fi
  echo "[init] Running maintenance/update.php after DB initialization..."
  php maintenance/update.php --quick || true
fi

if [ ! -f LocalSettings.php ]; then
  echo "[init] Running MediaWiki installer..."
  # Non-interactive install
  php maintenance/install.php \
    --dbtype mysql \
    --dbserver "${MW_DB_HOST}" \
    --dbname "${MW_DB_NAME}" \
    --dbuser "${MW_DB_USER}" \
    --dbpass "${MW_DB_PASS}" \
    --server "${MW_SITE_SERVER%/}" \
    --scriptpath "" \
    --lang "${MW_LANG}" \
    --pass "${MW_ADMIN_PASS}" \
    "${MW_SITE_NAME}" "${MW_ADMIN_USER}"

  echo "[init] Installer finished. Persisting LocalSettings.php to /data and appending extension config..."
  mkdir -p /data
  # Persist LocalSettings to /data and keep a real copy in webroot (no symlink)
  if [ -f LocalSettings.php ]; then
    cp -f LocalSettings.php /data/LocalSettings.php
    cp -f /data/LocalSettings.php LocalSettings.php
  fi

  # Try to install Semantic MediaWiki via Composer before enabling it
  SMW_OK=0
  echo "[init] Installing Semantic MediaWiki via Composer..."
  if [ -w composer.json ] && composer --no-interaction --no-progress require "mediawiki/semantic-media-wiki:~4.1"; then
    SMW_OK=1
    echo "[init] Semantic MediaWiki installed."
  else
    echo "[init] Warning: Semantic MediaWiki install failed; proceeding without enabling SMW."
  fi

  # Append our extension and upload configuration if not already present
  if ! grep -q "# BEGIN: custom extensions" /data/LocalSettings.php; then
    cat >> /data/LocalSettings.php <<'PHP'

# BEGIN: custom extensions
wfLoadExtension( 'WikiEditor' );
wfLoadExtension( 'CodeEditor' );
wfLoadExtension( 'PdfHandler' );
wfLoadExtension( 'MultimediaViewer' );
wfLoadExtension( 'MsUpload' );
wfLoadExtension( 'VisualEditor' );
wfLoadExtension( 'TimedMediaHandler' );
wfLoadExtension( 'SyntaxHighlight_GeSHi' );
wfLoadExtension( 'WikiMarkdown' );

$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = '/usr/bin/convert';
$wgFileExtensions[] = 'pdf';

# VisualEditor defaults
$wgDefaultUserOptions['visualeditor-enable'] = 1;
$wgDefaultUserOptions['visualeditor-editor'] = 'visualeditor';

# MsUpload: allow registered users to upload
$wgGroupPermissions['user']['upload'] = true;

# TimedMediaHandler config (basic playback, no transcode by default)
$wgFFmpegLocation = '/usr/bin/ffmpeg';
$wgTmhEnableTranscode = false;
$wgTmhEnableMp4Uploads = true;
# Ensure getID3 library is available for media metadata
if ( file_exists( __DIR__ . '/vendor/getid3/getid3/getid3.php' ) ) {
    require_once __DIR__ . '/vendor/getid3/getid3/getid3.php';
}
# END: custom extensions
PHP
  fi

  # If SMW was installed, enable it now (after the heredoc to safely toggle)
  if [ "$SMW_OK" = "1" ]; then
    echo "wfLoadExtension( 'SemanticMediaWiki' );" >> /data/LocalSettings.php
    echo "\$smwgNamespace = parse_url( \$wgServer, PHP_URL_HOST );" >> /data/LocalSettings.php
  fi

  echo "[init] Running maintenance/update.php (including SMW tables)..."
  php maintenance/update.php --quick
fi

# Ensure custom extension config block exists even if using a pre-existing LocalSettings.php
if [ -f /data/LocalSettings.php ] && ! grep -q "# BEGIN: custom extensions" /data/LocalSettings.php; then
  echo "[init] Appending custom extension configuration to LocalSettings.php..."
  cat >> /data/LocalSettings.php <<'PHP'

# BEGIN: custom extensions
wfLoadExtension( 'WikiEditor' );
wfLoadExtension( 'CodeEditor' );
wfLoadExtension( 'PdfHandler' );
wfLoadExtension( 'MultimediaViewer' );
wfLoadExtension( 'MsUpload' );
wfLoadExtension( 'VisualEditor' );
wfLoadExtension( 'TimedMediaHandler' );
wfLoadExtension( 'SyntaxHighlight_GeSHi' );
wfLoadExtension( 'WikiMarkdown' );

$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = '/usr/bin/convert';
$wgFileExtensions[] = 'pdf';
$wgFileExtensions[] = 'mp4';
$wgFileExtensions[] = 'avi';
$wgFileExtensions[] = 'mkv';

# Allow larger uploads to match PHP limits
$wgMaxUploadSize = 1024 * 1024 * 1024; // 1 GiB

# VisualEditor defaults
$wgDefaultUserOptions['visualeditor-enable'] = 1;
$wgDefaultUserOptions['visualeditor-editor'] = 'visualeditor';

# MsUpload: allow registered users to upload
$wgGroupPermissions['user']['upload'] = true;
# TimedMediaHandler config (basic playback, no transcode by default)
$wgFFmpegLocation = '/usr/bin/ffmpeg';
$wgTmhEnableTranscode = false;
$wgTmhEnableMp4Uploads = true;
# Ensure getID3 library is available for media metadata
if ( file_exists( __DIR__ . '/vendor/getid3/getid3/getid3.php' ) ) {
    require_once __DIR__ . '/vendor/getid3/getid3/getid3.php';
}
# END: custom extensions
PHP
  # Keep webroot in sync
  cp -f /data/LocalSettings.php LocalSettings.php
  php maintenance/update.php --quick || true
fi

# Ensure SMW installed/enabled per env toggle (runs on every start)
WANT_SMW=$(normalize_bool "$MW_ENABLE_SMW")
if [ -f /data/LocalSettings.php ]; then
  if [ "$WANT_SMW" = "1" ]; then
    # Install SMW code if missing
    if [ ! -f "${MW_DIR}/extensions/SemanticMediaWiki/extension.json" ]; then
      echo "[init] Installing Semantic MediaWiki via Composer (env enabled)..."
      if ! { [ -w composer.json ] && composer --no-interaction --no-progress require "mediawiki/semantic-media-wiki:~4.1"; }; then
        echo "[init] Warning: Failed to install SemanticMediaWiki; startup will continue without SMW."
      fi
    fi
    # Append LocalSettings lines if not present
    if ! grep -q "SemanticMediaWiki" /data/LocalSettings.php && [ -f "${MW_DIR}/extensions/SemanticMediaWiki/extension.json" ]; then
      echo "wfLoadExtension( 'SemanticMediaWiki' );" >> /data/LocalSettings.php
      echo "\$smwgNamespace = parse_url( \$wgServer, PHP_URL_HOST );" >> /data/LocalSettings.php
      echo "[init] Enabled SemanticMediaWiki in LocalSettings.php"
      cp -f /data/LocalSettings.php LocalSettings.php
      php maintenance/update.php --quick || true
    fi
    # Normalize legacy enableSemantics() to direct smwgNamespace assignment
    if grep -q "enableSemantics" /data/LocalSettings.php; then
      echo "[init] Normalizing enableSemantics() to $smwgNamespace assignment"
      sed -i -E "s/enableSemantics\(.*\);/\$smwgNamespace = parse_url( \$wgServer, PHP_URL_HOST );/" /data/LocalSettings.php || true
      cp -f /data/LocalSettings.php LocalSettings.php
    fi
  else
    # If disabled by env but enabled in config and code missing, comment out to avoid fatals
    if grep -q "SemanticMediaWiki" /data/LocalSettings.php && [ ! -f "${MW_DIR}/extensions/SemanticMediaWiki/extension.json" ]; then
      echo "[init] MW_ENABLE_SMW is disabled and SMW code missing; commenting out SMW lines."
      sed -i -E "s/^(\s*)wfLoadExtension\( '\''SemanticMediaWiki'\'' \);/# \0/" /data/LocalSettings.php || true
      sed -i -E "s/^(\s*)enableSemantics\(.*\);/# \0/" /data/LocalSettings.php || true
    fi
  fi
fi

# Ensure mp4 is allowed and upload size is set even if the custom block already existed
if [ -f /data/LocalSettings.php ]; then
  if ! grep -q "\$wgFileExtensions\[\]\s*=\s*'mp4'" /data/LocalSettings.php; then
    echo "[init] Enabling mp4 uploads in LocalSettings.php"
    echo "\$wgFileExtensions[] = 'mp4';" >> /data/LocalSettings.php
  fi
  if ! grep -q "\$wgFileExtensions\[\]\s*=\s*'avi'" /data/LocalSettings.php; then
    echo "[init] Enabling avi uploads in LocalSettings.php"
    echo "\$wgFileExtensions[] = 'avi';" >> /data/LocalSettings.php
  fi
  if ! grep -q "\$wgFileExtensions\[\]\s*=\s*'mkv'" /data/LocalSettings.php; then
    echo "[init] Enabling mkv uploads in LocalSettings.php"
    echo "\$wgFileExtensions[] = 'mkv';" >> /data/LocalSettings.php
  fi
  # Ensure TimedMediaHandler is enabled and ffmpeg configured
  if ! grep -q "TimedMediaHandler" /data/LocalSettings.php; then
    echo "[init] Enabling TimedMediaHandler in LocalSettings.php"
    echo "wfLoadExtension( 'TimedMediaHandler' );" >> /data/LocalSettings.php
  fi
  # Ensure Parsoid REST API (for VisualEditor) is enabled via vendor path
  if grep -q "wfLoadExtension( 'Parsoid' );" /data/LocalSettings.php; then
    echo "[init] Normalizing Parsoid load to vendor path"
    sed -i "s#wfLoadExtension( 'Parsoid' );#wfLoadExtension( 'Parsoid', \"\$IP/vendor/wikimedia/parsoid/extension.json\" );#" /data/LocalSettings.php
  fi
  if ! grep -q "vendor/wikimedia/parsoid/extension.json" /data/LocalSettings.php; then
    echo "[init] Enabling Parsoid extension (REST API) via vendor path"
    echo "wfLoadExtension( 'Parsoid', \"\$IP/vendor/wikimedia/parsoid/extension.json\" );" >> /data/LocalSettings.php
  fi
  # Ensure canonical server is set (keeps REST domain consistent)
  if ! grep -q "^\$wgCanonicalServer\b" /data/LocalSettings.php; then
    echo "\$wgCanonicalServer = \$wgServer;" >> /data/LocalSettings.php
  fi
  # Ensure Mermaid is enabled
  if ! grep -q "wfLoadExtension( 'Mermaid' );" /data/LocalSettings.php; then
    echo "[init] Enabling Mermaid extension"
    echo "wfLoadExtension( 'Mermaid' );" >> /data/LocalSettings.php
  fi
  # Configure Mermaid theme (Mermaid extension uses $mermaidgDefaultTheme)
  if grep -q '^[[:space:]]*\$mermaidgDefaultTheme[[:space:]]*=' /data/LocalSettings.php; then
    sed -i -E 's/^[[:space:]]*\$mermaidgDefaultTheme[[:space:]]*=.*/$mermaidgDefaultTheme = '\''"${MW_MERMAID_THEME}"'\'';/' /data/LocalSettings.php
  else
    echo "\$mermaidgDefaultTheme = '${MW_MERMAID_THEME}';" >> /data/LocalSettings.php
  fi
  # Ensure WikiMarkdown is enabled
  if ! grep -q "WikiMarkdown" /data/LocalSettings.php; then
    echo "[init] Enabling WikiMarkdown in LocalSettings.php"
    # Ensure WikiMarkdown composer autoload is required before loading the extension
    if ! grep -q "extensions/WikiMarkdown/vendor/autoload.php" /data/LocalSettings.php; then
      echo "require_once __DIR__ . '/extensions/WikiMarkdown/vendor/autoload.php';" >> /data/LocalSettings.php
    fi
    echo "wfLoadExtension( 'WikiMarkdown' );" >> /data/LocalSettings.php
  fi

  # If WikiMarkdown is already enabled but autoload is missing, insert it just before the load line
  if grep -q "wfLoadExtension( 'WikiMarkdown' );" /data/LocalSettings.php \
     && ! grep -q "extensions/WikiMarkdown/vendor/autoload.php" /data/LocalSettings.php; then
    echo "[init] Inserting WikiMarkdown composer autoload before extension load"
    sed -i "/wfLoadExtension( 'WikiMarkdown' );/i require_once __DIR__ . '\/extensions\/WikiMarkdown\/vendor\/autoload.php';" /data/LocalSettings.php
  fi
  # Ensure SyntaxHighlight is enabled (use correct key matching directory)
  if grep -q "wfLoadExtension( 'SyntaxHighlight' )" /data/LocalSettings.php && ! grep -q "SyntaxHighlight_GeSHi" /data/LocalSettings.php; then
    echo "[init] Normalizing SyntaxHighlight load key to SyntaxHighlight_GeSHi"
    sed -i "s/wfLoadExtension( 'SyntaxHighlight' );/wfLoadExtension( 'SyntaxHighlight_GeSHi' );/" /data/LocalSettings.php
  fi
  if ! grep -q "SyntaxHighlight_GeSHi" /data/LocalSettings.php; then
    echo "[init] Enabling SyntaxHighlight in LocalSettings.php"
    echo "wfLoadExtension( 'SyntaxHighlight_GeSHi' );" >> /data/LocalSettings.php
  fi
  if ! grep -q "\$wgFFmpegLocation" /data/LocalSettings.php; then
    echo "[init] Setting ffmpeg path for TMH"
    echo "\$wgFFmpegLocation = '/usr/bin/ffmpeg';" >> /data/LocalSettings.php
  fi
  if ! grep -q "\$wgTmhEnableTranscode" /data/LocalSettings.php; then
    echo "[init] Disabling TMH transcode by default"
    echo "\$wgTmhEnableTranscode = false;" >> /data/LocalSettings.php
  fi
  # Ensure getID3 is required for TMH metadata parsing (normalize path)
  # Replace any legacy deep path first, then ensure the normalized one exists
  if grep -q "vendor/getid3/getid3/getid3/getid3.php" /data/LocalSettings.php; then
    echo "[init] Normalizing getID3 require path in LocalSettings.php"
    sed -i "s#vendor/getid3/getid3/getid3/getid3.php#vendor/getid3/getid3/getid3.php#g" /data/LocalSettings.php
  fi
  if ! grep -q "vendor/getid3/getid3/getid3.php" /data/LocalSettings.php; then
    echo "[init] Requiring getID3 library in LocalSettings.php"
    echo "require_once __DIR__ . '/vendor/getid3/getid3/getid3.php';" >> /data/LocalSettings.php
  fi
  if grep -q '^[[:space:]]*\$wgMaxUploadSize[[:space:]]*=' /data/LocalSettings.php; then
    echo "[init] Updating MediaWiki max upload size to 1GiB"
    sed -i -E 's/^[[:space:]]*\$wgMaxUploadSize[[:space:]]*=.*/$wgMaxUploadSize = 1024 * 1024 * 1024;/' /data/LocalSettings.php
  else
    echo "[init] Setting MediaWiki max upload size to 1GiB"
    echo "\$wgMaxUploadSize = 1024 * 1024 * 1024;" >> /data/LocalSettings.php
  fi
  # Ensure larger thumbnails for big images: set $wgMaxImageArea (default 100 MP)
  if grep -q '^[[:space:]]*\$wgMaxImageArea[[:space:]]*=' /data/LocalSettings.php; then
    echo "[init] Setting wgMaxImageArea to ${MW_MAX_IMAGE_AREA}"
    sed -i -E 's/^[[:space:]]*\$wgMaxImageArea[[:space:]]*=.*/$wgMaxImageArea = '"${MW_MAX_IMAGE_AREA}"';/' /data/LocalSettings.php
  else
    echo "[init] Adding wgMaxImageArea = ${MW_MAX_IMAGE_AREA}"
    echo "\$wgMaxImageArea = ${MW_MAX_IMAGE_AREA};" >> /data/LocalSettings.php
  fi
  # Allow SVG uploads
  if ! grep -q '\\$wgFileExtensions\\[\\].*svg' /data/LocalSettings.php; then
    echo "[init] Enabling SVG uploads"
    echo "\$wgFileExtensions[] = 'svg';" >> /data/LocalSettings.php
  fi
  # Configure SVG rendering size and converter
  if grep -q '^[[:space:]]*\$wgSVGMaxSize[[:space:]]*=' /data/LocalSettings.php; then
    sed -i -E 's/^[[:space:]]*\$wgSVGMaxSize[[:space:]]*=.*/$wgSVGMaxSize = '"${MW_SVG_MAX_SIZE}"';/' /data/LocalSettings.php
  else
    echo "\$wgSVGMaxSize = ${MW_SVG_MAX_SIZE};" >> /data/LocalSettings.php
  fi
  # Decide on converter: prefer rsvg when available or when requested
  WANT_CONVERTER="${MW_SVG_CONVERTER}"
  if [ "$WANT_CONVERTER" = "auto" ] && command -v rsvg-convert >/dev/null 2>&1; then
    WANT_CONVERTER="rsvg"
  fi
  if [ "$WANT_CONVERTER" = "rsvg" ] || [ "$WANT_CONVERTER" = "ImageMagick" ] || [ "$WANT_CONVERTER" = "inkscape" ]; then
    # Remove any existing wgSVGConverter lines and append desired value
    sed -i -E '/^[[:space:]]*\$wgSVGConverter[[:space:]]*=/d' /data/LocalSettings.php
    echo "\$wgSVGConverter = '${WANT_CONVERTER}';" >> /data/LocalSettings.php
  fi
  cp -f /data/LocalSettings.php LocalSettings.php
fi

# Final enforcement for TMH MP4 uploads flag
if [ -f /data/LocalSettings.php ] && ! grep -q "\$wgTmhEnableMp4Uploads" /data/LocalSettings.php; then
  echo "[init] Allowing MP4 uploads via TMH (final enforcement)"
  echo "\$wgTmhEnableMp4Uploads = true;" >> /data/LocalSettings.php
  cp -f /data/LocalSettings.php LocalSettings.php
fi

# Add Chinese aliases for File namespace so [[檔案:...]] / [[文件:...]] links work
if [ -f /data/LocalSettings.php ] && ! grep -q "\$wgNamespaceAliases\['檔案'\]" /data/LocalSettings.php; then
  echo "[init] Adding Chinese aliases for File namespace (檔案/文件)"
  cat >> /data/LocalSettings.php <<'PHP'
$wgNamespaceAliases['檔案'] = NS_FILE;        // zh-hant
$wgNamespaceAliases['文件'] = NS_FILE;        // zh-hans
$wgNamespaceAliases['檔案討論'] = NS_FILE_TALK;
$wgNamespaceAliases['文件討論'] = NS_FILE_TALK;
PHP
  cp -f /data/LocalSettings.php LocalSettings.php
fi

# Optional: Enable ResourceLoader debug (disables JS minification)
if [ "${MW_RL_DEBUG}" = "1" ] && [ -f /data/LocalSettings.php ] && ! grep -q "^\$wgResourceLoaderDebug\b" /data/LocalSettings.php; then
  echo "[init] Enabling ResourceLoader debug mode"
  echo "\$wgResourceLoaderDebug = true;" >> /data/LocalSettings.php
  cp -f /data/LocalSettings.php LocalSettings.php
fi

echo "[init] Starting Apache..."
exec apache2-foreground
