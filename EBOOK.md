---
layout: default
title: Ebook Ideas
permalink: /ebook/
---

# EBOOK IDEAS

Goal: make this repository read like an ebook while staying practical for operators.

## Suggested book structure
- Front matter: title page, edition, changelog link, how to use this book.
- Part I: Foundations (stack overview, safety rules, environment setup).
- Part II: Core workflows (provision, deploy, backups, restores, monitoring).
- Part III: Operations playbook (incidents, migrations, performance).
- Part IV: Advanced topics (multi-env, scaling, security hardening).
- Appendices: glossary, command reference, troubleshooting index.

## Concrete changes to make it feel like an ebook
- Add a `BOOK.md` or `TOC.md` with a curated reading path and chapter order.
- Use consistent chapter numbering in headings (e.g., "Chapter 3: Backups").
- Add short chapter intros with goals, prerequisites, and time estimates.
- Include "Key takeaways" and "Next steps" at the end of each chapter.
- Create sidebars for "Caution", "Tip", and "Gotcha" blocks.
- Add a glossary that defines Trellis, Bedrock, vault, etc.
- Add a command index: "ansible-playbook", "wp", "rsync", "ssh".
- Use consistent diagrams (Mermaid) for flows and architecture.

## Mapping existing docs into a book
- `README.md` becomes the "Preface" and "How to use this book".
- `trellis/`, `wp-cli/`, and `nginx/` become core chapters with sub-sections.
- `troubleshooting/` becomes an appendix indexed by symptoms.
- `CHANGELOG.md` becomes "Edition history".

## Chapter template (example)
- Title and purpose
- Prerequisites
- Safety checklist
- Step-by-step workflow (with dry-run first)
- Verification steps
- Cleanup / rollback
- Troubleshooting notes
- References / related chapters

## Reading paths
- "New operator": setup -> backups -> monitoring -> incident response
- "Migration": inventory -> backup -> dry-run -> cutover -> verify
- "Performance": caching -> image optimization -> monitoring

## Visual and format ideas
- Add callout styling using Markdown blockquotes with labels.
- Use diagrams to show data flow and failure points.
- Provide "before/after" snippets for config changes.
- Include small, realistic case studies for each major workflow.
- Add periodic "You should know" recap sections.

## Tooling options (if desired)
- Generate a static ebook with mdBook or MkDocs.
- Keep markdown as the source of truth; export to PDF/EPUB.
- Use a `docs/` build step later, but keep repo structure intact.

## Next candidate chapters to write
- Chapter: Safe backup and restore (Trellis + wp-cli).
- Chapter: Deployment checklist and rollback.
- Chapter: Monitoring signals and alert triage.
- Chapter: Image optimization pipeline.

---

## Jekyll Implementation Guide

### Current Implementation Status

✅ **Completed:**
- Basic Jekyll setup with `_config.yml`
- Default layout with navigation (`_layouts/default.html`)
- Book landing page (`BOOK.md`)
- Table of contents (`TOC.md`)
- Book-themed styling with serif fonts and warm colors (`assets/main.css`)
- Reading paths for different user types
- Enhanced Jekyll configuration with Gemfile and plugins (2026-01-15)
- Ruby 4.0 compatibility (2026-01-15)

🔨 **Needs improvement:**
- No chapter-specific layouts
- Missing callout boxes for tips/warnings/cautions
- No chapter navigation (prev/next)
- No search functionality
- No print/PDF export styles
- No reading time estimates
- No progress tracking

---

## Improvement Roadmap

### 1. Enhanced Jekyll Configuration ✅ **COMPLETED**

**Status:** Implemented on 2026-01-15

**Changes made:**
- Created `Gemfile` with Jekyll 4.4 and required plugins
- Added Ruby 4.0 compatibility gems (logger, csv, base64)
- Configured `_config.yml` with metadata and plugins
- Successfully building with `bundle exec jekyll build`

**Original plan:** Expand `_config.yml` with better metadata and plugins:

