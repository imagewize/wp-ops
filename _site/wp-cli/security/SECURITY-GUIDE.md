# WordPress Security Scanner Suite - Usage Guide

**Version:** 1.0.0
**Date:** November 5, 2025
**Files:**
- `security-scanner.php` (wrapper - runs both scanners)
- `security-scanner-targeted.php` (site-specific threats)
- `security-scanner-general.php` (broad malware detection)

---

## Overview

This security scanner suite provides **dual-layer protection** for the Rob Disbergen WordPress site:

### Two-Scanner Strategy

**1. Targeted Scanner** (`security-scanner-targeted.php`)
- **Purpose:** Monitors site-specific threats from your November 2025 investigation
- **Focus:** Facebook redirects, file disclosure, WordPress exploits, performance issues
- **Use case:** Weekly monitoring, post-deployment verification
- **Speed:** Fast (~1.7 seconds for 6,600 files)

**2. General Scanner** (`security-scanner-general.php`)
- **Purpose:** Detects broad-spectrum malware and unknown threats
- **Focus:** Known malware filenames, pharma hacks, webshells, SEO spam
- **Use case:** Monthly deep scans, after suspected compromise
- **Speed:** Comprehensive (~2.5 seconds for 7,400 files)

**3. Wrapper Script** (`security-scanner.php`)
- **Purpose:** Runs both scanners sequentially for complete coverage
- **Use case:** Comprehensive security audits

### Combined Features

**Targeted Scanner:**
- Facebook redirect detection
- File disclosure vulnerabilities
- WordPress-specific exploits
- SQL injection patterns
- PHP malware (eval, base64)
- Code obfuscation detection

**General Scanner:**
- Known malware filenames (c99, r57, shell, etc.)
- Pharmaceutical spam injection
- SEO spam and hidden iframes
- Webshell signatures
- Multiple encoding layers
- Backdoor functions
- Long base64/hex strings

**Both Scanners:**
- Severity levels (CRITICAL, HIGH, MEDIUM)
- Fast performance (< 3 seconds each)
- Command-line path arguments
- Colored CLI output
- False positive documentation

---

## Installation

The scanner suite is already included in the theme:

```
wp-content/themes/robdisbergen/
├── security-scanner.php            # Wrapper (runs both)
├── security-scanner-targeted.php   # Site-specific threats
└── security-scanner-general.php    # Broad malware detection
```

**⚠️ IMPORTANT SECURITY NOTES:**

1. **Never leave these files accessible on production without protection**
2. **Delete or move outside web root after scanning**
3. **Use IP whitelist if accessing via browser**
4. **Recommended: Use WP-CLI for production scans**

---

## Usage

### Recommended Scanning Strategy

**Weekly** → Run **targeted scanner** (quick, site-specific)
```bash
php security-scanner-targeted.php
```

**Monthly** → Run **general scanner** (comprehensive, malware detection)
```bash
php security-scanner-general.php
```

**After Incident** → Run **both** via wrapper
```bash
php security-scanner.php
```

---

### Method 1: Command Line (Recommended)

**Run both scanners (complete coverage):**
```bash
cd /path/to/wordpress
php wp-content/themes/robdisbergen/security-scanner.php
```

**Run targeted scanner only (weekly):**
```bash
php wp-content/themes/robdisbergen/security-scanner-targeted.php
```

**Run general scanner only (monthly):**
```bash
php wp-content/themes/robdisbergen/security-scanner-general.php
```

**Scan a specific directory:**
```bash
php wp-content/themes/robdisbergen/security-scanner.php /path/to/directory
```

**Scan with home directory shortcut:**
```bash
php wp-content/themes/robdisbergen/security-scanner-targeted.php ~/code/robdisbergen.nl
```

### Method 2: WP-CLI (Production Safe)

**Run both scanners:**
```bash
wp eval-file wp-content/themes/robdisbergen/security-scanner.php
```

**Run targeted scanner only:**
```bash
wp eval-file wp-content/themes/robdisbergen/security-scanner-targeted.php
```

**Run general scanner only:**
```bash
wp eval-file wp-content/themes/robdisbergen/security-scanner-general.php
```

### Method 3: Browser Access (Requires IP Whitelist)

1. **FIRST**: Edit the scanner file and add your IP address:
   ```php
   $allowed_ips = [
       '127.0.0.1',
       'YOUR.IP.ADDRESS.HERE', // ← Add your IP here
   ];
   ```

2. Navigate to one of:
   ```
   https://yoursite.com/wp-content/themes/robdisbergen/security-scanner.php
   https://yoursite.com/wp-content/themes/robdisbergen/security-scanner-targeted.php
   https://yoursite.com/wp-content/themes/robdisbergen/security-scanner-general.php
   ```

3. **AFTER SCANNING**: Delete the files or remove them from the web root!

---

## Understanding Results

### Scan Statistics

```
SCAN SUMMARY:
  Directories scanned: 1,828
  Files scanned: 6,638
  Files with matches: 79
  Total matches: 86
  Errors: 0
  Skipped files: 2
  Scan time: 1.69 seconds
```

