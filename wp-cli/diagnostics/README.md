# Diagnostics

WordPress diagnostic tools for troubleshooting common issues in Trellis/Bedrock environments. These tools help identify and resolve problems with caching, performance, database operations, and WordPress core functionality.

## Chapter Purpose

This chapter explains which diagnostics to run first and how to interpret the results without changing production data.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Available Tools](#available-tools)
  - [Transient Diagnostics](#transient-diagnostics)
- [Best Practices](#best-practices)
- [Contributing](#contributing)

## Overview

This directory contains diagnostic scripts and tools designed to help debug WordPress issues in both development and production environments. Each tool is standalone and can be deployed independently.

**Key Features:**
- Production-safe diagnostic scripts
- Comprehensive reporting capabilities
- No database modifications during diagnostics
- Security-conscious design with access controls
- Compatible with Trellis/Bedrock WordPress architecture

## Installation

Diagnostic tools are designed to be copied into your WordPress project as needed:

### For WP-CLI Scripts
```bash
# Copy to your theme or plugin directory
cp diagnostic-transients.php /path/to/site/web/app/themes/your-theme/

# Or copy to wp-content root
cp diagnostic-transients.php /path/to/site/web/wp-content/
```

### For Browser-Based Tools
```bash
# Upload to wp-content directory (most common)
scp transient-debug-browser.php user@server:/path/to/site/web/wp-content/

# Or use Trellis deployment
# Add file to your repository and deploy normally
```

## Available Tools

### Transient Diagnostics

WordPress transients are a way to temporarily store cached data in the database. These tools help diagnose issues when transients aren't being stored, retrieved, or expired correctly.

#### 1. CLI Transient Diagnostic (`diagnostic-transients.php`)

**Purpose:** Run comprehensive transient diagnostics via WP-CLI on development or production servers.

**Usage:**
```bash
# From Bedrock site root (development)
wp eval-file web/app/themes/your-theme/diagnostic-transients.php --path=web/wp

# Via Trellis SSH
trellis ssh production
cd /srv/www/example.com/current
wp eval-file web/app/themes/your-theme/diagnostic-transients.php --path=web/wp
```

**What It Tests:**
1. **Transient Storage** - Verifies set/get operations work correctly
2. **API Cache Status** - Checks specific cache (api_properties_list) existence and expiration
3. **Object Cache Configuration** - Detects external cache systems (Redis, Memcached, LiteSpeed)
4. **Database Transient Check** - Verifies transients exist in wp_options table
5. **Transient Cleanup Cron** - Lists scheduled cleanup jobs
6. **Business Hours Logic** - Tests time-based cache lifetime calculations
7. **Recent Activity** - Shows transients created in the last hour

**Output:** Terminal-formatted diagnostic report with recommendations

**When to Use:**
- Transients not persisting between requests
- Cache appears to be cleared unexpectedly
- API data not being cached properly
- After enabling/disabling object cache plugins

#### 2. Browser Transient Debugger (`transient-debug-browser.php`)

**Purpose:** Web-based diagnostic tool for production servers where WP-CLI access may be limited or when you need to share results with non-technical stakeholders.

**Setup:**
1. Upload file to `wp-content/` directory
2. Edit the file and change the `DEBUG_SECRET` constant to a unique value
3. Access via browser: `https://example.com/wp-content/transient-debug-browser.php?secret=your_secret`

**Security:**
- Requires secret token in URL query parameter
- Change `DEBUG_SECRET` constant before deployment
- Delete file after diagnostics are complete
- Returns HTML output (not visible in page source to casual observers)

**What It Tests:**
1. **Basic Transient Functionality** - Real-time set/get/delete operations
2. **Database Configuration** - MySQL settings that affect performance
3. **wp_options Table Analysis** - Table size, transient count, autoload size
4. **Large Transient Test** - Tests 1KB, 10KB, 100KB, and 1MB transients
5. **API Properties Cache** - Checks your specific cache implementation
6. **Object Cache & Plugins** - Detects cache plugins and configurations
7. **Server Environment** - PHP, MySQL, WordPress versions
8. **Recent Transients** - Last 20 transients in database

**Output:** Styled HTML report with color-coded results, tables, and actionable recommendations

**When to Use:**
- Production environment without easy WP-CLI access
- Need to share diagnostic results with clients or team members
- Want detailed database performance metrics
- Testing after server configuration changes

### Common Issues Diagnosed

Both tools help identify:

- **External object cache conflicts** - LiteSpeed, Redis, Memcached interfering with transients
- **Database storage failures** - Transients not being written to wp_options table
- **Expired cache issues** - Transients expiring too quickly or not at all
- **Plugin conflicts** - Cache management plugins clearing transients unexpectedly
- **Large data storage problems** - MySQL packet size limits preventing large transient storage
- **Autoload bloat** - Too many autoloaded options slowing down WordPress

## Best Practices

### Security
- **Always** change default secret tokens in browser-based tools
- **Delete** diagnostic files from production after use
- **Never** commit files with real secrets to version control
- **Restrict** access to diagnostic URLs (use .htaccess or Nginx rules if leaving in place)

### Performance
- Run diagnostics during low-traffic periods when possible
- Browser diagnostic creates temporary test transients but cleans them up
- CLI diagnostic is lightweight and safe for production use

### Workflow
1. **Start with CLI diagnostic** - Faster, more detailed for developers
2. **Use browser diagnostic** - When you need shareable results or detailed DB analysis
3. **Document findings** - Copy output to your issue tracker or documentation
4. **Test fixes** - Re-run diagnostic after implementing solutions

### Interpreting Results

**Green (✅)** - Test passed, working as expected
**Yellow (⚠️)** - Warning, may indicate potential issues
**Red (❌)** - Critical failure, requires immediate attention

## Contributing

When adding new diagnostic tools to this directory:

1. **Follow naming convention:** `diagnostic-{feature}.php` for CLI tools, `{feature}-debug-browser.php` for web tools
2. **Include security:** Add access controls for browser-based tools
3. **Document thoroughly:** Add inline comments explaining each test
4. **Update this README:** Add tool description under "Available Tools"
5. **Test on production:** Verify tool is safe and doesn't modify data
6. **Provide examples:** Show expected output in documentation

### Planned Additions

Future diagnostic tools may include:
- Database performance diagnostics
- Image optimization verification
- Nginx configuration testing
- SSL/TLS certificate validation
- WordPress security audit tools
- Cron job monitoring
- Plugin conflict detection
- Memory usage analysis

---

**Need Help?**

These tools are designed to help identify problems, not fix them automatically. If diagnostic reports show issues:

1. Review the recommendations in the tool output
2. Check WordPress debug logs: `web/app/debug.log`
3. Review server error logs: `/var/log/nginx/error.log`
4. Consult Trellis documentation: https://roots.io/trellis/docs/
5. Search WordPress support forums for specific error messages

For issues with these diagnostic tools themselves, open an issue in this repository.
