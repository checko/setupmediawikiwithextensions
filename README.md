# MediaWiki Test Stack (Docker)

A quick-start MediaWiki stack using Docker Compose, pre-wired with commonly used extensions:

- MsUpload
- WikiEditor
- MultimediaViewer
- PdfHandler
- SemanticMediaWiki (SMW)
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

On first run, the container auto-installs MediaWiki, persists `LocalSettings.php` to `./data/LocalSettings.php`, enables the extensions, and runs database updates including SMW tables.

## What’s in the stack
- `mediawiki` service: custom image based on `mediawiki:1.41`, plus system tools for PdfHandler and Composer. Extensions are cloned/installed during image build.
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
- To change port, edit `docker-compose.yml` port mapping.

## Installed Extensions
- MsUpload, WikiEditor, MultimediaViewer, PdfHandler, VisualEditor, CodeEditor
- SemanticMediaWiki (`mediawiki/semantic-media-wiki ~4.1` via Composer)

## Maintenance
- Run MediaWiki update (schema changes, extension updates):
  - `docker compose exec mediawiki php maintenance/update.php --quick`
- Rebuild SMW data (optional):
  - `docker compose exec mediawiki php extensions/SemanticMediaWiki/maintenance/rebuildData.php -d 50`
- View logs:
  - `docker compose logs -f mediawiki`
- Stop:
  - `docker compose down`
- Full reset (dev only – removes volumes):
  - `docker compose down -v`

## Troubleshooting
- Blank/failed VE edits: ensure `MW_SITE_SERVER` matches how you access the wiki (scheme/host/port).
- PDF thumbnails/text extract missing: ensure ImageMagick, Ghostscript, Poppler are installed (baked into image). For very large PDFs, resource limits may apply.
- DB not ready on first start: the web container waits for DB; if stuck, check `docker compose logs db`.

## Verifying Extensions
See `docs/extension-checks.md` for quick ways to verify each extension is enabled and working.

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
