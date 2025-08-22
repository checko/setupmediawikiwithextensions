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
  # Move generated LocalSettings to /data for persistence and symlink back
  if [ -f LocalSettings.php ]; then
    mv LocalSettings.php /data/LocalSettings.php
    ln -s /data/LocalSettings.php LocalSettings.php
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

echo "[init] Starting Apache..."
exec apache2-foreground
