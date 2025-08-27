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
  - Includes `librsvg2-bin` for high‑quality SVG rasterization via `rsvg-convert`.
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
- To change port, edit `docker-compose.yml` port mapping.

### Important: Do not edit `./data/*` directly
- The file `./data/LocalSettings.php` is persisted output and managed by the init script.
- Make configuration changes in `scripts/init-mediawiki.sh` (source of truth) and/or `.env`, then rebuild/recreate:
  - `docker compose up -d --build --force-recreate`
- The init script will enforce config (extensions, upload types/sizes, TMH, etc.) and sync the webroot copy of `LocalSettings.php`.
- Rationale: editing `./data/LocalSettings.php` manually can be overwritten or drift from the intended, versioned configuration.

## Installed Extensions
- MsUpload, WikiEditor, MultimediaViewer, PdfHandler, VisualEditor, CodeEditor
- SyntaxHighlight (with Pygments for code blocks)
- SemanticMediaWiki (`mediawiki/semantic-media-wiki ~4.1` via Composer)
- WikiMarkdown (adds `<markdown>...</markdown>` tag and Markdown content model)
- Mermaid (parser function `#mermaid` for flowcharts/diagrams)

### Markdown Usage
- Inline/block tag: wrap content in `<markdown>...</markdown>` on any page.
- Content model: pages with `.md` suffix are treated as Markdown.
- Parsedown/Extra/Extended dependencies are bundled in the image; no extra steps needed.

### Mermaid Usage
- Use parser function with Mermaid syntax:
  `{{#mermaid:graph TD; A-->B; B-->C;}}`
- Theme via `.env`: `MW_MERMAID_THEME` (forest/default/neutral/dark).

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
- "File with dimensions greater than 12.5 MP": increase `MW_MAX_IMAGE_AREA` in `.env` (e.g., `100000000` for 100 MP). Larger values consume more CPU/RAM during thumb generation.
- SVG quality/performance: prefers `rsvg` when available. Verify at Special:Version → Image manipulation. Increase `MW_SVG_MAX_SIZE` if thumbs are too small.

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