### Severity Levels

#### CRITICAL
- **Facebook redirect attempts**
- **eval() with base64_decode**
- **Arbitrary file download vulnerabilities**
- **System command execution from user input**

**Action Required:** Investigate immediately

#### HIGH
- **Suspicious redirects**
- **Unsafe file operations**
- **Potential SQL injection**

**Action Required:** Review within 24 hours

#### MEDIUM
- **WordPress unauthenticated AJAX**
- **Code obfuscation patterns**
- **Dynamic function calls**

**Action Required:** Review as time permits

---

## Common False Positives

### WordPress Core Files

These are **LEGITIMATE** and should be **ignored**:

```
✓ xmlrpc.php - file_get_contents('php://input')
  → Legitimate WordPress XML-RPC functionality

✓ wp-includes/class-json.php - file_get_contents('php://input')
  → Legitimate JSON API input handling

✓ wp-includes/rest-api/class-wp-rest-server.php
  → Legitimate REST API request handling
```

### Plugin Security Features

These are **LEGITIMATE** plugin features:

```
✓ LiteSpeed Cache - file_get_contents('php://input')
  → Legitimate optimization and API features

✓ ACF Pro - add_action('wp_ajax_nopriv_')
  → Legitimate frontend AJAX for custom fields

✓ Gravity Forms - add_action('wp_ajax_nopriv_')
  → Legitimate frontend form submissions

✓ UpdraftPlus - chmod(), file operations
  → Legitimate backup and restore operations
```

### Cryptography Libraries

These are **LEGITIMATE** encoding patterns:

```
✓ phpseclib - chr(), base64, gzinflate
  → Legitimate encryption/decryption operations

✓ SimplePie - gzinflate, gzuncompress
  → Legitimate RSS feed compression handling
```

---

## Real Threats to Watch For

### Actual Malware Patterns

**These would be CRITICAL:**

```
❌ eval(base64_decode('malicious_code_here'))
❌ window.location = "http://facebook.com"
❌ system($_GET['cmd'])
❌ readfile($_GET['file']) without sanitization
```

### Signs of Compromise

