# SEO Tools & Audits

Comprehensive SEO analysis and audit tools for WordPress sites in Trellis/Bedrock environments. These tools help identify technical SEO issues, content gaps, and optimization opportunities.

## Overview

This directory contains production-tested SEO utilities for:

- **Page Structure Analysis** - Navigation hierarchy, orphaned pages, duplicate content
- **Redirect Chain Auditing** - HTTP→HTTPS, www canonicalization, security headers
- **Schema Markup Validation** - JSON-LD presence and type detection
- **Blog Content Audits** - Categorization, featured images, content length analysis

## Directory Structure

```
wp-cli/seo/
├── page-audit.sh             # Page structure, hierarchy, and orphan detection
├── redirect-audit.sh          # Comprehensive redirect chain and security header testing
├── schema-audit.sh           # Schema markup validation across key pages
├── blog-audit.sh             # Blog content categorization and quality analysis
├── orphan-pages-audit.sh     # Find pages not linked from navigation menus
├── orphan-links-audit.sh     # Find pages nothing else links to in its content
└── README.md                 # This file
```

## Quick Start

### Prerequisites

- WP-CLI installed (included with Trellis)
- WordPress site (Bedrock or traditional structure)
- SSH access to server (for remote operations)
- curl for HTTP-based audits

### Common Operations

```bash
# Local development (from Bedrock site directory)
cd /srv/www/example.com/current
./wp-cli/seo/redirect-audit.sh --url https://example.com

# Remote via Trellis
ssh web@example.com "cd /srv/www/example.com/current && \
  ./wp-cli/seo/page-audit.sh"

# Run schema audit
./wp-cli/seo/schema-audit.sh https://example.com
```

---

## 1. Page Structure Audit

**Script:** `page-audit.sh`

Analyzes WordPress page structure including hierarchy, navigation menus, key business pages, and identifies potential orphaned pages.

### Features

- Export all published pages with metadata (ID, title, slug, dates, parent)
- Analyze navigation menu structure (main menu and submenus)
- Check for key business pages (home, about, contact, services, etc.)
- Identify service/portfolio subpages
- Export complete page hierarchy from database
- Detect duplicate page titles
- Generate comprehensive audit report

### Usage

```bash
# Run from WordPress directory (Bedrock: web/wp parent)
cd /srv/www/example.com/current
./wp-cli/seo/page-audit.sh

# With custom output directory
OUTPUT_DIR="reports/seo" ./wp-cli/seo/page-audit.sh
```

### Output Files

- `audits/page-audit-[date].csv` - All published pages inventory
- `audits/navigation-structure-[date].txt` - Menu structure export
- `audits/page-hierarchy-[date].txt` - Database hierarchy query results
- `audits/duplicate-page-titles-[date].txt` - Duplicate title detection
- `audits/page-audit-report-[date].txt` - Comprehensive report

### Key Checks Performed

1. **Page Inventory** - Total published pages count
2. **Navigation Analysis** - Menu items and structure
3. **Key Pages Check** - Verifies existence of critical business pages
4. **Hierarchy Analysis** - Parent-child relationships
5. **Duplicate Detection** - Finds pages with identical titles
6. **Orphan Detection** - Pages not in main navigation (basic check)

### Recommendations

- Run monthly for proactive SEO monitoring
- Review orphaned pages report and add internal links
- Use duplicate title report to improve page uniqueness
- Verify all key business pages exist and are accessible

---

## 2. Redirect Chain Audit

**Script:** `redirect-audit.sh`

Comprehensive testing of redirect chains, HTTP→HTTPS redirects, www canonicalization, and security headers.

### Features

- Test HTTPS pages for optimal 200 response with 0 redirects
- Verify HTTP→HTTPS 301 redirects
- Check www→non-www canonicalization
- Validate security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options)
- Color-coded output for quick assessment
- Detailed markdown report generation

### Usage

```bash
# Audit a single site
./wp-cli/seo/redirect-audit.sh --url https://example.com

# With verbose curl output
./wp-cli/seo/redirect-audit.sh --url https://example.com --verbose

# Test specific URLs
./wp-cli/seo/redirect-audit.sh --url https://example.com/about/ --url https://example.com/contact/

# Save report to custom location
REPORT_DIR="reports" ./wp-cli/seo/redirect-audit.sh --url https://example.com
```

### Test Types

1. **HTTPS Pages Test** - Should return 200 with 0 redirects (optimal)
2. **HTTP→HTTPS Redirect** - Should be single 301 redirect
3. **WWW Canonicalization** - Should redirect www to non-www with 301
4. **Security Headers** - Checks for HSTS, CSP, X-Frame-Options, X-Content-Type-Options

### Status Indicators

