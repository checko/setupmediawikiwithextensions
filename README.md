# MediaWiki Test Stack (Docker)

A quick-start MediaWiki stack using Docker Compose, pre-wired with commonly used extensions:

- MsUpload
- WikiEditor
- MultimediaViewer
- PdfHandler
- SemanticMediaWiki (SMW) — baked into the image at build time
- VisualEditor (uses built-in Parsoid in MW 1.41)
- CodeEditor

Port is mapped to `9090` on the host.

## Prerequisites
- Docker and Docker Compose (Docker Desktop or docker engine + compose plugin)

## Quick Start
1. Copy env file and adjust values as needed:
   - `cp .env.example .env`
   - Set `MW_ADMIN_PASS`, `MW_SITE_SERVER` if not `http://localhost:9090`.
2. Build and start:
   - `docker compose up -d --build`
3. Visit your wiki:
   - `http://localhost:9090`
4. Log in with the admin account:
   - User: `Admin`
   - Password: as set in `.env` (default `changeme123!` — change it!)

On first run, the container auto-installs MediaWiki even if a prior `LocalSettings.php` exists but the DB is empty, persists `LocalSettings.php` to `./data/LocalSettings.php`, and enables the extensions. SMW is bundled in the image and enabled; if SMW shows a “missing upgrade key” page, run the SMW setup step under Maintenance below.

## Restore existing wiki (DB + uploads) automatically

Place your dump/archive files in `./data` and enable one-time restore on init via `.env`.

- Supported DB dump formats: `.sql`, `.sql.gz`
- Supported uploads archives: `.zip`, `.tar.gz`, `.tgz`

1) Copy and edit `.env`:
   ```bash
   cp .env.example .env
   # set these values in .env
   MW_RESTORE_ON_INIT=1
   MW_RESTORE_DB_DUMP=/data/wikidb.sql          # or /data/wikidb.sql.gz
   MW_RESTORE_UPLOADS_ARCHIVE=/data/images.zip  # optional
   # If DB already has tables and you want to overwrite them, also set:
   MW_FORCE_DB_RESTORE=1
   ```

2) Put your files in `./data`:
   - `./data/wikidb.sql` (or `.sql.gz`)
   - `./data/images.zip` (or `.tar.gz`/`.tgz`)

3) Start or restart the stack:
   ```bash
   docker compose up -d --build
   ```

What happens on first start (with `MW_RESTORE_ON_INIT=1`):
- Database restore runs first. If the DB is empty, the dump is imported. If the DB has tables and `MW_FORCE_DB_RESTORE=1`, it will drop/recreate the database before importing.
- A minimal `LocalSettings.php` (seeded from `templates/LocalSettings.minimal.php` inside the image) is copied into place when needed so there is no interactive setup page.
- `maintenance/update.php` runs to align the schema with this container’s MediaWiki. If the imported database predates MediaWiki 1.35, the container automatically runs the bundled MediaWiki 1.35 updater first, then re-runs the 1.41 updater.
- Uploads archive is extracted into `/var/www/html/images`, permissions are fixed, and image metadata is refreshed.
- If the uploads archive is a ZIP and uses a non‑UTF‑8 code page, set `MW_ZIP_ENCODING` (for example `cp950` or `gbk`). The init script automatically re-encodes any `#Uxxxx`-style filenames so Chinese/Unicode names render correctly.
- Marker files under `/data` prevent repeated restores on later restarts.

You can also run the restore scripts manually later:
```bash
# Restore uploads into the running container
bash scripts/restore-uploads.sh images.zip                    # default
bash scripts/restore-uploads.sh images.zip --zip-encoding cp950  # preserve Traditional Chinese names
bash scripts/restore-uploads.sh images.zip --zip-encoding gbk    # preserve Simplified Chinese names

# Restore DB into the running container (stops web first)
bash scripts/restore-db.sh wikidb.sql
```

## Localization quirks: Chinese File aliases

This stack adds namespace aliases so that pages using Chinese file prefixes render correctly:
- `[[檔案:…]]`, `[[文件:…]]` → `File:` namespace

If you have other localized prefixes (e.g., categories), we can add similar aliases.

## Export from another server
See docs/EXPORT-SOURCE.md for step‑by‑step commands to dump the DB and archive the `images/` folder from a source server (bare‑metal or Docker), transfer them, and restore here.

### ZIP filename encodings
- ZIP archives don’t always store filenames as UTF‑8. If your source ZIP was made on Windows or old tools, pass `--zip-encoding` when using `scripts/restore-uploads.sh` (e.g., `cp950` or `gbk`).
- For automated restore at startup, set `MW_ZIP_ENCODING=cp950` (or `gbk`) in `.env`.
- Prefer `tar.gz` for future transfers to avoid encoding issues entirely.