```yaml
title: WP OPS - WordPress Operations Handbook
description: Comprehensive guide for WordPress server management with Trellis, WP-CLI, and Nginx
author: Your Name
baseurl: "" # for GitHub Pages: /wp-ops
url: "" # for GitHub Pages: https://yourusername.github.io

markdown: kramdown
kramdown:
  input: GFM
  syntax_highlighter: rouge
  syntax_highlighter_opts:
    css_class: 'highlight'

exclude:
  - trellis/backup/*.yml
  - trellis/monitoring/*.yml
  - .git
  - .gitignore
  - Gemfile
  - Gemfile.lock
  - vendor/

collections:
  chapters:
    output: true
    permalink: /chapters/:name/

plugins:
  - jekyll-relative-links
  - jekyll-toc
```

**Benefits:**
- Better SEO with description and author
- GitHub Pages compatibility
- Syntax highlighting for code blocks
- Collections for organized chapter structure
- Plugin support for auto-linking and TOC generation

---

### 2. Chapter Layout System

Create `_layouts/chapter.html` for consistent chapter structure:

```html
---
layout: default
---
<article class="chapter">
  <div class="chapter-meta">
    {% if page.chapter_number %}
      <span class="chapter-number">Chapter {{ page.chapter_number }}</span>
    {% endif %}
    {% if page.reading_time %}
      <span class="reading-time">{{ page.reading_time }} min read</span>
    {% endif %}
  </div>

  <h1>{{ page.title }}</h1>

  {% if page.prerequisites %}
  <div class="callout callout-prerequisites">
    <h3>Prerequisites</h3>
    <ul>
    {% for prereq in page.prerequisites %}
      <li>{{ prereq }}</li>
    {% endfor %}
    </ul>
  </div>
  {% endif %}

  {{ content }}

  {% if page.key_takeaways %}
  <div class="callout callout-summary">
    <h3>Key Takeaways</h3>
    <ul>
    {% for takeaway in page.key_takeaways %}
      <li>{{ takeaway }}</li>
    {% endfor %}
    </ul>
  </div>
  {% endif %}

  <nav class="chapter-nav">
    {% if page.previous_chapter %}
      <a href="{{ page.previous_chapter }}" class="prev">← Previous: {{ page.previous_title }}</a>
    {% endif %}
    {% if page.next_chapter %}
      <a href="{{ page.next_chapter }}" class="next">Next: {{ page.next_title }} →</a>
    {% endif %}
  </nav>
</article>
```

**Chapter front matter example:**

```yaml
---
layout: chapter
title: "Provisioning Environments"
chapter_number: 3
reading_time: 30
prerequisites:
  - "Chapter 1: Operating Principles"
  - "Chapter 2: Command Helpers"
key_takeaways:
  - "Trellis provisioning requires site name matching wordpress_sites.yml"
  - "Always test on staging before production"
  - "PHP upgrades need specific tags: php, nginx, wordpress-setup, users, memcached"
previous_chapter: "/chapters/command-helpers/"
previous_title: "Command Helpers"
next_chapter: "/chapters/backups/"
next_title: "Backups and Restores"
---
```

---

### 3. Callout Box Styling

Add these CSS classes to `assets/main.css` for visual callouts:

```css
/* Callout boxes for tips, warnings, cautions */
.callout {
  margin: 1.5em 0;
  padding: 1em 1.2em;
  border-left: 4px solid var(--accent);
  background: #f9f6f1;
  border-radius: 4px;
}

.callout h3 {
  margin-top: 0;
  font-size: 1rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 700;
}

.callout-tip {
  border-left-color: #4a7c59;
  background: #f0f8f4;
}

.callout-tip h3 {
  color: #4a7c59;
}

.callout-warning {
  border-left-color: #d97706;
  background: #fffbeb;
}

.callout-warning h3 {
  color: #d97706;
}

.callout-danger {
  border-left-color: #dc2626;
  background: #fef2f2;
}

.callout-danger h3 {
  color: #dc2626;
}

.callout-prerequisites {
  border-left-color: #6366f1;
  background: #eef2ff;
}

.callout-prerequisites h3 {
  color: #6366f1;
}

.callout-summary {
  border-left-color: #059669;
  background: #ecfdf5;
}

.callout-summary h3 {
  color: #059669;
}
```

