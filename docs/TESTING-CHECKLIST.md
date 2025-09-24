# MediaWiki 1.44 Testing Checklist

This document provides a comprehensive testing checklist to verify all functionality works correctly after MediaWiki 1.44 upgrade and extension compatibility fixes.

## Test Environment Setup

### Prerequisites
- Clean Docker environment
- No existing data in `./data/` directory
- No existing Docker volumes or containers

### Start From Scratch Test
```bash
# 1. Clean everything
rm -rf ./data/*
docker compose down -v --rmi all --remove-orphans

# 2. Build and start fresh
docker compose up -d --build

# 3. Wait for initialization
docker compose logs -f mediawiki
```

## Core MediaWiki Functionality

### ✅ Basic Wiki Operations
- [ ] Main page loads without errors
- [ ] User can register/login
- [ ] Edit pages (source editor)
- [ ] Save page changes
- [ ] View page history
- [ ] Upload files (if enabled)

### ✅ Visual Editor
- [ ] Visual Editor loads (`?veaction=edit`)
- [ ] No ResourceLoader 500 errors
- [ ] Can edit and save pages
- [ ] Toolbar functions work

### ✅ Skins and UI
- [ ] Vector 2022 skin displays correctly
- [ ] Navigation menus work
- [ ] Search functionality
- [ ] Special pages accessible

## Extension Testing

### ✅ WikiMarkdown Extension
Test with this content:
```wikitext
<markdown>
## Test Markdown Section

This is a **bold** and *italic* text test.

- List item 1
- List item 2

[External link](https://example.com)

### Sub-heading
Regular text content.
</markdown>
```

**Expected Results:**
- [ ] Markdown renders as HTML
- [ ] Bold/italic formatting works
- [ ] Lists display correctly
- [ ] External links are functional
- [ ] Headings generate proper HTML with IDs
- [ ] Content wrapped in `mw-markdown` CSS class

### ✅ Mermaid Extension
Test with this content:
```wikitext
{{#mermaid:graph TD
A[Start] --> B{Decision}
B -->|Yes| C[Action 1]
B -->|No| D[Action 2]
C --> E[End]
D --> E
}}

{{#mermaid:sequenceDiagram
participant Alice
participant Bob
Alice->Bob: Hello Bob
Bob-->Alice: Hello Alice
}}
```

**Expected Results:**
- [ ] Graph diagrams render
- [ ] Sequence diagrams render
- [ ] No "Class Html not found" errors
- [ ] Proper HTML structure with `ext-mermaid` class
- [ ] Data attributes contain diagram definition

### ✅ Semantic MediaWiki
- [ ] Special:SMWAdmin accessible
- [ ] No setup/upgrade warnings
- [ ] Can create semantic properties
- [ ] Semantic queries work
- [ ] Ask queries return results

### ✅ Other Core Extensions
- [ ] **VisualEditor**: Loads and functions
- [ ] **WikiEditor**: Source editing toolbar
- [ ] **CodeEditor**: Syntax highlighting in edit mode
- [ ] **SyntaxHighlight**: Code blocks render with highlighting
- [ ] **MultimediaViewer**: Image viewing
- [ ] **PdfHandler**: PDF file handling
- [ ] **MsUpload**: File upload functionality

## Database and Legacy Support

### ✅ Fresh Installation
- [ ] Clean install completes successfully
- [ ] All extensions load without errors
- [ ] Database schema created correctly

### ✅ Legacy Database Upgrade (if applicable)
- [ ] Pre-1.39 databases upgrade via intermediate step
- [ ] 1.39→1.44 upgrade works
- [ ] All data preserved after upgrade
- [ ] Extensions work after upgrade

## Performance and Stability

### ✅ Error Checking
- [ ] No PHP fatal errors in logs
- [ ] No ResourceLoader failures
- [ ] No database connection issues
- [ ] No extension loading failures

### ✅ ResourceLoader
- [ ] JavaScript loads correctly
- [ ] CSS styles apply properly
- [ ] No 500 errors in browser console
- [ ] Minification works (if enabled)

## Chinese/Unicode Support

### ✅ Internationalization
Test with Chinese content:
```wikitext
<markdown>
## 中文測試

這是一個**粗體**和*斜體*的測試。

- 列表項目 1
- 列表項目 2

[外部連結](https://example.com)
</markdown>

{{#mermaid:graph TD
開始[開始] --> 決策{決策}
決策 -->|是| 動作1[動作1]
決策 -->|否| 動作2[動作2]
}}
```

**Expected Results:**
- [ ] Chinese characters display correctly
- [ ] Markdown formatting works with Chinese text
- [ ] Mermaid diagrams support Chinese labels
- [ ] File namespace aliases work (`[[檔案:...]]`, `[[文件:...]]`)

## Final Verification

### ✅ Complete System Test
- [ ] All pages load without errors
- [ ] All extensions function correctly
- [ ] No error messages in logs
- [ ] Performance is acceptable
- [ ] User experience is smooth

### ✅ Documentation
- [ ] README.md reflects current functionality
- [ ] Extension compatibility documented
- [ ] Troubleshooting information updated

## Test Results Log

### Date: ___________
### Tester: ___________
### Environment: ___________

**Overall Status:** ⬜ PASS ⬜ FAIL ⬜ PARTIAL

**Notes:**
```
[Add any issues found, performance observations, or other notes]
```

**Failed Tests:**
```
[List any failed test items with details]
```

**Recommendations:**
```
[Any suggested improvements or follow-up actions]
```