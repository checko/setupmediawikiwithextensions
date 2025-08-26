# MediaWiki Debug Logging (How-To)

This wiki can enable verbose exception details and a debug log file to help troubleshoot errors. Use these settings temporarily, then disable them when finished.

## Enable (temporary)
Add these lines to `LocalSettings.php` (near the end is fine):

```php
// DEBUG (temporary)
$wgShowExceptionDetails = true;                  // Show full exception details in browser
$wgLogExceptionBacktrace = true;                 // Include backtraces in logs
$wgDebugLogFile = "/tmp/wiki-debug.log";        // Write logs to a file in the container
```

Notes:
- These settings are intended for troubleshooting. Do not keep them enabled in production.
- The log file path is inside the container; view with:
  - `docker compose exec mediawiki tail -f /tmp/wiki-debug.log`

## Disable
Comment or remove the three lines above, then reload the page or restart the container.

```php
// $wgShowExceptionDetails = true;
// $wgLogExceptionBacktrace = true;
// $wgDebugLogFile = "/tmp/wiki-debug.log";
```

## Tips
- After enabling logging, reproduce the error and immediately fetch recent log entries.
- Remember to turn these off to reduce noise and avoid leaking sensitive details.
