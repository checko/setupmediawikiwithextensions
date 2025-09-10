# Export From a Source MediaWiki Server (DB + Uploads)

Use these steps on the old server to produce a database dump and an uploads archive that this stack can restore.

Assumptions
- Source wiki uses MySQL/MariaDB (this stack restores to MariaDB).
- You have shell access to the source server (root or a user with DB dump permissions).
- Replace placeholders like `DBNAME`, `DBUSER`, `DBPASS`, and paths as needed.

## 1) Prepare for a consistent dump (optional but recommended)
Set the source wiki to read-only briefly to avoid edits during the dump:

```
# In LocalSettings.php on the source server
$wgReadOnly = 'Read-only during maintenance (export)';
```

You can remove this line after dumping.

## 2) Dump the database
Pick the variant that matches your source deployment.

Bare‑metal MySQL/MariaDB:
```
mysqldump \
  --single-transaction --quick --hex-blob \
  --default-character-set=binary \
  -u DBUSER -p'DBPASS' DBNAME | gzip -9 > wikidb.sql.gz
```

Dockerized MediaWiki with a `db` container:
```
# Replace stack folder or container name as needed
docker exec -i <db-container> \
  sh -lc "mysqldump --single-transaction --quick --hex-blob --default-character-set=binary -u root -p'$MYSQL_ROOT_PASSWORD' DBNAME" \
  | gzip -9 > wikidb.sql.gz
```

Notes:
- `--single-transaction` minimizes locking for InnoDB and yields a consistent snapshot.
- `--default-character-set=binary` avoids charset conversions during export.
- You can export uncompressed (`wikidb.sql`) if preferred.

## 3) Archive the uploads directory
On the source server, locate the wiki’s images directory (usually `<webroot>/images`). Create a tar.gz or zip; tar is recommended.

```
# From the directory containing the images/ folder
sudo tar -czf images.tar.gz images/
# or, if you’re inside the images directory already
sudo tar -czf images.tar.gz -C .. images
```

Zip alternative:
```
sudo zip -r images.zip images/
```

Tips:
- Keep originals: do NOT archive only `images/thumb/`. The originals live under hashed subfolders like `images/a/ab/Filename.png`.
- Including thumbs is fine but optional (they will regenerate on the new server).

## 4) Transfer the files to the new server
Copy to the target repo’s `./data` directory (recommended):

```
# From your workstation or source server
scp wikidb.sql.gz user@new-server:/path/to/setupmediawiki/data/
scp images.tar.gz  user@new-server:/path/to/setupmediawiki/data/
# or scp images.zip accordingly
```

## 5) Restore on the new server
Follow the README section “Restore existing wiki (DB + uploads) automatically” or run the helper scripts:

```
# Automatic (preferred): set in .env and restart
MW_RESTORE_ON_INIT=1
MW_RESTORE_DB_DUMP=/data/wikidb.sql.gz
MW_RESTORE_UPLOADS_ARCHIVE=/data/images.tar.gz

# Or manual scripts after the stack is up
bash scripts/restore-db.sh ./data/wikidb.sql.gz
bash scripts/restore-uploads.sh ./data/images.tar.gz --yes
```

After restore:
- Remove `$wgReadOnly` from the source (if you set it).
- On the new server, run `docker compose exec mediawiki php maintenance/runJobs.php --maxjobs 10000` and browse a few pages to warm caches.

## 6) Version compatibility
- Restoring from an older MediaWiki to a newer one is supported; the init script runs `maintenance/update.php`.
- Restoring from a newer MediaWiki into an older target is not supported; match or upgrade the target version first.

