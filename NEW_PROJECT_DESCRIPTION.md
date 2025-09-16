# MediaWiki Accelerator Stack — Project Blueprint

## Vision
Deliver a turnkey MediaWiki environment that teams can spin up in minutes for knowledge bases, documentation hubs, or archival wikis. The stack should feel production-ready out of the gate: sensible defaults, rich editing tools, multilingual support, and guardrails for backups and restores. Everything must be reproducible via Docker Compose so new environments (local, staging, prod) behave identically.

## Core Objectives
- **Zero-interaction provisioning:** Containers bootstrap MediaWiki, create the initial admin, and persist `LocalSettings.php` automatically on first start. No browser installer.
- **Extension bundle for modern authoring:** Ship with VisualEditor + Parsoid, WikiEditor, CodeEditor, MsUpload, MultimediaViewer, PdfHandler, Mermaid, Markdown, SyntaxHighlight, TimedMediaHandler, and Semantic MediaWiki (SMW) enabled by default.
- **Rich media readiness:** Support 1 GiB video uploads with MP4/AVI/MKV playback, PDF thumbnails, large raster images, SVG rendering via librsvg, and preloaded fonts for CJK glyphs.
- **Data portability:** Provide scripted import/export for database dumps and uploads archives, including one-time automated restore during first boot.
- **Internationalization niceties:** Add namespace aliases for Chinese file prefixes (`檔案`, `文件`) so migrated pages work without edits.
- **Operator ergonomics:** Document every workflow (backup, restore, extension checks, debugging) and expose toggles through `.env` rather than code edits.

## Stack Components
- `mediawiki` service: Custom image based on `mediawiki:1.43` (LTS) built from `Dockerfile.mediawiki`.
  - Installs tooling (ffmpeg, ImageMagick, Ghostscript, Poppler, librsvg, MariaDB client, Composer, Pygments) plus fonts for multilingual thumbnails.
  - Clones extension sources at build time and vendors Semantic MediaWiki + getID3.
  - Overlays the Mermaid extension so ResourceLoader ships only a lightweight initializer (`patches/ext.mermaid.init.js`) while the v10.9.1 library loads from `/extensions/Mermaid/resources/mermaid.min.js`.
  - Entrypoint `scripts/init-mediawiki.sh` manages install/restore logic, enforces idempotent config, and keeps `/data/LocalSettings.php` synced with the webroot.
- `db` service: `mariadb:10.6` with credentials injected from `.env` and storage persisted to the `db_data` volume.
- Volumes:
  - `./data` bind-mounted to persist `LocalSettings.php`, restore markers, and transfer dumps.
  - Named volume `wiki_images` for uploads; `db_data` for MariaDB files.
  - PHP overrides in `php/conf.d/uploads.ini` push `upload_max_filesize`/`post_max_size` to 1 GiB.

## Bootstrap & Restore Flow
1. Copy `.env.example` → `.env`, set admin password, site URL, and optional toggles (`MW_MAX_IMAGE_AREA`, `MW_SVG_MAX_SIZE`, `MW_MERMAID_THEME`, etc.).
2. `docker compose up -d --build` builds the custom image and launches the stack.
3. Entrypoint waits for MariaDB, optionally runs `scripts/init-mediawiki.sh` autodetect restore:
   - Imports SQL dumps (`.sql` / `.sql.gz`) when `MW_RESTORE_ON_INIT=1` and `MW_RESTORE_DB_DUMP` is set; uses marker files to prevent reruns.
   - Extracts uploads archives (`.zip`/`.tar.gz`) with backup + permission fixes; honors `MW_ZIP_ENCODING` for non-UTF-8 ZIP filenames.
   - Seeds minimal `LocalSettings.php` if missing, executes `maintenance/update.php`, and re-runs after restore.
4. Installer path handles brand-new databases, appends the curated extension block, configures VisualEditor/Parsoid, TimedMediaHandler, large file settings, Mermaid theme, WikiMarkdown autoload, and SMW enablement (configurable via `MW_ENABLE_SMW`).
5. Chinese namespace aliases appended to accommodate migrated content without manual edits.

## Operations Toolkit
- `scripts/restore-db.sh`: Stops the web container, backs up the current DB to `./data/backup-<timestamp>.sql`, strips `CREATE DATABASE`/`USE` from incoming dumps, imports, then runs `maintenance/update.php` and restarts MediaWiki.
- `scripts/restore-uploads.sh`: Interactive helper that copies archives into the container, auto-detects layout (`mediawiki-*/images`, `images/`, hashed directories), creates backups, refreshes metadata, and supports host-side ZIP encoding conversion.
- `docs/` playbooks: step-by-step guides for database upgrades (including 1.35 intermediate hop + SMW actor fix), export procedures, extension validation, Mermaid debugging, and session memos documenting prior restores.
- `.env` toggles: adjust image limits, SVG conversion, Mermaid theme, ResourceLoader debug, restore options, and SMW enablement without touching scripts.

## File Layout Snapshot
- `docker-compose.yml` — defines `mediawiki` + `db` services, binds volumes, wires environment variables, exposes port 9090.
- `Dockerfile.mediawiki` — builds the bespoke MediaWiki image with all dependencies/extensions preloaded.
- `scripts/` — automation for init, database restore, and uploads restore.
- `patches/` — client-side overlays (Mermaid initializer).
- `docs/` — operational manuals and change logs.
- `php/conf.d/uploads.ini` — PHP upload/post size overrides.
- `.env.example` — template of tunable settings.

## Roadmap Considerations for the New Project
- Add CI to lint shell scripts and validate Docker build.
- Provide optional job-runner service for background MediaWiki jobs (cron/CLI).
- Introduce health checks (e.g., curl `Special:Version`) for readiness probes.
- Expand localization aliases or language packs based on target user base.
- Package opinionated skin(s) and authentication add-ons if required by stakeholders.

This blueprint can seed the new project repository: copy core assets, prune site-specific docs, and iterate on the roadmap items to tailor the stack to its eventual deployment environments.
