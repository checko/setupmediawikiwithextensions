# MediaWiki 1.31 Database Upgrade Strategy

Date: 2025-09-23
Target: MediaWiki 1.44.0 LTS
Source: MediaWiki 1.31.x databases

## Overview

This document outlines the strategy for upgrading MediaWiki 1.31 databases to MediaWiki 1.44.0 LTS using the existing intermediate upgrade infrastructure in this project.

## Current Project Infrastructure

The project already includes infrastructure for automatic database upgrades:

- **Legacy MediaWiki Bundle**: MediaWiki 1.39.8 at `/opt/mediawiki-1.39`
- **Automatic Detection**: `run_update_with_legacy_support()` function detects upgrade failures
- **Minimal Configuration**: Template LocalSettings.php for intermediate upgrades
- **Error Pattern Matching**: Detects "Can not upgrade from versions older than 1.35"

## Supported Upgrade Path

Based on MediaWiki's official upgrade policy and LTS support:

### Current Implementation: 1.31 → 1.39 → 1.44

**This should work because:**
- MediaWiki 1.31 LTS → MediaWiki 1.39 LTS is officially supported
- MediaWiki 1.39.8 includes database upgrade fixes for older versions (1.39.2+)
- MediaWiki 1.39 → 1.44 is supported in current implementation

### Upgrade Process Flow

```
MediaWiki 1.31 Database
           ↓
1. Try MW 1.44 update.php
           ↓
2. Fails: "Cannot upgrade from versions older than 1.35"
           ↓
3. Auto-trigger MW 1.39.8 intermediate upgrade
           ↓
4. MW 1.39.8 processes 1.31 → 1.39 schema changes
           ↓
5. Re-run MW 1.44 update.php (1.39 → 1.44)
           ↓
6. Success: Database now at MW 1.44 schema
```

## Testing Current Implementation

### Step 1: Test with MediaWiki 1.31 Database

1. **Prepare test database dump from MW 1.31**
2. **Use existing restore process**:
   ```bash
   # Enable restore in .env
   MW_RESTORE_ON_INIT=1
   MW_RESTORE_DB_DUMP=/data/wikidb-1.31.sql

   # Start stack - should auto-upgrade
   docker compose up -d --build
   ```

3. **Monitor logs for upgrade process**:
   ```bash
   docker compose logs -f mediawiki
   ```

### Expected Log Output
```
[upgrade:pre139] Detected pre-1.39 database. Running intermediate upgrade via MediaWiki 1.39...
[upgrade:pre139] Intermediate upgrade complete. Re-running MediaWiki 1.44 updater...
```

## Potential Issues and Solutions

### Issue 1: MediaWiki 1.39 Cannot Handle 1.31

**Symptoms**: MW 1.39 fails with older database error
**Solution**: Add MediaWiki 1.35 as additional intermediate step

### Issue 2: Actor Table Conflicts (Common with 1.31)

**Symptoms**: `CannotCreateActorException` during upgrade
**Solution**: Already documented in `docs/RESTORE-DB.md`:
```sql
UPDATE actor a JOIN user u ON u.user_id=a.actor_user
SET a.actor_name=u.user_name
WHERE a.actor_user IS NOT NULL AND a.actor_name<>u.user_name;
```

### Issue 3: Missing Database Tables/Columns

**Symptoms**: SQL errors about missing tables/columns
**Solution**: MW 1.39.8 should handle these automatically

## Enhanced Implementation (If Needed)

If testing reveals that MW 1.39 cannot handle some 1.31 databases, implement three-tier upgrade:

### Extended Upgrade Path: 1.31 → 1.35 → 1.39 → 1.44

**Dockerfile Changes**:
```dockerfile
# Add MediaWiki 1.35 for very old databases
ARG MW_135_VERSION=1.35.13
RUN set -eux; \
    curl -fsSL "https://releases.wikimedia.org/mediawiki/1.35/mediawiki-${MW_135_VERSION}.tar.gz" -o /tmp/mediawiki-1.35.tar.gz; \
    mkdir -p /opt; \
    tar -xzf /tmp/mediawiki-1.35.tar.gz -C /opt; \
    mv /opt/mediawiki-${MW_135_VERSION} /opt/mediawiki-1.35; \
    rm -f /tmp/mediawiki-1.35.tar.gz
```

**Enhanced upgrade function**:
```bash
run_update_with_multilevel_legacy_support() {
  local conf_file="${1:-LocalSettings.php}"

  # Try MW 1.44
  if ! php maintenance/update.php --quick --conf "$conf_file"; then

    # Try MW 1.39 intermediate
    if run_legacy_upgrade "/opt/mediawiki-1.39" "1.39"; then
      php maintenance/update.php --quick --conf "$conf_file"
      return $?
    fi

    # Try MW 1.35 intermediate (for very old DBs)
    if run_legacy_upgrade "/opt/mediawiki-1.35" "1.35"; then
      # Chain: 1.35 → 1.39 → 1.44
      run_legacy_upgrade "/opt/mediawiki-1.39" "1.39"
      php maintenance/update.php --quick --conf "$conf_file"
      return $?
    fi
  fi
}
```

## Verification Steps

### 1. Database Schema Version
```sql
SELECT * FROM updatelog WHERE ul_key = 'version';
```

### 2. Extension Compatibility
- Check Special:Version for all extensions loaded
- Verify SemanticMediaWiki tables if SMW was enabled

### 3. Functional Testing
- Login with existing users
- Create/edit pages
- Upload files (if enabled)
- Test extension features

## Known Limitations

### 1. Very Old Extension Data
- Some extension data from 1.31 may not migrate cleanly
- SemanticMediaWiki may require `setupStore.php --skip-import`

### 2. Configuration Changes
- New MediaWiki 1.44 configuration options won't be set
- Manual review of LocalSettings.php may be needed

### 3. Performance
- Large databases may take significant time to upgrade
- Multiple intermediate upgrades increase processing time

## Rollback Strategy

### If Upgrade Fails
1. **Restore from backup**: Use pre-upgrade database backup
2. **Manual intermediate upgrade**: Use specific MW versions manually
3. **Partial migration**: Migrate content only, recreate structure

### Database Backup
Always backup before attempting upgrade:
```bash
docker compose exec -T db mysqldump -u root -p"$MW_DB_ROOT_PASSWORD" "$MW_DB_NAME" > backup-pre-upgrade.sql
```

## Implementation Priority

### Phase 1: Test Current Implementation ✅
- Test MW 1.31 → 1.39 → 1.44 with existing code
- Document results and any issues

### Phase 2: Enhanced Implementation (If Needed)
- Add MW 1.35 intermediate step if required
- Implement multi-level upgrade function
- Add comprehensive error handling

### Phase 3: Documentation and Testing
- Update RESTORE-DB.md with 1.31 specific notes
- Create test cases for various 1.31 database states
- Validate upgrade process end-to-end

## Recommendation

**Start with testing the current implementation** since MediaWiki 1.39.8 should handle upgrades from 1.31. The existing infrastructure may already be sufficient without additional changes.

Only implement the enhanced three-tier upgrade system if testing reveals specific compatibility issues with the current two-tier approach.