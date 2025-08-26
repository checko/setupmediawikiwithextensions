# Fix and Worklog

This document summarizes the issues encountered while bringing the MediaWiki Docker stack to a solid, first‑run experience (with video uploads), and the corresponding fixes applied.

## Overview
- Stack: MediaWiki 1.41 + MariaDB via Docker Compose
- Goal: Bypass web installer, persist config, enable key extensions, support large video uploads with playback.

## Issues and Fixes

1) LocalSettings.php not found (web installer page)
- Symptom: Browser showed "LocalSettings.php not found" despite `data/LocalSettings.php` existing.
- Root cause: The webroot had a symlink to `/data/LocalSettings.php` which Apache/PHP (www-data) couldn’t follow in this environment.
- Fix: Replace symlink with a real file copy in webroot; keep `/data/LocalSettings.php` as the persisted source.
  - scripts/init-mediawiki.sh now:
    - Copies `/data/LocalSettings.php` into `/var/www/html/LocalSettings.php` (no symlink).
    - On fresh install, copies generated file into `/data` and keeps a real copy in webroot.

2) Idempotent extension configuration and persistence safety
- Improvement: If `data/LocalSettings.php` exists (e.g., after container recreate), ensure the custom extension block is present and webroot copy is synced.
- Also added `COMPOSER_ALLOW_SUPERUSER=1` in Dockerfile to silence Composer root warnings.

3) Allow video uploads (mp4/avi/mkv) and large file sizes
- Added to LocalSettings via init script (idempotent enforcement):
  - `$wgFileExtensions[] = 'mp4'; 'avi'; 'mkv';`
  - `$wgMaxUploadSize = 1024 * 1024 * 1024;` (1 GiB)
- Increased PHP limits in `php/conf.d/uploads.ini`:
  - `upload_max_filesize=1024M`, `post_max_size=1024M`.

4) TimedMediaHandler (TMH) video playback
- Enabled TMH and installed ffmpeg:
  - Dockerfile: `ffmpeg` installed via apt.
  - LocalSettings: `wfLoadExtension('TimedMediaHandler');`
  - Config: `$wgFFmpegLocation='/usr/bin/ffmpeg'; $wgTmhEnableTranscode=false;` (no heavy jobs by default)
  - Allowed MP4 ingestion: `$wgTmhEnableMp4Uploads = true;`

5) MP4 upload error: Class "getID3" not found
- Symptom: Upload dialog showed "Caught exception of type Error: Class getID3 not found".
- Root cause: TMH requires the getID3 library to parse media metadata.
- Fix: Vendor getID3 into the image and require it from LocalSettings.
  - Dockerfile: downloads getID3 (v1.9.23) into `/var/www/html/vendor/getid3/getid3`.
  - LocalSettings (via init script):
    - `require_once __DIR__ . '/vendor/getid3/getid3/getid3/getid3.php';`
  - Verified in container that `class_exists('getID3')` is true.

6) Page save error after inserting video: database query error
- Symptom: "A database query error has occurred" after saving page with an embedded MP4.
- Root cause: TMH `transcode` table was missing.
- Fix: Ran `maintenance/update.php` to create TMH tables (including `transcode`).
- Note: The init script already runs `update.php` on fresh install; after enabling TMH later, `update.php` was run manually to sync schema.

7) Misc improvements
- SMW (Semantic MediaWiki) is optional and controlled by env `MW_ENABLE_SMW`.
  - If enabled and extension files are missing, the script attempts Composer install.
  - If enabling fails, lines are commented out to avoid startup fatals.
- Ensured extension config/appends are idempotent and webroot copy is kept in sync with `/data`.
- Temporary debug enabled to capture full stack traces when needed:
  - `$wgShowExceptionDetails = true; $wgLogExceptionBacktrace = true; $wgDebugLogFile = "/tmp/wiki-debug.log";`

## Files Touched
- Dockerfile.mediawiki
  - Add `COMPOSER_ALLOW_SUPERUSER=1`.
  - Install tools: `ffmpeg`.
  - Vendor getID3 into `/var/www/html/vendor/getid3/getid3`.
  - Clone `TimedMediaHandler` at build.
- scripts/init-mediawiki.sh
  - Copy LocalSettings into webroot (no symlink) and persist to `/data`.
  - Append custom extensions block if missing; enforce config idempotently.
  - Enable TMH, set ffmpeg path, allow MP4 ingestion, and require getID3.
  - Enforce allowed file extensions and `$wgMaxUploadSize`.
  - SMW idempotent install/enable via env toggle, with safety fallbacks.
- php/conf.d/uploads.ini
  - Raise `upload_max_filesize` and `post_max_size` to 1024M.

## Verification Checklist
- First run bypasses web installer; `LocalSettings.php` present and readable in webroot.
- Special:Version shows: MsUpload, WikiEditor, MultimediaViewer, PdfHandler, VisualEditor, CodeEditor, TimedMediaHandler.
- Upload limits:
  - PHP: `upload_max_filesize=1024M`, `post_max_size=1024M`
  - MediaWiki: `$wgMaxUploadSize = 1 GiB`
- Allowed file types include: gif, jpeg, jpg, png, webp, pdf, mp4, avi, mkv.
- MP4 upload works; thumbnails generate; page save succeeds (TMH tables present).

## Suggested Future Safeguards
- Auto-run `maintenance/update.php` on startup when detecting newly enabled extensions or missing required tables (e.g., TMH `transcode`).
- Optionally enable TMH transcoding with job runner if desired (increases CPU usage).
- Turn off debug logging after validation (to reduce noise and disk writes).

