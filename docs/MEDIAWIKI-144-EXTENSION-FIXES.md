# MediaWiki 1.44 Extension Compatibility Fixes

This document outlines the fixes applied to make various MediaWiki extensions compatible with MediaWiki 1.44.0 LTS.

## Overview

MediaWiki 1.44 introduced namespace changes for several core classes, breaking compatibility with extensions written for older versions. This document covers the specific fixes required.

## WikiMarkdown Extension

### Issues Fixed

1. **ResourceLoader Class Namespacing**
   - `ResourceLoaderFileModule` → `MediaWiki\ResourceLoader\FileModule`
   - `ResourceLoaderContext` → `MediaWiki\ResourceLoader\Context`

2. **Parser Class Namespacing**
   - `Parser` → `MediaWiki\Parser\Parser`

3. **Linker Class Namespacing**
   - `Linker` → `MediaWiki\Linker\Linker`

4. **Html Class Namespacing**
   - `Html` → `MediaWiki\Html\Html`

5. **Deprecated Method Replacement**
   - `Linker::makeHeadline()` method removed
   - Replaced with direct HTML generation: `<h{level} id="{anchor}">{text}</h{level}>`

### Files Modified

- `includes/WikiMarkdown.php`
- `includes/ResourceLoaderWikiMarkdownVisualEditorModule.php`

### Implementation

The fixes are automatically applied during Docker image build via:
- `patches/WikiMarkdown-mw144-complete-compatibility.patch`

### Testing

✅ **Verified Working:**
- Chinese/Unicode text rendering
- Bold and italic formatting
- External links
- Header generation with proper IDs
- CSS class wrapping (`mw-markdown`)

## Mermaid Extension

### Issues Identified

1. **Html Class Namespacing**
   - Error: `Class "Html" not found` in `MermaidParserFunction.php:84`
   - Fix required: `Html` → `MediaWiki\Html\Html`

### Status
🔧 **In Progress** - Fix being implemented

## Future Extension Compatibility

### Common MediaWiki 1.44 Namespace Changes

Extensions may need updates for these class relocations:

```php
// OLD → NEW
Parser                    → MediaWiki\Parser\Parser
Html                     → MediaWiki\Html\Html
Linker                   → MediaWiki\Linker\Linker
ResourceLoaderFileModule → MediaWiki\ResourceLoader\FileModule
ResourceLoaderContext    → MediaWiki\ResourceLoader\Context
Title                    → MediaWiki\Title\Title
User                     → MediaWiki\User\User
```

### Testing Approach

1. Enable detailed error reporting: `$wgShowExceptionDetails = true;`
2. Test extension functionality systematically
3. Check for "Class not found" errors
4. Apply namespace fixes
5. Verify functionality works as expected

## Changelog

### 2025-09-24
- ✅ Fixed WikiMarkdown ResourceLoader compatibility
- ✅ Fixed WikiMarkdown Parser, Linker, Html namespace issues
- ✅ Replaced deprecated makeHeadline method
- 🔧 Started Mermaid extension Html namespace fix

## References

- [MediaWiki 1.44 Release Notes](https://www.mediawiki.org/wiki/Release_notes/1.44)
- [WikiMarkdown Extension](https://github.com/kuenzign/WikiMarkdown)
- [Mermaid Extension](https://github.com/SemanticMediaWiki/Mermaid)