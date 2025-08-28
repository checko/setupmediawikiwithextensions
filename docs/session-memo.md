# Session Memo

Date: 2025-08-28
Branch: `settings-update`
Remote: `origin/settings-update`

## Changes Landed
- getID3 path normalized; added `MW_MAX_IMAGE_AREA` (default 100 MP) and enforcement.
- SVG support:
  - Installed `librsvg2-bin` (rsvg-convert), exposed `MW_SVG_MAX_SIZE`, preferred converter `rsvg`.
  - Added CJK fonts (Noto CJK, Arphic UMing/UKai, Noto Emoji) for proper Traditional Chinese glyph rendering.
- Syntax highlighting:
  - Enabled `SyntaxHighlight_GeSHi`; installed Python Pygments.
  - Verified `<syntaxhighlight>` works.
- Markdown:
  - Added `WikiMarkdown` extension; installed Composer deps (Parsedown, Extra, Extended) at build.
  - Ensured `require_once extensions/WikiMarkdown/vendor/autoload.php` precedes `wfLoadExtension('WikiMarkdown')`.
  - README: Added docs and usage.
- Mermaid:
  - Added `Mermaid` extension; theme via `.env` `MW_MERMAID_THEME` (default `forest`).
  - README: Added usage docs.
  - Client loader reworked to avoid RL minifier issues and support v10 diagrams:
    - RL module serves only an initializer; Mermaid v10.9.1 is vendored locally at `/extensions/Mermaid/resources/mermaid.min.js`.
    - Initializer uses `mermaid.run()` (v10) with delayed init and render locks to prevent duplicates.
    - Documented indentation rules (start at column 1; mindmap requires a single root) and list-bullet pitfalls.
- VisualEditor / Parsoid:
  - Enabled Parsoid from vendor path: `wfLoadExtension('Parsoid', "$IP/vendor/wikimedia/parsoid/extension.json");`
  - Set `$wgCanonicalServer = $wgServer;` to keep REST “domain” consistent.
 - SemanticMediaWiki:
  - Installed at image build via Composer create-project into `extensions/SemanticMediaWiki`.
  - Init script enables SMW and assigns `$smwgNamespace = parse_url( $wgServer, PHP_URL_HOST );` (no `enableSemantics()` call).
  - If prompted for an upgrade key, run `php extensions/SemanticMediaWiki/maintenance/setupStore.php` in the container.
 - Init script hardening:
  - Detect empty DB on first boot and run installer even when `LocalSettings.php` exists (prevents DBQueryError).
  - Skip SMW composer at runtime unless composer files are writable.

## How To Run
- Start: `docker compose up -d`
- Rebuild after config changes: `docker compose up -d --build --force-recreate`
- Logs: `docker compose logs -f mediawiki`
- URL: `http://192.168.145.166:9090`
 - Clean reset (testing): `docker compose down -v --rmi all --remove-orphans && docker compose build --no-cache && docker compose up -d`

## Quick Verification
- VisualEditor: Edit any page; VE should load without “Unable to fetch Parsoid HTML”.
  - Parsoid REST HTML should return 200 when domain is host only:
    - `curl -I 'http://192.168.145.166:9090/rest.php/192.168.145.166/v3/page/html/Main%20Page'` (may 302 to page+revision; follow to 200)
    - Domain with port (e.g. `192.168.145.166:9090`) returns 400 (expected, domain check).
- Mermaid:
  - `{{#mermaid:graph TD; A[Start] --> B{Choice}; B -->|Yes| C; B -->|No| D;}}`
- Markdown:
  - Inline tag: `<markdown># Title</markdown>`
  - `.md`-suffixed pages use Markdown content model.
- SyntaxHighlight:
  - `<syntaxhighlight lang="python">print("ok")</syntaxhighlight>`
- SVG + CJK fonts:
  - Upload an SVG with Traditional Chinese text; thumbnails should render correctly.
- Large image thumbnails:
  - Upload > 12.5 MP; thumbnails should be generated (via `MW_MAX_IMAGE_AREA`).
 - SMW:
  - Visit `Special:SMWAdmin` / `Special:SemanticStatistics`. Create `Property:Has color` with `[[Has type::String]]`, annotate a page `[[Has color::Red]]`, check `Special:Browse/<Page>`.
  - Try `{{#ask: [[Has color::+]] | ?Has color}}`.

## Notes / Follow-ups
- SMW is installed at build; if you see an SMW setup/upgrade page, run `setupStore.php` then `maintenance/update.php --quick`.
- If access URL changes, ensure `.env` `MW_SITE_SERVER` exactly matches (scheme/host/port) and rebuild.

## Environment Variables
- `MW_MAX_IMAGE_AREA` (default 100000000)
- `MW_SVG_MAX_SIZE` (default 4096)
- `MW_SVG_CONVERTER` (`auto` | `rsvg` | `ImageMagick` | `inkscape`)
- `MW_MERMAID_THEME` (`forest` | `default` | `neutral` | `dark`)
- `MW_RL_DEBUG` (0/1): when 1, disables JS minification via `$wgResourceLoaderDebug` to work around client parsing/minify issues

## Helpful REST Checks
- `curl -I 'http://192.168.145.166:9090/rest.php/192.168.145.166/v3/page/html/Main%20Page'` → 302 then 200
- `curl -I 'http://192.168.145.166:9090/rest.php/v1/page/Main_Page'` → 200
