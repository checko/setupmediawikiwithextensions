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
    echo "enableSemantics( parse_url( \$wgServer, PHP_URL_HOST ) );" >> /data/LocalSettings.php
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
      cp -f /data/LocalSettings.php LocalSettings.php
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

# Optional: Enable ResourceLoader debug (disables JS minification)
if [ "${MW_RL_DEBUG}" = "1" ] && [ -f /data/LocalSettings.php ] && ! grep -q "^\$wgResourceLoaderDebug\b" /data/LocalSettings.php; then
  echo "[init] Enabling ResourceLoader debug mode"
  echo "\$wgResourceLoaderDebug = true;" >> /data/LocalSettings.php
  cp -f /data/LocalSettings.php LocalSettings.php
fi

echo "[init] Starting Apache..."
exec apache2-foreground