- **✅ OPTIMAL** - 200 status, 0 redirects
- **⚠️ ACCEPTABLE** - 200 status, 1 redirect (should be fixed)
- **❌ ISSUE** - Multiple redirect chains or incorrect status

### Output Files

- `results/audits/redirect-audit-[timestamp].md` - Detailed markdown report

### Recommendations

- Run after any server configuration changes
- Test all key landing pages, not just homepage
- Fix any redirect chains (multiple 301/302 hops)
- Implement missing security headers
- Verify www canonicalization is consistent

---

## 3. Schema Markup Audit

**Script:** `schema-audit.sh`

Validates JSON-LD schema markup presence and types across key WordPress pages.

### Features

- Detect JSON-LD schema blocks in page HTML
- Identify specific schema types:
  - Organization
  - LocalBusiness
  - Service
  - Product
  - WebSite
  - BreadcrumbList
- Check key pages (homepage, services, contact, portfolio, about, shop)
- Generate summary report with recommendations

### Usage

```bash
# Audit schema on a site
./wp-cli/seo/schema-audit.sh https://example.com

# With custom output directory
OUTPUT_DIR="reports/seo" ./wp-cli/seo/schema-audit.sh https://example.com
```

### Output Files

- `audits/schema-audit-[date].txt` - Complete audit report

### Schema Types by Page

| Page Type | Recommended Schema |
|-----------|-------------------|
| Homepage | Organization, WebSite |
| Services | Service, BreadcrumbList |
| Contact | LocalBusiness, Organization |
| Portfolio/Case Studies | Article, BreadcrumbList |
| Shop/Packages | Product, Offer |

### Validation Tools

