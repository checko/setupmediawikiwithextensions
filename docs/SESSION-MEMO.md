# MediaWiki Restore — Session Memo

Updated: 2025-09-10

- URL: `http://192.168.145.166:9090`
- Stack: Docker Compose (`mediawiki` + `db`)
- Repo root: this folder

Status
- Database: Restored from `./wikidb.sql` and upgraded.
  - Ran intermediate update with `mediawiki:1.35`, then finalized on 1.41.5.
  - Resolved SMW actor/user conflict (aligned `actor.actor_name` with `user.user_name`).
  - Current MW: 1.41.5; SMW initialized; `update.php` completed.
- Uploads: Restored on 2025-09-10 from `images.zip` using the new script.
  - Script used: `bash scripts/restore-uploads.sh images.zip --yes`
  - Previous mistaken content is still available for reference at `/var/www/html/images.bak-20250908-175403` (inside container).
  - The script also made an automatic backup of the pre-restore state under `/var/www/html/images.bak-<timestamp>`.
  - Ran `refreshImageMetadata.php` successfully; `rebuildImages.php --missing` reported a MimeAnalyzer null-type error in MW 1.41 (non-fatal); images display fine. We can revisit if missing files are noticed.
- Docs/Tools added:
  - `scripts/restore-db.sh` (import + backup + update)
  - `docs/RESTORE-DB.md` (full guide, incl. 1.35 step and SMW fix)
  - `data/LocalSettings.upgrade.php` (minimal config for the 1.35 updater)

Uploads Restore

Fast path (script)
- `bash scripts/restore-uploads.sh <images.(zip|tar.gz)> --yes`
  - Detects layout automatically (`mediawiki-*/images`, `images/`, or hashed subdirs), fixes perms, refreshes metadata, and makes a pre-restore backup.

Manual path (if you prefer step-by-step)
1) Copy archive into container:
   - `docker compose cp YOUR_ARCHIVE.tar.gz mediawiki:/tmp/uploads.tar.gz`
2) Inspect layout:
   - `docker compose exec -T mediawiki sh -lc "tar -tzf /tmp/uploads.tar.gz | head -n 20"`
3) Extract into `/var/www/html/images` based on layout:
   - If `mediawiki-*/images/...`:
     - `docker compose exec -T mediawiki sh -lc "mkdir -p /var/www/html/images && tar -xzf /tmp/uploads.tar.gz -C /var/www/html/images --strip-components=2 mediawiki-*/images"`
   - If `images/...`:
     - `docker compose exec -T mediawiki sh -lc "tar -xzf /tmp/uploads.tar.gz -C /var/www/html --strip-components=0 images"`
   - If hashed subdirs only (a/ab/...):
     - `docker compose exec -T mediawiki sh -lc "mkdir -p /var/www/html/images && tar -xzf /tmp/uploads.tar.gz -C /var/www/html/images"`
4) Fix ownership/permissions:
   - `docker compose exec -T mediawiki sh -lc "chown -R www-data:www-data /var/www/html/images && find /var/www/html/images -type d -exec chmod 755 {} + && find /var/www/html/images -type f -exec chmod 644 {} +"`
5) Refresh metadata:
   - `docker compose exec mediawiki php maintenance/refreshImageMetadata.php --force`
   - `docker compose exec mediawiki php maintenance/rebuildImages.php --missing`
6) Verify: Special:ListFiles and pages with images.

Optional
- Restore the reverted content (if needed temporarily):
  - `docker compose exec -T mediawiki sh -lc "rm -rf /var/www/html/images/* && cp -a /var/www/html/images.bak-20250908-175403/. /var/www/html/images/ && chown -R www-data:www-data /var/www/html/images"`
- Remove backup after confirming success:
  - `docker compose exec -T mediawiki sh -lc "rm -rf /var/www/html/images.bak-20250908-175403"`

References
- DB restore guide: `docs/RESTORE-DB.md`
- Quick restore: `bash scripts/restore-db.sh ./wikidb.sql`
- Env: `.env` (site URL `MW_SITE_SERVER`, DB settings)
