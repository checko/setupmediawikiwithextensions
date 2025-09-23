# Debug Log — Mermaid Rendering

Date: 2025-08-27 to 2025-08-28
Branch: `settings-update`

## Symptoms
- Mermaid diagrams not rendering; console shows minifier syntax errors (e.g., “Illegal newline after throw”) when `ext.mermaid` is served through ResourceLoader.
- Timeline/mindmap reported “Syntax error in graph” on v9 builds.
- Later, mindmap parsed as multiple roots when blocks were indented by list bullets.

## Root Causes
- Upstream Mermaid v6 extension ships modern JS that can trip RL minification.
- Mermaid v9 didn’t support timeline/mindmap; v10 required.
- Placing Mermaid blocks inside list items alters indentation; mindmap needs a single root and strict indentation.

## Fixes Applied
1. Keep RL module small; load Mermaid JS separately:
   - RL `ext.mermaid` now serves only an initializer file.
   - Vendored Mermaid v10.9.1 at `/extensions/Mermaid/resources/mermaid.min.js` to avoid CDN dependence.
2. Initializer (`patches/ext.mermaid.init.js`):
   - Defers init (`startOnLoad: false`) and runs after MediaWiki hook.
   - Uses `mermaid.run()` (v10) on a `.mermaid` child node; falls back to `render()` when needed.
   - Adds render locks (`data-mermaid-status`) and cleans prior child graph nodes to prevent duplicates.
3. Docs updated:
   - README/extension-checks include v10 diagrams and mindmap/timeline examples.
   - Tips: start blocks at column 1; avoid list bullets; mindmap must have exactly one root.
4. Optional debug: `MW_RL_DEBUG=1` to disable JS minification if needed.

## Verification
- Flowchart, sequence, class, state diagrams render.
- Timeline renders with v10 runner.
- Mindmap renders when blocks start at column 1 with single root.

## Known Notes
- If CDN must be used instead of vendored JS, switch initializer source to the CDN URL.
- Some older browsers may require additional polyfills for v10 runner; standard modern browsers are OK.

---

# Debug Log — MediaWiki 1.44.0 LTS Upgrade

Date: 2025-09-23
Branch: `upgrade-mediawiki-1.44`

## Symptoms
- TypeError exceptions when accessing login/navigation pages: "WikiMarkdown::onContentHandlerDefaultModelFor(): Argument #1 ($title) must be of type Title, MediaWiki\Title\Title given"
- SemanticMediaWiki fatal errors: "Could not check compatibility between SMW\MediaWiki\Search\ExtendedSearchEngine::getTextFromContent(Title $t, ?Content $c = null) and SearchEngine::getTextFromContent(MediaWiki\Title\Title $t, ?MediaWiki\Content\Content $c = null)"
- Extensions failing to load due to namespace/class changes in MediaWiki 1.44

## Root Causes
1. **WikiMarkdown Title Class Issue**: MediaWiki 1.44 moved `Title` class to `MediaWiki\Title\Title` namespace, breaking WikiMarkdown's function signatures
2. **SemanticMediaWiki Version Incompatibility**: Project used SMW ~4.1 (version 4.2.0), but MediaWiki 1.44 requires SMW 6.0+ for compatibility
3. **Extension Branch Mismatches**: Some extensions needed REL1_44 branches instead of REL1_41

## Fixes Applied
1. **WikiMarkdown Compatibility Patch**:
   - Created `patches/WikiMarkdown-mw144-title-compatibility.patch`
   - Updated function signatures: `Title $title` → `\MediaWiki\Title\Title $title`
   - Fixed `onContentHandlerDefaultModelFor()` and `onCodeEditorGetPageLanguage()` functions
   - Applied automatically during Docker build process

2. **SemanticMediaWiki Version Upgrade**:
   - Updated from `mediawiki/semantic-media-wiki:~4.1` to `~6.0`
   - Updated in `Dockerfile.mediawiki` and `scripts/init-mediawiki.sh`
   - SemanticMediaWiki 6.0.1 now compatible with MediaWiki 1.44.0 LTS

3. **Extension Branch Updates**:
   - Updated extension clones from REL1_41 to REL1_44 branches
   - Updated legacy upgrade bundle from MediaWiki 1.35.13 to 1.39.8

## Verification
- MediaWiki 1.44.0 LTS loads successfully
- All extensions working: SemanticMediaWiki 6.0.1, WikiMarkdown 1.1.3, Mermaid, etc.
- Login/navigation pages functional without errors
- Special:Version shows all extensions loaded correctly

## Known Notes
- SemanticMediaWiki requires version 6.0+ for MediaWiki 1.44 compatibility
- WikiMarkdown patch handles Title class namespace changes automatically
- All fixes integrated into automated build process for future deployments

