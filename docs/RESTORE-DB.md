# MediaWiki Database Restore Guide (Docker Compose)

This guide restores a MediaWiki database exported from another server into this stack, and handles schema upgrades safely (including an intermediate 1.35 step when needed) plus a common SMW actor/name conflict.

Works with the compose in this repo. Adjust paths if your layout differs.

## Prerequisites
- Docker + Docker Compose installed and working
- This repo is set up and the stack is created at least once (`docker compose up -d`)
- `.env` with DB credentials (defaults):
  - `MW_DB_NAME=wikidb`
  - `MW_DB_USER=wiki`
  - `MW_DB_PASS=wiki_pass`
  - `MW_DB_ROOT_PASSWORD=root_pass`
- Your dump file: `wikidb.sql` or `wikidb.sql.gz`

## TL;DR (common case)
Most restores from MediaWiki 1.35 or newer only need:

1) Put dump at repo root, e.g. `./wikidb.sql`
2) Run the helper:

```
bash scripts/restore-db.sh ./wikidb.sql
```

The script:
- Stops web, backs up current DB to `data/backup-YYYYmmdd-HHMMSS.sql`
- Imports the dump into `MW_DB_NAME`
- Runs `maintenance/update.php`
- Starts web again

Afterwards: open your wiki and log in using the admin from the source wiki.

## If updater says “Cannot upgrade from versions older than 1.35”
The stack now bundles MediaWiki 1.35 and will automatically run the intermediate updater when it detects this condition. You should only need the manual steps below if you want to re-run the process yourself (for example, after customizing `LocalSettings.php`).

1) Stop web (DB stays up):

```
docker compose stop mediawiki
```

2) Run MW 1.35 updater on the same compose network using a minimal LocalSettings:

- A ready-to-use file is included: `templates/LocalSettings.minimal.php` (loads only the legacy Vector skin). Copy it into `./data/LocalSettings.php` if you want to inspect or tweak it before running the updater, but avoid enabling newer skins/extensions here—the 1.35 tarball lacks them and the updater will fail.
- Detect compose network (usually `<folder>_default`):

```
net=$(docker network ls --format '{{.Name}}' | grep -E "^$(basename "$PWD")_default$")
echo "$net"
```

- Execute the updater (substitute env values if changed):

```
docker run --rm \
  --network "$net" \
  -e MW_DB_HOST=db \
  -e MW_DB_NAME="$(grep -E '^MW_DB_NAME=' .env | sed 's/^MW_DB_NAME=//')" \
  -e MW_DB_USER="$(grep -E '^MW_DB_USER=' .env | sed 's/^MW_DB_USER=//')" \
  -e MW_DB_PASS="$(grep -E '^MW_DB_PASS=' .env | sed 's/^MW_DB_PASS=//')" \
  -e MW_SITE_SERVER="$(grep -E '^MW_SITE_SERVER=' .env | sed 's/^MW_SITE_SERVER=//')" \
  -v "$PWD/templates/LocalSettings.minimal.php:/var/www/html/LocalSettings.php:ro" \
  mediawiki:1.35 php maintenance/update.php --quick
```

3) Start web and finalize update on 1.41:

```
docker compose start mediawiki
docker compose exec mediawiki php maintenance/update.php --quick
```

## Optional: fix SMW “Maintenance script” actor conflict
On some imports, the updater can fail with:

```
CannotCreateActorException ... Cannot replace user for existing actor: actor_id=5, new user_id=...
```

This is typically an `actor` row whose `actor_user` points to a user, but `actor_name` still says `Maintenance script`.

Fix by aligning `actor_name` with the linked user’s `user_name`:

```
docker compose exec -T db sh -lc "mysql -u root -p'$MW_DB_ROOT_PASSWORD' -e \"USE $MW_DB_NAME; \
  UPDATE actor a JOIN user u ON u.user_id=a.actor_user \
  SET a.actor_name=u.user_name \
  WHERE a.actor_user IS NOT NULL AND a.actor_name<>u.user_name;\""
```

Then initialize SMW tables (idempotent) and run the updater again:

```
docker compose exec mediawiki php extensions/SemanticMediaWiki/maintenance/setupStore.php --skip-import
docker compose exec mediawiki php maintenance/update.php --quick
```

## Users and uploads
- Full DB restore replaces users/groups/preferences from the source wiki. Use the admin from the source wiki. If needed:

```
docker compose exec mediawiki php maintenance/changePassword.php --user 'Admin' --password 'NewStrongPass123!'
```

- Uploads are not in the DB. Copy the prior `images/` into the `wiki_images` volume:

```
docker compose cp /path/to/images/. mediawiki:/var/www/html/images/
```

## Troubleshooting
- Dump includes `CREATE DATABASE`/`USE`: the restore script strips those; for manual imports, delete or replace them to target `$MW_DB_NAME`.
- Stuck on DB start: check `docker compose logs db`.
- VE/Parsoid issues: ensure `MW_SITE_SERVER` matches how you access the wiki (scheme/host/port), then hard refresh.
- Large imports: the restore can take a while; monitor `docker compose logs -f mediawiki` and `db` if needed.

