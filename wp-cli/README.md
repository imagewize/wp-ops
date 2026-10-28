# WP-CLI Tools & Documentation

Command-line tools, scripts, and comprehensive guides for WordPress operations using [WP-CLI](https://wp-cli.org/) in [Trellis/Bedrock](https://roots.io/) environments.

## Overview

This directory contains production-tested WP-CLI utilities for:

- **Content Creation** - Gutenberg block patterns and page creation workflows
- **Diagnostics** - WordPress troubleshooting and debugging tools
- **Migration** - WordPress site migration to Trellis/Bedrock infrastructure
- **SEO** - SEO audits: page structure, redirect chains, schema markup, blog analysis, orphan pages

## Directory Structure

```
wp-cli/
├── content-creation/    # Block patterns, page creation, automation scripts
├── diagnostics/         # Troubleshooting and debugging tools
└── seo/                # SEO audit tools and scripts
```

## Quick Start

### Prerequisites

- WP-CLI installed (included with Trellis)
- WordPress site (Bedrock or traditional structure)
- SSH access to server (for remote operations)
- Basic understanding of WordPress and WP-CLI commands

### Common Operations

```bash
# Local development (from Bedrock site directory)
wp post list --post_type=page --path=web/wp
wp post create --post_title="New Page" --post_status=publish --path=web/wp

# Remote via Trellis
trellis vm shell --workdir /srv/www/example.com/current -- wp post list --path=web/wp
```

---

## 1. Content Creation

**Location:** `content-creation/`

Tools and documentation for creating WordPress pages and Gutenberg block patterns in Trellis/Bedrock environments.

### Features

- **Local Development Workflow** - Trellis VM-based page creation
- **Production Deployment** - Automated and manual deployment methods
- **URL Sanitization** - Critical for avoiding mixed content warnings
- **Block Pattern Standards** - Comprehensive requirements based on 141+ production patterns
- **Automation Scripts** - Bash scripts for deployment

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Navigation guide to appropriate documentation |
| `PAGE-CREATION.md` | Complete page creation workflow (1,000+ lines) |
| `PATTERN-REQUIREMENTS.md` | Block pattern specification (1,150+ lines) |
| `page-creation.sh` | Automated production deployment script |
| `examples/example-page-content.html` | Sample Gutenberg block markup |

### Key Topics

**PAGE-CREATION.md** covers:
- Local development workflow with Trellis VM
- Production deployment (automated script and manual methods)
- **CRITICAL: URL Sanitization** before production deployment
  - Pattern URLs get hardcoded into database
  - Development URLs (`.test`) must be replaced with production URLs (`.com`)
  - Verification and search-replace workflows
- Adding patterns to existing pages (3 methods with examples)
- Common issues and troubleshooting
- Best practices for security, performance, and SEO

**PATTERN-REQUIREMENTS.md** covers:
- Pattern header requirements (Title, Slug, Description, Categories)
- Metadata attribute structure
- Structural patterns (full-width, grids, constrained layouts)
- Spacing and styling standards (theme variable usage mandatory)
- Image handling (avoiding hardcoded media IDs)
- Typography and responsive design
- Accessibility and semantic HTML
- PHP in patterns (security, escaping, limitations)
- Internationalization (i18n)
- **17 Common Mistakes** with explanations

### Usage Examples

#### Create Page Locally

```bash
# SSH into Trellis VM
trellis vm shell

# Navigate to WordPress directory
cd /srv/www/example.com/current

# Create page with pattern
CONTENT='<!-- wp:pattern {"slug":"theme-name/hero-section"} /-->'
wp post create --post_title="About Us" \
  --post_content="$CONTENT" \
  --post_status=publish \
  --path=web/wp
```

#### Deploy to Production (Automated)

```bash
# Edit page-creation.sh with your details
./content-creation/page-creation.sh
```

#### Verify URLs After Deployment

```bash
# Check for development URLs in production
ssh web@example.com "cd /srv/www/example.com/current && \
  wp db query \"SELECT COUNT(*) FROM wp_posts WHERE post_content LIKE '%.test%';\" --path=web/wp"

# If found, run search-replace
ssh web@example.com "cd /srv/www/example.com/current && \
  wp search-replace 'http://example.test' 'https://example.com' --all-tables --precise --path=web/wp"
```

### Common Workflows

#### Adding Pattern to Existing Page

**Method 1: Direct Content Update**
```bash
# Get existing content
EXISTING=$(wp post get 100 --field=content --path=web/wp)

# Add pattern
NEW_CONTENT="<!-- wp:pattern {\"slug\":\"theme/hero\"} /-->
$EXISTING"

# Update post
wp post update 100 --post_content="$NEW_CONTENT" --path=web/wp
```

**Method 2: Using Heredoc**
```bash
wp post update 100 --post_content="$(cat <<'EOF'
<!-- wp:pattern {"slug":"theme/hero"} /-->
<!-- wp:pattern {"slug":"theme/features"} /-->
EOF
)" --path=web/wp
```

**Method 3: Python Escaping (Complex Content)**
```python
import subprocess
content = """<!-- wp:pattern {"slug":"theme/hero"} /-->
<!-- wp:paragraph -->
<p>Content with "quotes" and 'apostrophes'</p>
<!-- /wp:paragraph -->"""

subprocess.run(['wp', 'post', 'update', '100', f'--post_content={content}', '--path=web/wp'])
```

**See also:** [content-creation/README.md](content-creation/README.md) and subdirectory documentation.

---

## 2. Diagnostics

**Location:** `diagnostics/`

Production-safe diagnostic scripts for identifying and troubleshooting WordPress issues without modifying data.

### Features

- **Web-based tool** (`transient-debug-browser.php`) - For browser access with security token

- **Comprehensive Tests**:
  - Transient storage and API cache functionality
  - Object cache configuration (Memcached, Redis)
  - Database connectivity and configuration
  - WordPress cron jobs and scheduling
  - Recent activity and performance
  - Server environment details

- **Security Features**:
  - Read-only operations (no data modification)
  - Token-based authentication for web version
  - Detailed logging and error reporting

### Available Tools

| Tool | Access Method | Use Case |
|------|--------------|----------|
| `transient-debug-browser.php` | Web browser | Production servers or sharing with non-technical users |

### Usage Examples

#### Web-Based Diagnostic

1. **Edit file** to set security token:
   ```php
   define('DEBUG_SECRET', 'your-random-secret-token-here');
   ```

2. **Upload to WordPress root** (outside web-accessible directory recommended)

3. **Access via browser**:
   ```
   https://example.com/transient-debug-browser.php?token=your-random-secret-token-here
   ```

4. **Review results** - Color-coded output with recommendations

5. **Delete file** when finished

### Diagnostic Tests Performed

**Test 1: Transient Storage**
- Creates test transient
- Verifies retrieval
- Checks deletion
- Identifies storage mechanism (database vs object cache)

**Test 2: API Cache Status**
- Checks transient API configuration
- Verifies cache availability
- Tests cache hit/miss behavior

**Test 3: Object Cache Configuration**
- Detects Memcached/Redis
- Validates connection
- Checks cache stats
- Reports configuration issues

**Test 4: Database Connectivity**
- Tests database connection
- Verifies wp_options table access
- Checks for autoload issues
- Reports large option sizes

**Test 5: WordPress Cron**
- Lists scheduled cron jobs
- Identifies overdue tasks
- Reports cron configuration
- Checks for disabled cron

**Test 6: Recent Activity**
- Analyzes recent transients
- Identifies plugin activity
- Reports unusual patterns
- Detects potential issues

**Test 7: Server Environment**
- PHP version and configuration
- Memory limits (WP_MEMORY_LIMIT, WP_MAX_MEMORY_LIMIT)
- WordPress version
- Active plugins count

### Common Issues Identified

- **Transient storage failures** - Database vs object cache mismatches
- **Object cache unavailable** - Memcached/Redis connection issues
- **Cron disabled** - DISABLE_WP_CRON set incorrectly
- **Large autoload data** - Performance impact
- **Plugin conflicts** - Excessive transient creation
- **Memory exhaustion** - Insufficient PHP memory limits

### Security Best Practices

1. **CLI tool**: Safe for production use (read-only)
2. **Web tool**:
   - Use strong, random secret token
   - Access via HTTPS only
   - Delete after use
   - Limit access by IP if possible
3. **Never commit** diagnostic files with secrets to version control
4. **Review output** for sensitive data before sharing

**See also:** [diagnostics/README.md](diagnostics/README.md) for complete documentation.

---

## 3. Migration

The migration guides live on the blog:

- [Migrating a WordPress site to Trellis and Bedrock](https://wpvilla.in/migrate-wordpress-to-trellis-bedrock-step-by-step/)
- [Testing a migration before DNS, and the cutover](https://wpvilla.in/trellis-migration-test-etc-hosts-letsencrypt-dns-cutover/)
- [Migrating several sites onto one Trellis server](https://wpvilla.in/migrate-multiple-wordpress-sites-one-trellis-server/)
- [wp search-replace for domain, HTTPS and Bedrock path changes](https://wpvilla.in/wp-search-replace-wordpress-url-domain-https-bedrock-paths/)

---

## 4. SEO

**Location:** `seo/`

Production-tested SEO audit tools for identifying technical SEO issues, content gaps, and optimization opportunities in WordPress sites.

### Features

- **Page Structure Audit** - Navigation hierarchy, key pages check, duplicate title detection
- **Redirect Chain Audit** - HTTP→HTTPS, www canonicalization, security headers validation
- **Schema Markup Audit** - JSON-LD detection and type validation across key pages
- **Blog Content Audit** - Categorization, featured images, content length analysis
- **Orphan Pages Audit** - Identify pages not linked from navigation menus

### Available Tools

| Tool | Purpose | Access Method |
|------|---------|---------------|
| `page-audit.sh` | Analyze page structure, hierarchy, and key business pages | WP-CLI |
| `redirect-audit.sh` | Test redirect chains, HTTP→HTTPS, www canonicalization | HTTP/curl |
| `schema-audit.sh` | Validate JSON-LD schema markup on key pages | HTTP/curl |
| `blog-audit.sh` | Analyze blog content categorization and quality | WP-CLI |
| `orphan-pages-audit.sh` | Find pages not in navigation menus | WP-CLI |

### Usage Examples

#### Page Structure Audit
```bash
# Run from Bedrock site directory
cd /srv/www/example.com/current
./wp-cli/seo/page-audit.sh

# With custom output directory
./wp-cli/seo/page-audit.sh --output reports/seo

# With custom WordPress path
./wp-cli/seo/page-audit.sh --path web/wp
```

#### Redirect Chain Audit
```bash
# Test a single site
./wp-cli/seo/redirect-audit.sh --url https://example.com

# With verbose output
./wp-cli/seo/redirect-audit.sh --url https://example.com --verbose

# Test specific URLs
./wp-cli/seo/redirect-audit.sh --url https://example.com/about/ --url https://example.com/contact/
```

#### Schema Markup Audit
```bash
# Audit default pages
./wp-cli/seo/schema-audit.sh https://example.com

# Audit specific pages
./wp-cli/seo/schema-audit.sh https://example.com --pages /,/services/,/contact/
```

#### Blog Content Audit
```bash
# Run from site directory
cd /srv/www/example.com/current
./wp-cli/seo/blog-audit.sh

# With custom output directory
./wp-cli/seo/blog-audit.sh --output reports/seo
```

#### Orphan Pages Audit
```bash
cd /srv/www/example.com/current
./wp-cli/seo/orphan-pages-audit.sh
```

### Common SEO Issues Identified

- **Missing key business pages** - Home, About, Contact, Services not found
- **Redirect chains** - Multiple 301/302 hops affecting SEO
- **Missing schema markup** - No JSON-LD on important pages
- **Orphaned pages** - Pages not linked from navigation
- **Thin content** - Blog posts with < 800 words
- **Missing featured images** - Posts without thumbnails
- **Duplicate page titles** - Multiple pages with same title
- **Missing security headers** - HSTS, CSP, X-Frame-Options

### Best Practices

1. **Run audits regularly** - Monthly for redirect/schema, quarterly for content
2. **Fix redirect chains first** - Every redirect hop loses link equity
3. **Implement schema markup** - Helps search engines understand your content
4. **Add internal links** - Connect orphaned pages to navigation structure
5. **Use descriptive titles** - Avoid duplicate or generic page titles
6. **Test on staging first** - Run audits on staging before production

**See also:** [seo/README.md](seo/README.md) for complete SEO tools documentation.

---

## Best Practices

### Content Creation

1. **Always test locally first** - Use Trellis development environment
2. **Sanitize URLs before production** - Check for hardcoded development URLs
3. **Follow pattern standards** - Use PATTERN-REQUIREMENTS.md as checklist
4. **Version control patterns** - Commit pattern files to theme repository
5. **Validate block markup** - Test in WordPress editor before automation

### Diagnostics

1. **Use CLI tools when possible** - More secure than web-based
2. **Run diagnostics before troubleshooting** - Gather baseline data
3. **Save diagnostic output** - Compare before/after for issue tracking
4. **Delete web diagnostic files** - Remove after use for security
5. **Regular health checks** - Run diagnostics monthly for proactive monitoring


### SEO

1. **Run audits regularly** - Monthly for redirect/schema, quarterly for content/structure
2. **Fix redirect chains** - Every redirect hop loses link equity (prioritize HTTP→HTTPS and www canonicalization)
3. **Implement schema markup** - JSON-LD helps search engines understand your content
4. **Eliminate orphaned pages** - Add internal links or delete unused pages
5. **Optimize content** - Expand thin content, add featured images, use descriptive titles
6. **Test on staging first** - Run SEO audits on staging before production changes
7. **Monitor search performance** - Track rankings and traffic after fixes

---

## Integration with Trellis

All WP-CLI operations work seamlessly with Trellis:

### Local Development

```bash
# SSH into Vagrant VM
trellis vm shell

# Navigate to site
cd /srv/www/example.com/current

# Run WP-CLI commands
wp --path=web/wp [command]
```

### Remote Operations

```bash
# Direct SSH
ssh web@example.com "cd /srv/www/example.com/current && wp [command] --path=web/wp"

# Via Trellis CLI
trellis vm shell --workdir /srv/www/example.com/current -- wp [command] --path=web/wp
```

### Path Considerations

Bedrock structure requires `--path=web/wp` for WP-CLI commands:

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

## Troubleshooting

### Common WP-CLI Issues

1. **Command not found**
   - Ensure WP-CLI is installed: `wp --version`
   - Trellis includes WP-CLI by default

2. **WordPress not found**
   - Use `--path=web/wp` for Bedrock installations
   - Verify you're in correct directory

3. **Database connection error**
   - Check `.env` file credentials
   - Verify database exists
   - Test: `wp db check --path=web/wp`

4. **Permission denied**
   - Ensure running as `web` user on remote servers
   - Check file ownership: `ls -la`

5. **Memory exhausted**
   - Increase PHP memory limit in `.env`:
     ```
     WP_MEMORY_LIMIT=256M
     WP_MAX_MEMORY_LIMIT=512M
     ```

---

## Further Reading

- [WP-CLI Documentation](https://wp-cli.org/)
- [Trellis Documentation](https://roots.io/trellis/docs/)
- [Bedrock Documentation](https://roots.io/bedrock/docs/)
- [WordPress Block Editor Handbook](https://developer.wordpress.org/block-editor/)
- [Block Pattern Directory](https://wordpress.org/patterns/)

---

## Contributing

When adding new WP-CLI tools or documentation:

1. Test in Trellis development environment
2. Document all commands with examples
3. Include troubleshooting section
4. Provide both local and remote usage examples
5. Consider security implications
6. Follow existing documentation format
7. Add to appropriate subdirectory README
