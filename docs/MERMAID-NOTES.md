# Mermaid Integration Notes (MediaWiki 1.41)

This document explains what we changed in the Mermaid extension integration, why we did it, and how to maintain or revert it.

## Overview

- Goal: Enable modern Mermaid v10 diagrams (timeline, mindmap, etc.) and avoid ResourceLoader (RL) minifier issues that broke client scripts.
- Approach: Keep the server/extension PHP intact, but overlay the client assets during the image build so RL serves only a small initializer, while the Mermaid library is loaded separately (locally vendored).

## What Changed

At image build time, we apply a small overlay to the extension’s frontend assets:

- `extension.json` (runtime): We set `ResourceModules.ext.mermaid.packageFiles = [ "resources/ext.mermaid.js" ]` so RL only serves our initializer.
- `resources/ext.mermaid.js`: Replaced with a minimal initializer copied from `patches/ext.mermaid.init.js` in this repo.
  - Loads Mermaid v10.9.1 from `/extensions/Mermaid/resources/mermaid.min.js` (locally vendored, no CDN dependency).
  - Uses `mermaid.run()` (v10) to render `.mermaid` nodes, with delayed initialization and duplicate‑render guards.
- `resources/mermaid.min.js`: Vendored Mermaid v10.9.1 UMD bundle at build time.

The Dockerfile performs these steps so the overlay is reproducible.

## What Didn’t Change

- No changes to the Mermaid extension’s PHP/backend code.
- No fork of the upstream repository; we patch in the container build only.

## Why This Approach

- RL minification and the upstream bundled JS caused parse/runtime errors in the browser.
- Mermaid v9 didn’t support mindmap/timeline; v10 is required for those.
- Overlaying at build time keeps changes minimal, reversible, and centralized in our Dockerfile.

## How It Works

- RL module `ext.mermaid` serves only the initializer (no library). This avoids RL minifying/combining the Mermaid library itself.
- The initializer defers initialization, loads the vendored Mermaid v10.9.1, then renders using `mermaid.run()` (recommended in v10, especially for mindmap/timeline).
- The initializer adds a simple render lock and removes prior child graphs to prevent duplicates on repeated hooks (e.g., VE or preview cycles).

Files of interest:
- Initializer source: `patches/ext.mermaid.init.js`
- Vendored library (in container): `/var/www/html/extensions/Mermaid/resources/mermaid.min.js`
- Docker overlay: `Dockerfile.mediawiki` (look for the Mermaid patch block)

## Versioning and Updates

- When the Mermaid extension is updated upstream, our Docker build will reapply the overlay. If upstream changes file paths or module names, the patch block may require tweaks.
- To upgrade Mermaid:
  1. Change the version URL in the Dockerfile’s `curl -o mermaid.min.js ...` line.
  2. Rebuild: `docker compose up -d --build --force-recreate`.

## Reverting to Upstream Packaging

If you want to run the extension exactly as upstream ships it:
- Remove the Mermaid patch block from `Dockerfile.mediawiki` (the COPY + two RUN steps that alter `extension.json` and `resources/ext.mermaid.js`).
- Rebuild the image. RL will then serve upstream `packageFiles` (including the library) and you may hit the minifier/runtime issues again.

## Alternative: Custom RL Module (No File Overlay)

Instead of modifying the extension files in the image, you could:
- Leave `extension.json` untouched.
- Add a custom RL module (e.g., `ext.mermaid-init`) via `LocalSettings.php` or a small maintenance extension that:
  - Exposes `patches/ext.mermaid.init.js` as a ResourceLoader module.
  - Loads that module on all content pages.

Trade‑offs: Slightly more plumbing in LocalSettings/Admin code, but the upstream extension folder remains pristine.

## Verify

- Special:Version → Extensions lists “Mermaid”.
- Flowchart/sequence render as usual.
- Timeline/mindmap render with v10.
- No double rendering on repeated hook events (edit/preview cycles).

## Troubleshooting

- Mindmap: Ensure the block starts at column 1 (no list bullets) and has exactly one root under the `mindmap` header. Use spaces for indentation.
- If the library fails to load, confirm the file exists at `/extensions/Mermaid/resources/mermaid.min.js` inside the container.
- As a last resort, set `MW_RL_DEBUG=1` in `.env` and rebuild to disable RL minification globally during troubleshooting.

