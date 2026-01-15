# WP-CLI Tools & Documentation

Command-line tools, scripts, and comprehensive guides for WordPress operations using [WP-CLI](https://wp-cli.org/) in [Trellis/Bedrock](https://roots.io/) environments.

## Overview

This directory contains production-tested WP-CLI utilities for:

- **Content Creation** - Gutenberg block patterns and page creation workflows
- **Diagnostics** - WordPress troubleshooting and debugging tools
- **Migration** - WordPress site migration to Trellis/Bedrock infrastructure

## Directory Structure

```
wp-cli/
├── content-creation/    # Block patterns, page creation, automation scripts
├── diagnostics/         # Troubleshooting and debugging tools
└── migration/           # Site migration documentation and workflows
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

# Run diagnostics
wp eval-file wp-cli/diagnostics/diagnostic-transients.php
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

- **Two Tool Formats**:
  - CLI-based (`diagnostic-transients.php`) - For servers with WP-CLI access
  - Web-based (`transient-debug-browser.php`) - For browser access with security token

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
| `diagnostic-transients.php` | WP-CLI | Development/production servers with CLI access |
| `transient-debug-browser.php` | Web browser | Production servers or sharing with non-technical users |

### Usage Examples

#### CLI Diagnostic (Recommended)

```bash
# Local development
cd /path/to/bedrock
wp eval-file diagnostic-transients.php --path=web/wp

# Remote via Trellis
ssh web@example.com "cd /srv/www/example.com/current && \
  wp eval-file diagnostic-transients.php --path=web/wp"

# Save output to file
wp eval-file diagnostic-transients.php --path=web/wp > diagnostic-report.txt
```

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

**Location:** `migration/`

Comprehensive guides for migrating WordPress sites to Trellis/Bedrock infrastructure.

### Features

- **Single-Site Migration** - Traditional WordPress to Trellis/Bedrock
- **Multi-Site Migration** - Consolidating multiple sites to Trellis
- **Full Bedrock Adoption** - Recommended approach with composer dependencies
- **Path Compatibility Mode** - Quick migration without restructuring
- **Domain Migration** - URL replacement workflows
- **Testing Methodology** - `/etc/hosts` testing before DNS cutover

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Migration overview and quick reference (100+ lines) |
| `REGULAR-TO-TRELLIS.md` | Complete single-site migration guide |
| `MULTI-SITE-MIGRATION.md` | Multi-site consolidation strategies |

### Migration Approaches

#### Full Bedrock Adoption (Recommended)

**Pros:**
- Modern Composer-based dependency management
- Improved security (wp-admin outside web root)
- Environment-specific configuration (.env files)
- Better version control (gitignore for WordPress core)
- Trellis deployment integration

**Cons:**
- Requires path updates in database
- More initial setup time
- Plugin compatibility review needed

#### Path Compatibility Mode

**Pros:**
- Faster migration
- Minimal database changes
- Lower risk for simple sites

**Cons:**
- Doesn't leverage Bedrock benefits
- Future maintenance complexity
- May need conversion later

### Common Migration Workflow

1. **Preparation**
   - Backup current site (database + files)
   - Document current configuration
   - Test locally with Trellis development environment
   - Identify custom code and plugins

2. **Database Migration**
   ```bash
   # Export from old site
   wp db export backup.sql

   # Import to new site
   wp db import backup.sql --path=web/wp

   # Update URLs (Bedrock adoption)
   wp search-replace '/wp-content/' '/app/' --all-tables --path=web/wp
   wp search-replace 'http://old-domain.com' 'https://new-domain.com' --all-tables --path=web/wp
   ```

3. **File Migration**
   ```bash
   # Copy uploads
   rsync -av old-site/wp-content/uploads/ \
     bedrock/web/app/uploads/

   # Copy themes (if custom)
   rsync -av old-site/wp-content/themes/custom-theme/ \
     bedrock/web/app/themes/custom-theme/

   # Install plugins via Composer (recommended)
   composer require wpackagist-plugin/plugin-name
   ```

4. **Testing with /etc/hosts**
   ```bash
   # Edit /etc/hosts before DNS change
   sudo nano /etc/hosts

   # Add line:
   123.45.67.89 example.com www.example.com

   # Test in browser before DNS cutover
   # Remove line after DNS propagation
   ```

5. **DNS Cutover**
   - Update A records to new server IP
   - Monitor for issues
   - Keep old site available for rollback

6. **Post-Migration**
   - Verify all pages load correctly
   - Test forms and contact submissions
   - Check SSL certificate
   - Configure WordPress cron (Trellis uses system cron)
   - Update Google Search Console
   - Submit updated sitemap

### Multi-Site Migration Strategies

**Time-Saving Tips:**
- **Batch preparation**: Set up all sites before first provision
- **Descriptive naming**: Use clear directory names from start (`site-1-domain.com` not `site-1`)
- **Configure together**: Add all sites to `wordpress_sites.yml` before provisioning
- **Template configs**: Reuse vault structure and settings

**Time Estimates:**
- First site: 3-5 hours (learning curve)
- Subsequent sites: 2-2.5 hours each
- Multi-site batch: ~2 hours per site (after first)

### Domain Migration Commands

```bash
# Simple domain change
wp search-replace 'old-domain.com' 'new-domain.com' --all-tables --path=web/wp

# HTTP to HTTPS
wp search-replace 'http://example.com' 'https://example.com' --all-tables --path=web/wp

# With dry run (test first)
wp search-replace 'old-domain.com' 'new-domain.com' --all-tables --dry-run --path=web/wp

# Precise mode (exact matches only)
wp search-replace 'old-domain.com' 'new-domain.com' --all-tables --precise --path=web/wp
```

### Bedrock Path Conversion

```bash
# Update content paths
wp search-replace '/wp-content/uploads/' '/app/uploads/' --all-tables --path=web/wp
wp search-replace '/wp-content/themes/' '/app/themes/' --all-tables --path=web/wp
wp search-replace '/wp-content/plugins/' '/app/plugins/' --all-tables --path=web/wp

# Update includes paths (less common)
wp search-replace 'wp-includes' 'wp/wp-includes' --all-tables --path=web/wp
```

### WordPress Cron Configuration

Trellis disables WP-Cron and uses system cron instead:

```bash
# Trellis sets in .env
DISABLE_WP_CRON=true

# System cron runs every 15 minutes
*/15 * * * * cd /srv/www/example.com/current && wp cron event run --due-now --path=web/wp

# Verify cron is working
ssh web@example.com "cd /srv/www/example.com/current && \
  wp cron event list --path=web/wp"
```

### Troubleshooting Common Issues

**Database connection errors:**
- Check `.env` file database credentials
- Verify database exists and user has permissions
- Test connection: `wp db check --path=web/wp`

**Missing uploads:**
- Verify rsync completed successfully
- Check file permissions: `chown -R web:www-data uploads/`
- Confirm path in database matches Bedrock structure

**Plugin compatibility:**
- Test plugins individually
- Check for hardcoded paths
- Review plugin requirements (some may need Composer installation)

**SSL errors:**
- Verify Trellis SSL configuration in `wordpress_sites.yml`
- Check nginx SSL certificates: `ls -la /etc/nginx/ssl/`
- Test SSL: `curl -I https://example.com`

**Permalink errors:**
- Flush rewrite rules: `wp rewrite flush --path=web/wp`
- Verify nginx configuration includes WordPress permalinks
- Check `.htaccess` equivalent in nginx config

**See also:** [migration/README.md](migration/README.md) and subdirectory documentation.

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

### Migration

1. **Backup everything** - Database and files before migration
2. **Test with /etc/hosts** - Verify before DNS change
3. **Use dry-run first** - Test search-replace before applying
4. **Document custom code** - Track plugins, themes, custom functionality
5. **Plan rollback strategy** - Keep old site available during migration
6. **Communicate changes** - Inform users of potential downtime
7. **Verify after migration** - Check all functionality works correctly

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
