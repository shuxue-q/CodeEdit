# Markdown preview libraries

These files are vendored so Markdown preview works offline. CodeEdit's own code is MIT;
the libraries below keep their own licenses.

| Library | Version | License | Project |
| --- | --- | --- | --- |
| markdown-it | 14.1.0 | MIT | https://github.com/markdown-it/markdown-it |
| DOMPurify | 3.2.6 | Apache-2.0 OR MPL-2.0 | https://github.com/cure53/DOMPurify |
| highlight.js | 11.11.1 | BSD-3-Clause | https://github.com/highlightjs/highlight.js |
| github-markdown-css | 5.8.1 | MIT | https://github.com/sindresorhus/github-markdown-css |
| KaTeX | 0.16.25 | MIT | https://github.com/KaTeX/KaTeX |
| Mermaid | 11.12.0 | MIT | https://github.com/mermaid-js/mermaid |

KaTeX's `katex.min.css` in this folder keeps the WOFF2 font sources and drops the WOFF and
TTF fallbacks. Font URLs point at the files beside the stylesheet, because the app target
copies resources without the `fonts/` directory. The WOFF2 files are KaTeX's fonts, under
the same MIT license.
License headers in the minified scripts remain in those files.