**Usage in markdown:**

```html
<div class="callout callout-warning">
<h3>Warning</h3>
Never run database operations without a backup first.
</div>

<div class="callout callout-tip">
<h3>Tip</h3>
Use `--dry-run` flag to test commands before executing.
</div>

<div class="callout callout-danger">
<h3>Danger</h3>
This operation cannot be undone. Ensure you have verified backups.
</div>
```

---

### 4. Chapter Navigation Styling

Add chapter navigation CSS to `assets/main.css`:

```css
/* Chapter navigation */
.chapter-nav {
  display: flex;
  justify-content: space-between;
  margin-top: 3em;
  padding-top: 2em;
  border-top: 2px solid var(--line);
  gap: 1em;
}

.chapter-nav a {
  padding: 0.8em 1.4em;
  background: var(--paper);
  border: 1px solid var(--line);
  border-radius: 6px;
  font-weight: 600;
  transition: all 0.2s ease;
  flex: 1;
  text-align: center;
}

.chapter-nav a:hover {
  background: var(--bg);
  border-color: var(--accent);
  text-decoration: none;
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(45, 34, 20, 0.1);
}

.chapter-nav .prev::before {
  content: "← ";
}

.chapter-nav .next::after {
  content: " →";
}

/* Chapter metadata */
.chapter-meta {
  display: flex;
  gap: 1.5em;
  margin-bottom: 1.5em;
  padding-bottom: 1em;
  border-bottom: 1px solid var(--line);
  font-size: 0.85rem;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 600;
}

.chapter-number {
  color: var(--accent);
}
```

---

### 5. Table of Contents Enhancement

Create `_data/book_structure.yml` for structured TOC data:

```yaml
- title: "Part I: Foundations"
  chapters:
    - number: 1
      title: "Operating Principles and Safety Basics"
      url: "/README.html"
      reading_time: 15

    - number: 2
      title: "Command Helpers and Doc Conventions"
      url: "/CLAUDE.html"
      reading_time: 10

- title: "Part II: Trellis Operations"
  chapters:
    - number: 3
      title: "Provisioning Environments"
      url: "/trellis/provision/"
      reading_time: 30

    - number: 4
      title: "Backups and Restores"
      url: "/trellis/backup/"
      reading_time: 25

    - number: 5
      title: "Monitoring and Alerting"
      url: "/trellis/monitoring/"
      reading_time: 20

    - number: 6
      title: "Security Hardening"
      url: "/trellis/security/"
      reading_time: 35

    - number: 7
      title: "Updating Trellis"
      url: "/trellis/updater/"
      reading_time: 15

- title: "Part III: WP-CLI Workflows"
  chapters:
    - number: 8
      title: "Content Creation"
      url: "/wp-cli/content-creation/"
      reading_time: 20

    - number: 9
      title: "Diagnostics"
      url: "/wp-cli/diagnostics/"
      reading_time: 15

    - number: 10
      title: "Migration"
      url: "/wp-cli/migration/"
      reading_time: 40

    - number: 11
      title: "Security Checks"
      url: "/wp-cli/security/"
      reading_time: 25

- title: "Part IV: Nginx Patterns"
  chapters:
    - number: 12
      title: "Browser Caching"
      url: "/nginx/browser-caching/"
      reading_time: 12

    - number: 13
      title: "Image Optimization"
      url: "/nginx/image-optimization/"
      reading_time: 18

    - number: 14
      title: "Redirects"
      url: "/nginx/redirects/"
      reading_time: 15

- title: "Part V: WordPress Utilities"
  chapters:
    - number: 15
      title: "Age Verification"
      url: "/wordpress-utilities/age-verification/"
      reading_time: 10

    - number: 16
      title: "Analytics"
      url: "/wordpress-utilities/analytics/"
      reading_time: 8

    - number: 17
      title: "Speed Optimization"
      url: "/wordpress-utilities/speed-optimization/"
      reading_time: 12

- title: "Part VI: Scripts and Automation"
  chapters:
    - number: 18
      title: "Utility Scripts Overview"
      url: "/scripts/"
      reading_time: 10

    - number: 19
      title: "Release and Theme Sync"
      url: "/scripts/"
      reading_time: 15

    - number: 20
      title: "PR Helper Script"
      url: "/scripts/"
      reading_time: 8
```

