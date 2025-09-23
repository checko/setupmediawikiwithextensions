# Extension Download Links

This stack enables the following MediaWiki extensions. The table lists the upstream source for each extension and how the code is pulled into the image or enabled at runtime.

| Extension | Source URL | How this project obtains it |
| --- | --- | --- |
| CodeEditor | https://github.com/wikimedia/mediawiki-extensions-CodeEditor | Bundled with the upstream `mediawiki:1.44` image and enabled in `scripts/init-mediawiki.sh`.
| Mermaid | https://github.com/SemanticMediaWiki/Mermaid | Cloned during image build in `Dockerfile.mediawiki:44`; patched and configured in `scripts/init-mediawiki.sh`.
| MsUpload | https://github.com/wikimedia/mediawiki-extensions-MsUpload | Cloned with branch `REL1_44` in `Dockerfile.mediawiki:32` and on container start in `scripts/init-mediawiki.sh:367` if missing.
| MultimediaViewer | https://github.com/wikimedia/mediawiki-extensions-MultimediaViewer | Bundled with the upstream `mediawiki:1.44` image and enabled in `scripts/init-mediawiki.sh`.
| Parsoid | https://packagist.org/packages/wikimedia/parsoid | Bundled with the upstream `mediawiki:1.44` image as a Composer vendor package; no extra download occurs. The init script only ensures `wfLoadExtension( 'Parsoid', "$IP/vendor/wikimedia/parsoid/extension.json" );`.
| PdfHandler | https://github.com/wikimedia/mediawiki-extensions-PdfHandler | Bundled with the upstream `mediawiki:1.44` image and enabled in `scripts/init-mediawiki.sh`.
| SemanticMediaWiki | https://github.com/SemanticMediaWiki/SemanticMediaWiki | Installed via Composer (`mediawiki/semantic-media-wiki:~6.0`) in `Dockerfile.mediawiki:82` and `scripts/init-mediawiki.sh:438,506`. Version 6.0+ required for MediaWiki 1.44 compatibility.
| SyntaxHighlight_GeSHi | https://github.com/wikimedia/mediawiki-extensions-SyntaxHighlight_GeSHi | Cloned with branch `REL1_44` in `Dockerfile.mediawiki:38`.
| TimedMediaHandler | https://github.com/wikimedia/mediawiki-extensions-TimedMediaHandler | Cloned with branch `REL1_44` in `Dockerfile.mediawiki:35`.
| VisualEditor | https://github.com/wikimedia/mediawiki-extensions-VisualEditor | Bundled with the upstream `mediawiki:1.44` image; VisualEditor is enabled in `scripts/init-mediawiki.sh` alongside Parsoid.
| WikiEditor | https://github.com/wikimedia/mediawiki-extensions-WikiEditor | Bundled with the upstream `mediawiki:1.44` image and enabled in `scripts/init-mediawiki.sh`.
| WikiMarkdown | https://github.com/kuenzign/WikiMarkdown | Cloned in `Dockerfile.mediawiki:41`, Composer dependencies installed during build, and patched for MediaWiki 1.44 compatibility via `patches/WikiMarkdown-mw144-title-compatibility.patch`.