## What’s in the stack
- `mediawiki` service: custom image based on `mediawiki:1.41`, plus system tools for PdfHandler and Composer. Extensions are cloned/installed during image build.
  - Includes `librsvg2-bin` for high‑quality SVG rasterization via `rsvg-convert`.
  - Includes Semantic MediaWiki installed at build time (`extensions/SemanticMediaWiki`).
  - Bundled skins (`Vector`, `MinervaNeue`, `MonoBook`, `Timeless` — including the Vector 2022 variant) are enabled automatically after the schema is brought up to 1.35+; keep the minimal restore stub at the default so the legacy upgrader can run.
- `db` service: `mariadb:10.6` with persistent volume.
- Volumes:
  - Database data in a named volume (`db_data`).
  - Media uploads in a named volume (`wiki_images`).
  - `LocalSettings.php` persisted to `./data` on the host.

## Configuration
- Main settings are in `.env`:
  - `MW_SITE_NAME`, `MW_LANG`
  - `MW_ADMIN_USER`, `MW_ADMIN_PASS`
  - `MW_DB_*` (db name/user/pass)
  - `MW_SITE_SERVER` (e.g., `http://localhost:9090`)
  - `MW_MAX_IMAGE_AREA` (max pixels for thumbnailing; raise to avoid "greater than 12.5 MP" errors)
  - `MW_SVG_MAX_SIZE` (max raster size for SVG thumbnails; default 4096)
- `MW_SVG_CONVERTER` (auto | rsvg | ImageMagick | inkscape; default auto)
- `MW_RL_DEBUG` (0/1) enable ResourceLoader debug to skip JS minification (for troubleshooting)
- To change port, edit `docker-compose.yml` port mapping.

### Important: Do not edit `./data/*` directly
- The file `./data/LocalSettings.php` is persisted output and managed by the init script.
- Make configuration changes in `scripts/init-mediawiki.sh` (source of truth) and/or `.env`, then rebuild/recreate:
  - `docker compose up -d --build --force-recreate`
- The init script will enforce config (extensions, upload types/sizes, TMH, etc.) and sync the webroot copy of `LocalSettings.php`. It will also initialize the database schema on first boot even if `LocalSettings.php` already exists but the DB is still empty.
- Rationale: editing `./data/LocalSettings.php` manually can be overwritten or drift from the intended, versioned configuration.

## Installed Extensions
- MsUpload, WikiEditor, MultimediaViewer, PdfHandler, VisualEditor, CodeEditor
- SyntaxHighlight (with Pygments for code blocks)
- SemanticMediaWiki (installed at image build via Composer create-project; enabled by default)
- WikiMarkdown (adds `<markdown>...</markdown>` tag and Markdown content model)
- Mermaid (parser function `#mermaid` for flowcharts/diagrams)

### Markdown Usage
- Inline/block tag: wrap content in `<markdown>...</markdown>` on any page.
- Content model: pages with `.md` suffix are treated as Markdown.
- Parsedown/Extra/Extended dependencies are bundled in the image; no extra steps needed.

### Mermaid Usage
- Basic: `{{#mermaid:graph TD; A-->B; B-->C;}}`
- Theme via `.env`: `MW_MERMAID_THEME` (forest/default/neutral/dark)
- v10 diagrams supported (timeline, mindmap, sankey, xychart). The image bundles Mermaid v10.9.1 locally and uses an initializer that avoids RL minification issues.
- Mindmap/timeline tips:
  - Start Mermaid blocks at column 1 (no list bullets or extra indentation).
  - For mindmap, include a single `mindmap` header line, then exactly one root node indented beneath it, then children indented further. Use spaces, not tabs.
  - Example mindmap:
    
    `{{#mermaid:
    mindmap
      Roadmap((Roadmap))
        Backend
          API v1
          DB Migrations
        Frontend
          Components
          Theming
        Ops
          Monitoring
          Backups
    }}`
  - Example timeline:
    
    `{{#mermaid:
    timeline
      title Product Timeline
      2025-08-01 : Kickoff
      2025-08-07 : API Draft
      2025-08-15 : Frontend Alpha
      2025-08-22 : Beta
      2025-09-01 : Release
    }}`

## Maintenance
- Run MediaWiki update (schema changes, extension updates):
  - `docker compose exec mediawiki php maintenance/update.php --quick`
- Initialize or repair Semantic MediaWiki store/tables:
  - `docker compose exec mediawiki php extensions/SemanticMediaWiki/maintenance/setupStore.php --skip-import`
- Rebuild SMW data (optional):
  - `docker compose exec mediawiki php extensions/SemanticMediaWiki/maintenance/rebuildData.php -d 50`
- View logs:
  - `docker compose logs -f mediawiki`