- [Google Rich Results Test](https://search.google.com/test/rich-results)
- [Schema.org Validator](https://validator.schema.org/)
- [Google Search Console Rich Results Report](https://search.google.com/search-console)

### Recommendations

- Implement Organization schema on homepage
- Add LocalBusiness schema to contact page
- Use Service schema on all service pages
- Validate schema with Google's tools
- Monitor Google Search Console for schema errors

---

## 4. Blog Content Audit

**Script:** `blog-audit.sh`

Analyzes blog post content for categorization, quality metrics, and SEO opportunities.

### Features

- Export all published blog posts with metadata
- Analyze post categories and tags
- Identify SME-focused vs technical content
- Check for posts without featured images
- Detect thin content (< 800 words)
- Generate content gap analysis

### Usage

```bash
# Run blog audit
cd /srv/www/example.com/current
./wp-cli/seo/blog-audit.sh

# With custom output directory
OUTPUT_DIR="reports/seo" ./wp-cli/seo/blog-audit.sh
```

### Output Files

- `audits/blog-audit-[date].csv` - All published posts inventory
- `audits/category-audit-[date].csv` - Category analysis
- `audits/thin-content-[date].txt` - Posts needing content expansion
- `audits/blog-audit-report-[date].txt` - Comprehensive report

### Metrics Tracked

- Total published posts and categories
- SME-focused content count (mentions of "SME", "small business", "case study")
- Technical content count (mentions of "Trellis", "Sage", "Bedrock")
- Posts without featured images
- Posts with thin content (< 800 words)

### Recommendations

- Maintain balance between SME-focused and technical content
- Add featured images to all posts
- Expand thin content posts to 800+ words
- Organize categories for better user experience
- Consider separating technical content to developer-focused site

---

## 5. Orphan Pages Audit

**Script:** `orphan-pages-audit.sh`

Identifies pages that exist in WordPress but are not linked from navigation menus.

### Features

- Export all published pages
- Extract menu item URLs from navigation menus
- Compare pages against menu URLs
- Generate report of potential orphaned pages

### Usage

```bash
# Run orphan pages audit
cd /srv/www/example.com/current
./wp-cli/seo/orphan-pages-audit.sh
```

### Important Note

This script only looks at **navigation menus**. For the in-content view — pages
nothing else links to — run `orphan-links-audit.sh` (section 6) alongside it.
For a full external crawl, Screaming Frog SEO Spider, Ahrefs Site Audit, or
Sitebulb still go further than either script.

### Output Files

- `audits/orphaned-pages-[date].csv` - Potential orphaned pages list
- `audits/menu-urls-[date].txt` - URLs found in navigation

### Recommendations

- Add internal links to important pages not in navigation
- Consider creating a sitemap page
- Use breadcrumb navigation
- Review and update navigation structure regularly

---

## 6. Orphan Links Audit

**Script:** `orphan-links-audit.sh`

Identifies published posts and pages that **no other content links to**. This is
the inbound-link sibling of `orphan-pages-audit.sh` — the two answer different
questions and are both worth running. A page can sit in the nav and still have
zero in-content links, or be linked from a dozen posts while absent from every
menu.

### Features

- Single SQL query — no crawl, no external tool
- Counts inbound references per published post/page, keeps the zeroes
- Runs locally or over SSH against production
- CSV export with ID, title, type, date, and URL

### Usage

```bash
# Against production over SSH
./wp-cli/seo/orphan-links-audit.sh --host web@example.com

# Locally, from a Bedrock site directory
cd /srv/www/example.com/current
./wp-cli/seo/orphan-links-audit.sh --path web/wp --output reports/seo
```

### Caveat

Link detection is a substring match of each page's slug against other published
`post_content`. A slug that appears as plain text counts as a link, and a page
linked only by ID (or by a slug-less shortlink) reads as orphaned. Treat the
output as a shortlist to review, not a verdict.

### Output Files

- `audits/orphan-links-[timestamp].csv` - Pages with zero inbound internal links

### Recommendations

- Work the list newest-first — recent posts are the ones most likely never linked
- Add links from topically related posts, not from a generic index page
- Re-run after a linking pass to confirm the count dropped

---

## Integration with Trellis

All SEO tools work seamlessly with Trellis:

### Local Development

```bash
# SSH into Vagrant VM
trellis vm shell

# Navigate to site
cd /srv/www/example.com/current

# Run SEO audits
./wp-cli/seo/redirect-audit.sh --url https://example.test
./wp-cli/seo/page-audit.sh
```

### Remote Operations

```bash
# Direct SSH
ssh web@example.com "cd /srv/www/example.com/current && \
  ./wp-cli/seo/schema-audit.sh https://example.com"

# Copy script and run
scp wp-cli/seo/blog-audit.sh web@example.com:/srv/www/example.com/current/
ssh web@example.com "cd /srv/www/example.com/current && \
  chmod +x ./wp-cli/seo/blog-audit.sh && \
  ./wp-cli/seo/blog-audit.sh"
```

### Path Considerations

Bedrock structure requires `--path=web/wp` for WP-CLI commands. All scripts in this directory handle this automatically when run from the Bedrock root (`/srv/www/example.com/current/`).

```
/srv/www/example.com/current/
├── web/
│   ├── wp/              ← WordPress core (--path=web/wp)
│   ├── app/
│   │   ├── uploads/
│   │   ├── themes/
│   │   └── plugins/
│   └── index.php
├── composer.json
└── .env
```

---

## Best Practices

### Regular Auditing Schedule

| Audit Type | Frequency | Notes |
|------------|-----------|-------|
| Redirect Audit | Weekly | After any server config changes |
| Schema Audit | Monthly | Or after theme/plugin updates |
| Page Structure | Quarterly | Or after major content changes |
| Blog Content | Quarterly | Review content gaps |
| Orphan Pages | Quarterly | Use Screaming Frog for comprehensive check |

### Before Running Audits

1. **Backup Database** - For write operations (bulk-alt-text)
2. **Check Server Load** - Some audits make many requests
3. **Verify WP-CLI Access** - Test with `wp --version`
4. **Test on Staging First** - For new audits, verify on staging

### After Running Audits

1. **Review Reports** - All scripts generate detailed output files
2. **Prioritize Issues** - Focus on high-impact problems first
3. **Track Changes** - Document fixes and re-audit
4. **Set Up Monitoring** - Automate regular checks where possible

---

## Troubleshooting

### Common Issues

1. **WP-CLI not found**
   - Ensure WP-CLI is installed: `wp --version`
   - Trellis includes WP-CLI by default
   - For Bedrock, use `--path=web/wp`

2. **Database connection error**
   - Check `.env` file credentials
   - Verify database exists
   - Test: `wp db check --path=web/wp`

3. **Permission denied**
   - Ensure running as `web` user on remote servers
   - Check file ownership: `ls -la`

4. **No pages found**
   - Verify post_type and post_status filters
   - Check if site has any published pages

5. **curl not found**
   - Install curl: `apt-get install curl` or `brew install curl`

---

## Further Reading

- [WP-CLI Documentation](https://wp-cli.org/)
- [Trellis Documentation](https://roots.io/trellis/docs/)
- [Bedrock Documentation](https://roots.io/bedrock/docs/)
- [Google SEO Starter Guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide)
- [Schema.org Documentation](https://schema.org/docs/documents.html)
- [Technical SEO Guide by Moz](https://moz.com/learn/seo/technical-seo)

---

## Contributing

When adding new SEO tools:

1. Test in Trellis development environment
2. Document all commands with examples
3. Include troubleshooting section
4. Provide both local and remote usage examples
5. Consider security implications (read-only vs write operations)
6. Follow existing documentation format
7. Add to appropriate subdirectory README
