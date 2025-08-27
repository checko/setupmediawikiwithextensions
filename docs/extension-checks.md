# Extension Verification Guide

Quick ways to confirm your requested extensions are installed, enabled, and working.

Covers: MsUpload, WikiEditor, MultimediaViewer, PdfHandler, SemanticMediaWiki, VisualEditor, CodeEditor, Mermaid.

## Check via UI
- Special:Version: open `http://<your-host>:9090/index.php/Special:Version`
- Look under “Installed software → Extensions”. Ensure these appear:
  - MsUpload, WikiEditor, MultimediaViewer, PdfHandler, SemanticMediaWiki, VisualEditor, CodeEditor, Mermaid

## Check via API
- Open in a browser:
  - `http://<your-host>:9090/api.php?action=query&meta=siteinfo&siprop=extensions&format=json`
- Search the JSON for each extension name.

## Check via CLI (Docker)
Run inside the project folder:

```
# List loaded status for specific extensions
docker compose exec -T mediawiki php maintenance/eval.php <<'PHP'
$exts = ['MsUpload','WikiEditor','MultimediaViewer','PdfHandler','SemanticMediaWiki','VisualEditor','CodeEditor'];
$reg = ExtensionRegistry::getInstance();
foreach ($exts as $e) {
  echo $e . ': ' . ($reg->isLoaded($e) ? 'ENABLED' : 'MISSING') . "\n";
}
PHP
```

## Sanity Tests per Extension
- VisualEditor: open any page → click `Edit`; VisualEditor toolbar should appear. If not, check `$wgServer`/Parsoid config.
- MsUpload: visit `Special:Upload`; drag a file to see enhanced UI.
- PdfHandler: upload a small PDF; file page should show a generated thumbnail and page count.
- MultimediaViewer: click a page’s image thumbnail; a lightbox should open.
- CodeEditor: edit `MediaWiki:Common.js`; syntax-highlighted editor should load.
- Mermaid:
  - Flowchart: `{{#mermaid:graph TD; A-->B; B-->C;}}`
  - Timeline (v10+):
    
    `{{#mermaid:
    timeline
      title Product Timeline
      2025-08-01 : Kickoff
      2025-08-07 : API Draft
      2025-08-15 : Frontend Alpha
      2025-08-22 : Beta
      2025-09-01 : Release
    }}`
  - Mindmap (v10+):
    
    `{{#mermaid:
    mindmap
      Root
        Child A
        Child B
    }}`
  - Notes: start Mermaid blocks at column 1 (not inside list bullets); mindmap requires one root and consistent indentation.
- SemanticMediaWiki:
  - Confirm at `Special:Version`, then visit `Special:SMWAdmin` to see status.
  - Create a page with: `[[Has number::42]]` and save.
  - Optional rebuild (can take time on large wikis):
    - `docker compose exec mediawiki php extensions/SemanticMediaWiki/maintenance/rebuildData.php -d 50`

## Troubleshooting
- Missing from Special:Version:
  - Confirm `data/LocalSettings.php` contains `wfLoadExtension( 'Name' );` entries and no typos.
  - Run updates: `docker compose exec mediawiki php maintenance/update.php --quick`.
  - For MsUpload: ensure the directory exists at `/var/www/html/extensions/MsUpload`.
  - For SMW: ensure Composer deps are present:
    - `docker compose exec mediawiki composer show | grep semantic-media-wiki || true`
- VisualEditor issues:
  - Ensure `MW_SITE_SERVER` or `$wgServer` matches how you access the site (scheme/host/port).
- PdfHandler issues:
  - Verify ImageMagick/Ghostscript/Poppler are installed (bundled in the image), and check container logs for conversion errors: `docker compose logs -f mediawiki`.

## Useful Pages
- Special:Version — list extensions/skins and versions
- Special:Upload — upload interface (MsUpload UI)
- Special:SMWAdmin — SMW admin/status

Replace `<your-host>` with your IP/hostname, e.g., `192.168.145.166`.
