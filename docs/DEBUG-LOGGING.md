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