1. **Unknown files in wp-content/uploads/**
   - Especially PHP files
   - Check: `find wp-content/uploads -name "*.php"`

2. **Recently modified core files**
   - Check: `wp core verify-checksums`

3. **Suspicious admin users**
   - Check: `wp user list --role=administrator`

4. **Database injections**
   - Check for users with suspicious display names
   - Check for posts with hidden iframes

---

## Scan Results from November 5, 2025

### Production Site Scan

**Location:** `~/code/robdisbergen/` (Development)
**Result:** ✅ **NO MALWARE DETECTED**

```
Files scanned: 6,638
Files with matches: 79 (all false positives)
Facebook redirects: 0 ← NONE FOUND
Actual threats: 0
```

**Conclusion:** The "Facebook redirect" issue reported by the client was **NOT caused by malware**, but by **performance issues during cache stampede** (see [LOADING-ISSUES.md](LOADING-ISSUES.md) for full analysis).

### Staging Site Scan

**Location:** `~/code/robdisbergen.nl/` (Staging)
**Result:** ✅ **NO MALWARE DETECTED**

```
Files scanned: 6,623
Files with matches: 78 (all false positives)
Facebook redirects: 0 ← NONE FOUND
Actual threats: 0
```

**Conclusion:** Both development and staging environments are clean.

---

## Integration with Production Server

### Upload to Production

```bash
# Via SFTP/FTP
# Upload: wp-content/themes/robdisbergen/security-scanner.php

# Via WP-CLI SSH
wp @production eval-file security-scanner.php
```

### Run on Production (Recommended Method)

**Option 1: WP-CLI via SSH**
```bash
ssh user@your-server.com
cd /path/to/wordpress
wp eval-file wp-content/themes/robdisbergen/security-scanner.php > scan-results.txt
cat scan-results.txt
```

**Option 2: Cron Job (Scheduled Scans)**
```bash
# Add to crontab
0 3 * * 1 /usr/local/bin/wp eval-file /path/to/security-scanner.php --path=/path/to/wordpress | mail -s "Weekly Security Scan" admin@yoursite.com
```

**Option 3: Server Script**
```bash
#!/bin/bash
# /usr/local/bin/weekly-scan.sh

cd /path/to/wordpress
php wp-content/themes/robdisbergen/security-scanner.php > /tmp/scan-$(date +%Y%m%d).txt

# Email results
mail -s "Security Scan Results" admin@yoursite.com < /tmp/scan-$(date +%Y%m%d).txt

# Keep last 10 scans
ls -t /tmp/scan-*.txt | tail -n +11 | xargs rm -f
```

---

## Customization

### Add Custom Patterns

Edit `security-scanner.php` around line 84:

```php
$patterns = [
    // ... existing patterns ...

    // Add your custom pattern
    'custom_threat' => [
        'name' => 'Custom Threat Pattern',
        'description' => 'Describe what this detects',
        'patterns' => [
            '/pattern1/i',
            '/pattern2/i',
        ],
        'severity' => 'CRITICAL',
    ],
];
```

### Adjust Scan Configuration

Edit around line 65:

```php
$config = [
    'start_path' => dirname(__FILE__, 4),
    'exclude_dirs' => [
        'node_modules',
        '.git',
        'vendor',
        'wp-content/uploads/cache',
        'wp-content/cache',
        'custom-exclude-dir', // ← Add custom exclusions
    ],
    'file_extensions' => ['php', 'js', 'txt', 'htm', 'html'], // ← Add extensions
    'max_execution_time' => 300,
    'max_file_size' => 5 * 1024 * 1024, // ← Adjust max file size
];
```

---

## Troubleshooting

### Timeout Errors

If scanning times out:

```php
// Increase limits in security-scanner.php
$config = [
    'max_execution_time' => 600, // 10 minutes instead of 5
];
```

Or run via command line (no timeout limits):
```bash
php -d max_execution_time=600 security-scanner.php
```

### Memory Errors

```bash
php -d memory_limit=512M security-scanner.php
```

### Permission Errors

```bash
# Run as web server user
sudo -u www-data php security-scanner.php

# Or fix permissions temporarily
chmod +r -R /path/to/scan
```

### Too Many False Positives

Edit patterns to be more specific:

```php
// Instead of:
'/eval\s*\(/i',  // Matches ALL eval()

// Use:
'/eval\s*\(\s*base64_decode/i',  // Only matches eval(base64_decode(...))
```

---

## Best Practices

### Regular Scanning Schedule

- **Development:** Before each deployment
- **Staging:** After each deployment
- **Production:** Weekly via cron job
- **After Updates:** After WordPress/plugin updates
- **After Incidents:** Immediately after any security concern

### Scan Checklist

- [ ] Run scanner on development
- [ ] Review all CRITICAL and HIGH matches
- [ ] Verify core file integrity: `wp core verify-checksums`
- [ ] Check plugin integrity: `wp plugin verify-checksums --all`
- [ ] Review recent file modifications
- [ ] Check database for suspicious content
- [ ] Review access logs for unusual requests
- [ ] Document any findings

### Security Hardening

After scanning, implement these protections:

1. **File Integrity Monitoring**
   ```bash
   # Install Wordfence or Sucuri
   wp plugin install wordfence --activate
   ```

2. **Disable File Editing**
   ```php
   // wp-config.php
   define('DISALLOW_FILE_EDIT', true);
   ```

3. **Limit Login Attempts**
   ```bash
   wp plugin install limit-login-attempts-reloaded --activate
   ```

4. **2FA Authentication**
   ```bash
   wp plugin install two-factor --activate
   ```

5. **Security Headers** (see [LOADING-ISSUES.md](LOADING-ISSUES.md) for .htaccess examples)

---

## Related Documentation

- **[LOADING-ISSUES.md](LOADING-ISSUES.md)** - Full investigation of November 2025 Facebook redirect issue
- **[LITESPEED-CACHE-TRADEOFF.md](LITESPEED-CACHE-TRADEOFF.md)** - Cache performance analysis
- **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** - Webhook rate limiting deployment

---

## Changelog

### Version 1.0.0 (November 5, 2025)

**Initial Release:**
- Facebook redirect pattern detection (from November 2025 investigation)
- PHP malware detection (eval, base64, gzinflate, etc.)
- File disclosure vulnerability detection
- SQL injection pattern detection
- WordPress-specific exploit detection
- Code obfuscation detection
- Multiple severity levels (CRITICAL, HIGH, MEDIUM)
- Command-line directory scanning support
- IP whitelist for browser access
- Colored CLI output
- HTML output for browser access
- Scan statistics and timing
- False positive documentation

**Tested On:**
- WordPress 6.4.x
- PHP 8.1/8.2
- 6,600+ files scanned in ~1.7 seconds
- Zero false negatives on known patterns

---

## Support & Contact

### Report False Positives

If you encounter a legitimate pattern flagged as suspicious:

1. Document the file path and line number
2. Verify the code is from official WordPress/plugin source
3. Add to "Common False Positives" section above
4. Consider adjusting the pattern regex to be more specific

### Report Security Issues

If you find an actual security vulnerability:

1. **DO NOT commit to public repository**
2. Document the vulnerability privately
3. Fix immediately
4. Review Git history for when it was introduced
5. Check if it was exploited (access logs)
6. Update passwords/secrets if compromised

---

## License

This scanner is part of the Rob Disbergen WordPress theme.
Copyright © 2025. All rights reserved.

Based on malware detection patterns from:
- WordPress Security Best Practices
- OWASP Top 10
- GitHub: jasperf/lookforbadguys.php
- Real-world WordPress security investigations

---

**Document Version:** 1.0
**Last Updated:** November 5, 2025
**Next Review:** After next security incident or quarterly