- Stop:
  - `docker compose down`
- Full reset (dev only – removes volumes):
  - `docker compose down -v`
  - To also remove images for a clean rebuild: `docker compose down -v --rmi all --remove-orphans && docker compose build --no-cache && docker compose up -d`

### Restore Database
- Scripted restore (stops web, backs up current DB, imports dump, runs update):
  - `bash scripts/restore-db.sh ./wikidb.sql`
  - Supports `.sql` and `.sql.gz`. Adjust path to your dump file.
- Manual restore (no script):
  - Stop web to avoid writes: `docker compose stop mediawiki`
  - Optional backup: `docker compose exec -T db sh -lc "mysqldump -u root -p'$MW_DB_ROOT_PASSWORD' '$MW_DB_NAME'" > data/backup-$(date +%Y%m%d-%H%M%S).sql`
  - Import: `docker compose exec -T db sh -lc "mysql -u root -p'$MW_DB_ROOT_PASSWORD' '$MW_DB_NAME'" < ./wikidb.sql`
  - Run MW updates: `docker compose exec mediawiki php maintenance/update.php --quick`
  - Start web: `docker compose start mediawiki`
- If your dump contains `CREATE DATABASE`/`USE` statements for a different DB name, strip or replace them so the import targets `$MW_DB_NAME` (default `wikidb`).
- Restoring uploads: DB restore does not include files. To restore images, copy the prior wiki’s `images/` directory into the `wiki_images` volume (e.g., `docker compose cp /path/to/images/. mediawiki:/var/www/html/images/`).
- Older-than-1.35 dumps: see `docs/RESTORE-DB.md` for the 1.35 intermediate upgrade step and a fix for a common SMW actor conflict.

## Troubleshooting
- Blank/failed VE edits: ensure `MW_SITE_SERVER` matches how you access the wiki (scheme/host/port).
- PDF thumbnails/text extract missing: ensure ImageMagick, Ghostscript, Poppler are installed (baked into image). For very large PDFs, resource limits may apply.
- DB not ready on first start: the web container waits for DB; if stuck, check `docker compose logs db`.
- "File with dimensions greater than 12.5 MP": increase `MW_MAX_IMAGE_AREA` in `.env` (e.g., `100000000` for 100 MP). Larger values consume more CPU/RAM during thumb generation.
- SVG quality/performance: prefers `rsvg` when available. Verify at Special:Version → Image manipulation. Increase `MW_SVG_MAX_SIZE` if thumbs are too small.
- Mermaid not rendering / double render:
  - Ensure blocks aren’t nested inside list items (leading `-`). This changes indentation and breaks mindmap parsing.
  - Hard refresh to clear cached modules. The initializer prevents double renders and loads Mermaid locally from `/extensions/Mermaid/resources/mermaid.min.js`.
  - See `docs/DEBUG-LOGGING.md` for the mermaid debugging log and fixes applied.
- Semantic MediaWiki:
  - If Special:Version or Special:SMWAdmin shows an “upgrade key” or setup message, run:
    - `docker compose exec mediawiki php extensions/SemanticMediaWiki/maintenance/setupStore.php`
    - then `docker compose exec mediawiki php maintenance/update.php --quick`
  - The init script uses `$smwgNamespace = parse_url( $wgServer, PHP_URL_HOST );` (no `enableSemantics()` call needed).

### International namespace aliases (Chinese “檔案/文件”)
- If pages from an older Chinese wiki contain image links like `[[檔案:xxx.jpg]]` (Traditional) or `[[文件:xxx.jpg]]` (Simplified) but your new site language is English, those links may not resolve by default.
- The init script now adds namespace aliases so both `檔案` and `文件` map to `NS_FILE`, and their talk pages to `NS_FILE_TALK`. No page edits are required.
- To customize or add more aliases, edit `scripts/init-mediawiki.sh` and append to `$wgNamespaceAliases` in the block labeled “Adding Chinese aliases for File namespace”. Recreate the stack afterwards: `docker compose up -d --build --force-recreate`.

## Verifying Extensions
See `docs/extension-checks.md` for quick ways to verify each extension is enabled and working, including example SMW queries and Mermaid blocks.

## Security Notes
- Change default admin password in `.env` before first run or immediately after via Special:ChangePassword.
- `.env` is gitignored; store secrets outside version control.

## Project Layout
- `docker-compose.yml` — services, env wiring, volumes
- `Dockerfile.mediawiki` — custom image, extension installs
- `scripts/init-mediawiki.sh` — first-boot installer and config
- `.env.example` — sample environment file
- `./data/LocalSettings.php` — persisted config after first run

## License
This repository contains configuration and setup scripts. MediaWiki and extensions are licensed by their respective authors.
