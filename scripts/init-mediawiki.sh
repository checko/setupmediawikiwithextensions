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

echo "[init] Waiting for database at ${MW_DB_HOST}..."
until mysqladmin ping -h"${MW_DB_HOST}" -u"${MW_DB_USER}" -p"${MW_DB_PASS}" --silent; do
  sleep 2
done
echo "[init] Database is up."

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
  if composer --no-interaction --no-progress require "mediawiki/semantic-media-wiki:~4.1"; then
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

$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = '/usr/bin/convert';
$wgFileExtensions[] = 'pdf';

# VisualEditor defaults
$wgDefaultUserOptions['visualeditor-enable'] = 1;
$wgDefaultUserOptions['visualeditor-editor'] = 'visualeditor';

# MsUpload: allow registered users to upload
$wgGroupPermissions['user']['upload'] = true;
# END: custom extensions
PHP
  fi

  # If SMW was installed, enable it now (after the heredoc to safely toggle)
  if [ "$SMW_OK" = "1" ]; then
    echo "wfLoadExtension( 'SemanticMediaWiki' );" >> /data/LocalSettings.php
    echo "enableSemantics( parse_url( \$wgServer, PHP_URL_HOST ) );" >> /data/LocalSettings.php
  fi

  echo "[init] Running maintenance/update.php (including SMW tables)..."
  php maintenance/update.php --quick
fi

# Ensure SMW installed/enabled per env toggle (runs on every start)
normalize_bool() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|on|ON) echo 1 ;;
    *) echo 0 ;;
  esac
}

WANT_SMW=$(normalize_bool "$MW_ENABLE_SMW")
if [ -f /data/LocalSettings.php ]; then
  if [ "$WANT_SMW" = "1" ]; then
    # Install SMW code if missing
    if [ ! -f "${MW_DIR}/extensions/SemanticMediaWiki/extension.json" ]; then
      echo "[init] Installing Semantic MediaWiki via Composer (env enabled)..."
      if ! composer --no-interaction --no-progress require "mediawiki/semantic-media-wiki:~4.1"; then
        echo "[init] Warning: Failed to install SemanticMediaWiki; startup will continue without SMW."
      fi
    fi
    # Append LocalSettings lines if not present
    if ! grep -q "SemanticMediaWiki" /data/LocalSettings.php && [ -f "${MW_DIR}/extensions/SemanticMediaWiki/extension.json" ]; then
      echo "wfLoadExtension( 'SemanticMediaWiki' );" >> /data/LocalSettings.php
      echo "enableSemantics( parse_url( \$wgServer, PHP_URL_HOST ) );" >> /data/LocalSettings.php
      echo "[init] Enabled SemanticMediaWiki in LocalSettings.php"
      php maintenance/update.php --quick || true
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

echo "[init] Starting Apache..."
exec apache2-foreground