**Enhanced TOC page:**

```markdown
---
layout: default
title: Table of Contents
permalink: /toc/
---

# Table of Contents

<div class="toc-summary">
  <p><strong>Total chapters:</strong> 20 | <strong>Total reading time:</strong> ~6 hours</p>
</div>

{% for part in site.data.book_structure %}

## {{ part.title }}

<div class="chapter-list">
{% for chapter in part.chapters %}
  <div class="chapter-item">
    <span class="chapter-number">{{ chapter.number }}</span>
    <a href="{{ chapter.url }}">{{ chapter.title }}</a>
    <span class="chapter-time">{{ chapter.reading_time }} min</span>
  </div>
{% endfor %}
</div>

{% endfor %}

## Appendices

- **Appendix A:** [Troubleshooting Index](/troubleshooting/)
- **Appendix B:** [Mail Issues](/troubleshooting/MAIL.html)
- **Appendix C:** [MariaDB Issues](/troubleshooting/MariaDB.html)
- **Appendix D:** [OOM Issues](/troubleshooting/OOM.html)
- **Appendix E:** [PHP-FPM Issues](/troubleshooting/PHP-FPM.html)
- **Appendix F:** [License](/LICENSE.html)
```

**TOC styling CSS:**

```css
.toc-summary {
  background: var(--bg);
  padding: 1em 1.5em;
  border-radius: 6px;
  margin-bottom: 2em;
  border-left: 4px solid var(--accent);
}

.chapter-list {
  margin: 1em 0 2em;
}

.chapter-item {
  display: flex;
  align-items: baseline;
  gap: 0.8em;
  padding: 0.6em 0;
  border-bottom: 1px solid var(--line);
}

.chapter-item:last-child {
  border-bottom: none;
}

.chapter-item .chapter-number {
  font-weight: 700;
  color: var(--accent);
  min-width: 2em;
}

.chapter-item a {
  flex: 1;
  font-weight: 500;
}

.chapter-item .chapter-time {
  font-size: 0.85rem;
  color: var(--muted);
  font-style: italic;
}
```

---

### 6. Search Functionality

Add simple client-side search to `_layouts/default.html`:

```html
<header class="site-header">
  <div class="container">
    <a class="site-title" href="{{ "/" | relative_url }}">{{ site.title }}</a>

    <div class="search-container">
      <input type="search" id="doc-search" placeholder="Search documentation..." aria-label="Search">
    </div>

    <nav class="site-nav">
      <a href="{{ "/" | relative_url }}">Book</a>
      <a href="{{ "/toc/" | relative_url }}">TOC</a>
      <a href="{{ "/ebook/" | relative_url }}">Ideas</a>
      <a href="{{ "/README.html" | relative_url }}">README</a>
    </nav>
  </div>
</header>
```

**Search styling:**

```css
.search-container {
  margin: 1em 0;
}

#doc-search {
  width: 100%;
  max-width: 400px;
  padding: 0.6em 1em;
  border: 1px solid var(--line);
  border-radius: 6px;
  background: var(--paper);
  font-family: inherit;
  font-size: 0.95rem;
}

#doc-search:focus {
  outline: 2px solid var(--accent);
  outline-offset: 2px;
}
```