## Verification
- Home page renders at `MW_SITE_SERVER`
- Special:Version shows expected extensions
- Create/edit pages works; uploads allowed (per `.env` and LocalSettings)

## Restore Uploads (images/ directory)
Database restores don’t include files. To make pages display images, restore the old wiki’s `images/` tree into this stack’s images volume and refresh metadata.

Where files live here
- Container path: `/var/www/html/images`
- Compose volume: `wiki_images` (named volume mounted to that path)

Step-by-step (tar.gz archive)
1) Put your archive at the repo root, e.g. `uploadimage.tar.gz`.
2) Copy it into the running container and inspect top-level structure:

```
docker compose cp uploadimage.tar.gz mediawiki:/tmp/uploadimage.tar.gz
docker compose exec -T mediawiki sh -lc "tar -tzf /tmp/uploadimage.tar.gz | head -n 20"
```

You’ll typically see one of these layouts in the listing:
- A: `mediawiki-<version>/images/...`
- B: `images/...`
- C: hashed leaf dirs only: `a/ab/File.png`, `b/bc/...`, etc.

3) Extract into `/var/www/html/images` using the matching command:
- Case A (archive contains `mediawiki-<version>/images/...`):

```
docker compose exec -T mediawiki sh -lc \
  "mkdir -p /var/www/html/images && \
   tar -xzf /tmp/uploadimage.tar.gz -C /var/www/html/images \
       --strip-components=2 mediawiki-*/images"
```

- Case B (archive contains top-level `images/...`):

```
docker compose exec -T mediawiki sh -lc \
  "tar -xzf /tmp/uploadimage.tar.gz -C /var/www/html \
       --strip-components=0 images"
```

- Case C (archive already is the content of `images/`):

```
docker compose exec -T mediawiki sh -lc \
  "mkdir -p /var/www/html/images && \
   tar -xzf /tmp/uploadimage.tar.gz -C /var/www/html/images"
```

Notes:
- Keep quotes as shown to avoid host shell expansion. Adjust the exact path (`mediawiki-1.25.2/images`) if needed.
- If your archive is a `.zip`, use `unzip -l` to inspect and `unzip` with the matching path pattern, then move into `/var/www/html/images`.

4) Fix ownership and permissions inside the container:

```
docker compose exec -T mediawiki sh -lc \
  "chown -R www-data:www-data /var/www/html/images && \
   find /var/www/html/images -type d -exec chmod 755 {} + && \
   find /var/www/html/images -type f -exec chmod 644 {} +"
```

5) Refresh MediaWiki’s file metadata and link tables:

```
docker compose exec mediawiki php maintenance/refreshImageMetadata.php --force
docker compose exec mediawiki php maintenance/rebuildImages.php --missing
```

6) Verify in the UI:
- Open Special:ListFiles and click a few files; the original should be present.
- Visit pages that embed images; thumbnails regenerate on first view. Hard-refresh if needed.

Troubleshooting
- Permission errors in logs: re-run the ownership/permission commands above.
- Missing originals: ensure your archive contains the full `images/` tree (not only `images/thumb/`). Originals live directly under hashed paths like `images/a/ab/Filename.png`.
- Very large sets: the refresh scripts may take time; they are safe to re-run.
- Do not use `maintenance/importImages.php` unless the DB truly lacks file rows; it creates new DB entries and can duplicate existing files.

### ZIP archives with non-UTF-8 filenames
- Set `MW_ZIP_ENCODING` in `.env` (for example `cp950` or `gbk`) before starting the stack so the init script can hint the correct encoding during extraction.
- Both the startup restore and `scripts/restore-uploads.sh` automatically translate `#Uxxxx`/`#Lxxxxxx` escape sequences into real Unicode characters after extraction, so filenames like `螢幕擷取畫面_2025-09-03_125009.png` work without manual renaming.
- To re-run the normalization on an existing stack, execute:

  ```
  docker compose exec mediawiki python3 - <<'PY'
  import os, re
  root = '/var/www/html/images'
  pattern = re.compile(r'#([UL])([0-9A-Fa-f]{4,6})')

  def decode(name):
      if '#U' not in name and '#L' not in name:
          return name
      def repl(match):
          try:
              return chr(int(match.group(2), 16))
          except ValueError:
              return match.group(0)
      return pattern.sub(repl, name)

  for dirpath, dirnames, filenames in os.walk(root, topdown=False):
      for entry in dirnames + filenames:
          new_name = decode(entry)
          if new_name != entry:
              src = os.path.join(dirpath, entry)
              dst = os.path.join(dirpath, new_name)
              base, ext = os.path.splitext(dst)
              counter = 1
              while os.path.exists(dst):
                  dst = f"{base}_{counter}{ext}"
                  counter += 1
              os.rename(src, dst)
  PY
  ```