**For advanced search**, consider adding [Lunr.js](https://lunrjs.com/) or [Algolia DocSearch](https://docsearch.algolia.com/).

---

### 7. Print and PDF Export Styles

Add print-specific styles to `assets/main.css`:

```css
/* Print styles for PDF export */
@media print {
  /* Hide navigation elements */
  .site-header,
  .site-footer,
  .chapter-nav,
  .search-container {
    display: none;
  }

  /* Optimize content for print */
  body {
    background: white;
    color: black;
    font-size: 11pt;
  }

  .content {
    box-shadow: none;
    border: none;
    margin: 0;
    padding: 0;
  }

  /* Make links visible */
  a {
    color: black;
    text-decoration: underline;
  }

  /* Show URLs after links */
  a[href^="http"]::after {
    content: " (" attr(href) ")";
    font-size: 0.8em;
    color: #666;
  }

  /* Avoid breaking inside code blocks */
  pre, code {
    page-break-inside: avoid;
    background: #f5f5f5;
    border: 1px solid #ddd;
  }

  /* Page breaks */
  h1, h2 {
    page-break-after: avoid;
  }

  .callout {
    page-break-inside: avoid;
  }

  /* Chapter starts on new page */
  .chapter {
    page-break-before: always;
  }

  .chapter:first-child {
    page-break-before: avoid;
  }
}
```

**PDF generation options:**

1. **Browser print:** Use Chrome's "Save as PDF" with print styles
2. **wkhtmltopdf:** Command-line HTML to PDF converter
3. **Prince XML:** Professional PDF generation (paid)
4. **Pandoc:** Convert markdown directly to PDF/EPUB

```bash
# Example: Generate PDF with wkhtmltopdf
wkhtmltopdf --print-media-type \
  --enable-local-file-access \
  http://localhost:4000 \
  wp-ops-handbook.pdf
```

---

### 8. Code Block Enhancements

Add copy-to-clipboard functionality for code blocks:

```html
<!-- Add to _layouts/default.html before </body> -->
<script>
  document.addEventListener('DOMContentLoaded', function() {
    document.querySelectorAll('pre code').forEach(function(block) {
      const button = document.createElement('button');
      button.className = 'copy-button';
      button.textContent = 'Copy';
      button.setAttribute('aria-label', 'Copy code to clipboard');

      block.parentElement.style.position = 'relative';
      block.parentElement.appendChild(button);

      button.addEventListener('click', function() {
        navigator.clipboard.writeText(block.textContent).then(function() {
          button.textContent = 'Copied!';
          setTimeout(function() {
            button.textContent = 'Copy';
          }, 2000);
        });
      });
    });
  });
</script>
```

**Copy button styling:**

```css
pre {
  position: relative;
}

.copy-button {
  position: absolute;
  top: 8px;
  right: 8px;
  padding: 0.4em 0.8em;
  background: var(--accent);
  color: white;
  border: none;
  border-radius: 4px;
  font-size: 0.8rem;
  cursor: pointer;
  opacity: 0;
  transition: opacity 0.2s;
}

pre:hover .copy-button {
  opacity: 1;
}

.copy-button:hover {
  background: var(--ink);
}
```

---

### 9. Breadcrumb Navigation

Add breadcrumbs to show location in book structure:

```html
<!-- Add to _layouts/chapter.html after <article class="chapter"> -->
<nav class="breadcrumb" aria-label="Breadcrumb">
  <ol>
    <li><a href="/">Home</a></li>
    {% if page.part %}
    <li><a href="{{ page.part_url }}">{{ page.part }}</a></li>
    {% endif %}
    <li aria-current="page">{{ page.title }}</li>
  </ol>
</nav>
```

**Breadcrumb styling:**

```css
.breadcrumb {
  margin-bottom: 1.5em;
  font-size: 0.9rem;
}

.breadcrumb ol {
  list-style: none;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.5em;
}

.breadcrumb li::after {
  content: "/";
  margin-left: 0.5em;
  color: var(--muted);
}

.breadcrumb li:last-child::after {
  content: "";
}

.breadcrumb a {
  color: var(--muted);
}

.breadcrumb a:hover {
  color: var(--accent);
}

.breadcrumb [aria-current="page"] {
  color: var(--ink);
  font-weight: 600;
}
```

---

### 10. Dark Mode Support

Add dark mode toggle for better reading experience:

```html
<!-- Add to _layouts/default.html in header -->
<button id="theme-toggle" aria-label="Toggle dark mode">
  <span class="sun">☀️</span>
  <span class="moon">🌙</span>
</button>
```

**Dark mode CSS variables:**

```css
:root {
  --bg: #f7f3ec;
  --ink: #1b1b1b;
  --muted: #6c5f4a;
  --accent: #9a4a2b;
  --paper: #fffaf1;
  --line: #e6dccb;
}

[data-theme="dark"] {
  --bg: #1a1a1a;
  --ink: #e8e8e8;
  --muted: #a8a8a8;
  --accent: #ff8a65;
  --paper: #252525;
  --line: #404040;
}

#theme-toggle {
  background: none;
  border: 1px solid var(--line);
  border-radius: 4px;
  padding: 0.5em;
  cursor: pointer;
  font-size: 1.2rem;
}

#theme-toggle .moon {
  display: none;
}

[data-theme="dark"] #theme-toggle .sun {
  display: none;
}

[data-theme="dark"] #theme-toggle .moon {
  display: inline;
}
```

**Dark mode JavaScript:**

```javascript
<script>
  const toggle = document.getElementById('theme-toggle');
  const currentTheme = localStorage.getItem('theme') || 'light';
  document.documentElement.setAttribute('data-theme', currentTheme);

  toggle.addEventListener('click', function() {
    const theme = document.documentElement.getAttribute('data-theme');
    const newTheme = theme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);
  });
</script>
```

---

## Quick Wins Checklist

Prioritized list of improvements by effort/impact:

### High Impact, Low Effort
- [ ] Add callout box styling (30 min)
- [ ] Add chapter navigation styling (20 min)
- [ ] Add reading time estimates to TOC (15 min)
- [ ] Add print styles for PDF export (30 min)
- [ ] Add copy buttons to code blocks (20 min)

### High Impact, Medium Effort
- [ ] Create chapter layout template (1 hour)
- [ ] Enhance _config.yml with full metadata (30 min)
- [ ] Create book_structure.yml data file (1 hour)
- [ ] Add breadcrumb navigation (45 min)
- [ ] Add search functionality (1-2 hours)

### Medium Impact, Medium Effort
- [ ] Add dark mode support (1 hour)
- [ ] Create GitHub Action for PDF generation (2 hours)
- [ ] Add progress tracking to TOC (1 hour)
- [ ] Add keyboard navigation (prev/next with arrow keys) (1 hour)

### Future Enhancements
- [ ] Add Mermaid diagram support
- [ ] Create glossary page with term definitions
- [ ] Add command reference index
- [ ] Create interactive examples with CodePen embeds
- [ ] Add version selector for different editions
- [ ] Implement full-text search with Lunr.js or Algolia

---

## Implementation Priority

**Phase 1: Core Reading Experience** (2-3 hours)
1. ✅ Enhanced _config.yml (Completed 2026-01-15)
2. Callout box styling
3. Chapter navigation styling
4. Print/PDF styles

**Phase 2: Navigation & Discovery** (3-4 hours)
5. Chapter layout template
6. Book structure data file
7. Enhanced TOC with reading times
8. Breadcrumb navigation

**Phase 3: Polish & Features** (3-4 hours)
9. Code block copy buttons
10. Dark mode support
11. Simple search functionality
12. GitHub Pages deployment

**Phase 4: Advanced Features** (ongoing)
13. PDF generation automation
14. Progress tracking
15. Keyboard shortcuts
16. Advanced search with Lunr.js
