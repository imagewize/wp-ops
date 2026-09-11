# WordPress Security Scanners

Comprehensive dual-scanner security suite for WordPress malware detection and security auditing.

✨ **NEW in v2.0:** Automatic checksum verification eliminates false positives from unmodified WordPress core and plugin files!

Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations and server management.

---

## ⚙️ Requirements & Installation

### Check if WP-CLI is Available

```bash
# Test if WP-CLI is installed
wp --version

# If you see version output, WP-CLI is available ✓
# If "command not found", see installation below
```

### Installing WP-CLI

#### VPS/Dedicated Server (with SSH root access)

```bash
# Download WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar

# Make executable
chmod +x wp-cli.phar

# Move to system PATH
sudo mv wp-cli.phar /usr/local/bin/wp

# Verify installation
wp --version
```

#### Shared Hosting (SSH access, no root)

```bash
# Download to home directory
cd ~
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar

# Create alias in ~/.bashrc or ~/.bash_profile
echo "alias wp='php ~/wp-cli.phar'" >> ~/.bashrc
source ~/.bashrc

# Verify
wp --version
```

#### Trellis/Bedrock Projects

WP-CLI is pre-installed ✓

### Execution Methods by Hosting Type

Choose the method that matches your hosting environment:

| Hosting Type | WP-CLI | Direct PHP | Browser | Recommended Method |
|--------------|--------|------------|---------|-------------------|
| **VPS/Dedicated** | ✅ Yes | ✅ Yes | ⚠️ Not recommended | `wp eval-file` |
| **Shared (SSH)** | Install it | ✅ Yes | ⚠️ Not recommended | Install WP-CLI or use `php` |
| **Shared (no SSH)** | ❌ No | ❌ No | ⚠️ Last resort | See [Browser Access](#browser-access-last-resort) |
| **Trellis/Bedrock** | ✅ Pre-installed | ✅ Yes | ⚠️ Not recommended | `wp eval-file` |
| **cPanel/Plesk** | Maybe | ✅ Via Terminal | ⚠️ Not recommended | See [cPanel/Plesk](#cpanelplesk-terminal) |

### cPanel/Plesk Terminal

Some shared hosts provide browser-based terminals:

**cPanel:**
1. Login → Advanced → Terminal
2. Navigate to WordPress: `cd public_html` (or your WordPress directory)
3. Run scanner:
```bash
php scanner-targeted.php
# Or with full path:
php /home/username/public_html/wp-cli/security/scanner-targeted.php
```

**Plesk:**
1. Login → File Manager → Open in Terminal (or Tools & Settings → Scheduled Tasks → Terminal)
2. Navigate to WordPress directory
3. Run scanner:
```bash
php scanner-targeted.php
# Or use version-specific PHP binary:
/opt/plesk/php/8.2/bin/php scanner-targeted.php
```

### Browser Access (Last Resort)

⚠️ **SECURITY WARNING**: Only use this method if you have NO other option!

**Setup:**

1. **Upload scanner files** to WordPress root via FTP or File Manager
2. **Add IP whitelist** - Edit the scanner file (e.g., `scanner-targeted.php`) around line 15:

```php
// Find and update this section:
$allowed_ips = [
    '127.0.0.1',
    'YOUR.IP.ADDRESS.HERE',  // ← Add your public IP address
];
```

3. **Find your IP address**: Visit https://whatismyipaddress.com/
4. **Access via browser**:
```
https://yoursite.com/scanner-targeted.php
```

5. **CRITICAL - Delete immediately after use**:
```bash
# Via FTP/File Manager, delete:
scanner-targeted.php
scanner-general.php
scanner-wrapper.php
```

**Why browser access is dangerous:**
- ❌ Exposes security scanner to the public internet
- ❌ Could leak file structure and configuration details
- ❌ Scanner file itself could be exploited by attackers
- ❌ Often flagged/blocked by security plugins and WAFs
- ❌ May be logged by server access logs

**Safer alternative for restricted hosting:**

Download your WordPress files via FTP and scan them locally on your computer:

```bash
# On your local machine (after downloading WordPress via FTP)
php scanner-targeted.php /path/to/downloaded-wordpress
```

---

## 🎯 Quick Start

```bash
# From WordPress root directory

# Run both scanners (recommended first scan)
wp eval-file wp-cli/security/scanner-wrapper.php

# Or run individually
wp eval-file wp-cli/security/scanner-targeted.php  # Quick check (1-2s, faster with checksum!)
wp eval-file wp-cli/security/scanner-general.php   # Deep scan (2-3s, faster with checksum!)
```

✨ **Automatic Checksum Verification:** If WP-CLI is available, checksums are verified automatically before scanning. No extra steps needed!

---

## 🔐 Checksum Verification (NEW in v2.0)

### What is Checksum Verification?

Checksum verification compares installed WordPress files against official release hashes from wordpress.org. This allows the scanners to:

1. ✅ **Skip unmodified core files** - No more false positives from legitimate WordPress code
2. ✅ **Skip verified plugins** - Plugins from wordpress.org that pass checksum are skipped
3. ✅ **Prioritize modified files** - Files that fail checksum are flagged as HIGH PRIORITY

### What Changed?

**Before v2.0:** Every scan would flag legitimate WordPress core files like `wp-includes/kses.php`, `wp-includes/SimplePie/src/Misc.php`, etc. for patterns like `file_get_contents('php://input')` or `ob_start('ob_gzhandler')`. These were **documented false positives** that appeared on every scan.

**After v2.0:** These files are automatically skipped if they pass checksum verification, reducing false positives to near zero for core files!

### How It Works

1. **Automatic Detection:** When a scan starts, the system checks if WP-CLI is available
2. **Core Verification:** Runs `wp core verify-checksums` to verify WordPress core integrity
3. **Plugin Verification:** Runs `wp plugin verify-checksums --all` to verify plugins
4. **Smart Filtering:** Files that pass verification are excluded from pattern matching
5. **Priority Alerts:** Files that fail checksum are flagged as HIGH PRIORITY threats

### What Gets Verified?

| Type | Verification | Result |
|------|-------------|--------|
| WordPress Core | `wp core verify-checksums` | ✅ Verified files skipped |
| WP.org Plugins | `wp plugin verify-checksums --all` | ✅ Verified files skipped |
| Premium/Custom Plugins | N/A (no checksum source) | ⚠️ Pattern scan only |
| Themes | N/A (custom code) | ⚠️ Pattern scan only |
| Uploads | N/A (user content) | ⚠️ Pattern scan only |
| mu-plugins | N/A (custom code) | ⚠️ Pattern scan only |

### Fallback Behavior

If WP-CLI is **not available**, the scanners automatically fall back to pattern-only mode with no checksum verification. The scan still works, but you'll see the same false positives as before.

To check if WP-CLI is available:
```bash
wp --version
```

If not installed, see [Requirements & Installation](#-requirements--installation) below.

### Direct PHP Usage

```bash
# If WP-CLI is not available
php wp-cli/security/scanner-wrapper.php
php wp-cli/security/scanner-targeted.php
php wp-cli/security/scanner-general.php

# Scan specific directory
php wp-cli/security/scanner-targeted.php /path/to/wordpress
```

### Via wp-ops

These scanners are also runnable through the [`wp-ops`](../../README.md) CLI (`wp-ops wp-cli --help` to list them). Set `WP_SITE_DIR` to the WordPress/Bedrock project to scan:

```bash
export WP_SITE_DIR=/path/to/your/bedrock-site
wp-ops wp-cli scanner-wrapper
wp-ops wp-cli scanner-targeted /custom/path/to/scan
```

---

## 📁 What's Included

```
wp-cli/security/
├── checksum-verify.php        # Checksum verification module (NEW!)
├── malware-scan.sh            # Scan a remote site over SSH (NEW!)
├── scanner-wrapper.php        # Wrapper (runs both scanners)
├── scanner-targeted.php       # Site-specific threat detection v2.0
├── scanner-general.php        # Broad malware detection v2.0
├── SECURITY-GUIDE.md          # Complete documentation
├── SCANNER-SUMMARY.md         # Quick reference guide
└── README.md                  # This file
```

---

## 🔍 Two-Scanner Strategy

### Targeted Scanner (Site-Specific)
**Purpose:** Fast detection of common WordPress vulnerabilities
**Speed:** ~1.7 seconds for 6,600 files

**Detects:**
- Facebook redirect attempts
- File disclosure vulnerabilities
- WordPress-specific exploits (unauthenticated AJAX)
- SQL injection patterns
- PHP malware (eval, base64_decode)
- Code obfuscation

**Use:** Weekly monitoring, post-deployment checks

### General Scanner (Broad Detection)
**Purpose:** Comprehensive malware detection
**Speed:** ~2.5 seconds for 7,400 files

**Detects:**
- Known malware filenames (c99.php, r57.php, shell.php, etc.)
- Pharmaceutical spam injection
- SEO spam and hidden iframes
- Webshell signatures (FilesMan, WSO, etc.)
- Multiple encoding layers
- Backdoor functions
- Long suspicious base64/hex strings

**Use:** Monthly deep scans, after suspected compromise

---

## 🚀 Usage Examples

### Local Development (Bedrock)

```bash
# From Bedrock site directory
wp eval-file wp-ops/wp-cli/security/scanner-targeted.php
```

### Remote sites

```bash
# One command, from your own machine — no copying, no cleanup
wp-ops malware-scan example.com production

# Both scanners
wp-ops malware-scan example.com production --mode both
```

`malware-scan` streams the scanner source to the target's PHP over stdin, so
nothing is ever written to the server. It resolves the SSH host and WordPress
path from the MCP server's site registry (`mcp-server/config/sites.json`, or
`$WP_OPS_SITES_CONFIG`) when one exists, and otherwise defaults to the stock
Trellis layout — `web@<site-name>` and `/srv/www/<site>/current/web/wp`.

Only those defaults assume Trellis. The scan itself is plain SSH plus a PHP
CLI, so any WordPress you can SSH into works once you say where it is:

```bash
wp-ops malware-scan example.com production \
  --host deploy@example.com --path /home/deploy/public_html
```

Point `--path` at the **WordPress core directory** (`web/wp` on Bedrock, the
docroot on a classic install). Checksum verification `chdir`s into that path to
run `wp core verify-checksums`, so aiming at a Bedrock site root silently loses
core verification. Checksum verification also needs WP-CLI *on the target*; the
scan still runs without it, in pattern-only mode.

Ignore the scanner's closing "DELETE THIS FILE after use" warning here — it is
written for the copy-to-the-server workflow below. Nothing was copied.

> **Copying the scanner to the server by hand is no longer enough.** Since
> v2.0 both scanners `require_once` the sibling `checksum-verify.php`, so a
> lone `scp` of `scanner-targeted.php` fatals on the missing file. Copy both
> files, or use `wp-ops malware-scan`.

### Scan Multiple Sites

```bash
#!/bin/bash
# weekly-scan.sh

sites=(
    "/var/www/site1.com"
    "/var/www/site2.com"
    "/var/www/site3.com"
)

for site in "${sites[@]}"; do
    echo "Scanning $site..."
    wp eval-file wp-cli/security/scanner-targeted.php --path="$site"
done
```

### Recommended Schedule

| Frequency | Scanner | Command |
|-----------|---------|---------|
| **Weekly** | Targeted | `wp eval-file wp-cli/security/scanner-targeted.php` |
| **Monthly** | General | `wp eval-file wp-cli/security/scanner-general.php` |
| **After Deployment** | Targeted | `wp eval-file wp-cli/security/scanner-targeted.php` |
| **After Incident** | Both | `wp eval-file wp-cli/security/scanner-wrapper.php` |

✨ **With Checksum Verification:** Scans are faster and produce fewer false positives!

---

## 📊 Sample Output

```
============================================
  SECURITY SCAN COMPLETE
============================================

SCAN SUMMARY:
  Directories scanned: 1,828
  Files scanned: 6,638
  Files with matches: 79
  Total matches: 86
  Errors: 0
  Scan time: 1.69 seconds

✓ No suspicious patterns detected!
```

---

## 🔗 Integration with wp-ops Workflows

### Pre-Deployment Security Check

```bash
# Before pushing database to staging
wp eval-file wp-cli/security/scanner-targeted.php
ansible-playbook trellis/backup/database-push.yml -e site=example.com -e env=staging
```

### Post-Deployment Verification

```bash
# After production deployment
ansible-playbook deploy.yml -e env=production

# Scan production from your own machine
wp-ops malware-scan example.com production
```

### Incident Response Workflow

```bash
# 1. Scan for malware
wp eval-file wp-cli/security/scanner-general.php

# 2. Backup before cleanup (see trellis/backup/)
ansible-playbook trellis/backup/database-backup.yml -e site=example.com -e env=production
ansible-playbook trellis/backup/files-backup.yml -e site=example.com -e env=production

# 3. Clean malware (manual remediation)

# 4. Verify clean
wp eval-file wp-cli/security/scanner-targeted.php
```

---

## ⚠️ Security Notes

**IMPORTANT:**
1. **Never commit scanner results** to version control
2. **Delete scanner files from production** after use (if copied temporarily)
3. **Use WP-CLI method** (recommended) instead of browser access
4. **Review output carefully** - not all matches are threats (see false positives)

### Browser Access (Not Recommended)

If you must access via browser:

1. Edit scanner file and add your IP:
```php
$allowed_ips = [
    '127.0.0.1',
    'YOUR.IP.ADDRESS.HERE', // Add your IP
];
```

2. Navigate to:
```
https://yoursite.com/wp-cli/security/scanner-wrapper.php
```

3. **DELETE immediately after use!**

---

## 🎓 Understanding Results

### Severity Levels

- **CRITICAL** - Investigate immediately (malware signatures, backdoors)
- **HIGH** - Review within 24 hours (suspicious redirects, file operations)
- **MEDIUM** - Review as time permits (WordPress exploits, obfuscation)

### Common False Positives

**These are SAFE and can be ignored:**

✅ `xmlrpc.php` - Legitimate WordPress XML-RPC
✅ `wp-includes/rest-api/*` - Legitimate REST API
✅ LiteSpeed Cache files - Legitimate optimization
✅ ACF Pro AJAX - Legitimate frontend functionality
✅ Gravity Forms - Legitimate form handling
✅ SimplePie/MySQL.php - Legitimate library

**See [SCANNER-SUMMARY.md](SCANNER-SUMMARY.md) for complete false positive list**

### Real Threats (Examples)

**Investigate these immediately:**

❌ `c99.php`, `r57.php`, `shell.php` in uploads
❌ `eval(base64_decode(...))` in theme files
❌ `system($_GET['cmd'])` anywhere
❌ Files modified in last 24 hours with suspicious names
❌ New PHP files in `/wp-content/uploads/`

---

## 🛠️ Advanced Usage

### Automated Cron Job

```bash
# Add to crontab: crontab -e
# Weekly scan every Monday at 3am
0 3 * * 1 /usr/bin/wp eval-file /path/to/wp-ops/wp-cli/security/scanner-targeted.php --path=/var/www/wordpress > /var/log/wp-scan.log 2>&1
```

### Customization

#### Add Custom Patterns

Edit the scanner file and add your patterns:

```php
// In scanner-targeted.php or scanner-general.php
$patterns = [
    // ... existing patterns ...

    'custom_threat' => [
        'name' => 'My Custom Threat',
        'description' => 'Description of what this detects',
        'patterns' => [
            '/your-regex-pattern-here/i',
        ],
        'severity' => 'CRITICAL',
    ],
];
```

#### Exclude Directories

```php
$config = [
    'exclude_dirs' => [
        'node_modules',
        '.git',
        'vendor',
        'your-custom-dir',  // Add your exclusions
    ],
];
```

---

## 🐛 Troubleshooting

### "wp: command not found"

**Cause:** WP-CLI is not installed or not in your system PATH

**Solutions:**

```bash
# Option 1: Install WP-CLI (see Requirements & Installation section)
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Option 2: Use full path to wp-cli.phar
php ~/wp-cli.phar eval-file wp-cli/security/scanner-targeted.php

# Option 3: Use direct PHP method instead
php wp-cli/security/scanner-targeted.php
```

### "PHP: command not found" (Shared Hosting)

**Cause:** PHP is not in your PATH or has a different binary name

**Solutions:**

```bash
# Try alternative PHP binary names
/usr/bin/php scanner-targeted.php
/usr/local/bin/php scanner-targeted.php
php-cli scanner-targeted.php
php8.2 scanner-targeted.php  # Version-specific (common on cPanel)

# Find PHP location
which php
whereis php
find /usr -name "php*" -type f 2>/dev/null | grep bin
```

### cPanel/Plesk PHP Version Issues

**cPanel - Select PHP version:**

1. MultiPHP Manager → Select desired PHP version for domain
2. Or use version-specific binary:
```bash
# Check available PHP versions
ls /opt/cpanel/ea-php*/root/usr/bin/php

# Use specific version
/opt/cpanel/ea-php82/root/usr/bin/php scanner-targeted.php
```

**Plesk - Use specific PHP version:**

```bash
# List available PHP versions
ls /opt/plesk/php/

# Use specific version
/opt/plesk/php/8.2/bin/php scanner-targeted.php
```

### File Upload Restrictions

**Problem:** Cannot upload `.php` files via File Manager (security restriction)

**Workaround:**

```bash
# Method 1: Upload as .txt, then rename
1. Upload as: scanner-targeted.txt
2. Rename via File Manager to: scanner-targeted.php

# Method 2: Use FTP instead (usually less restricted than web-based File Manager)
# FTP clients like FileZilla typically allow .php uploads

# Method 3: Upload via SSH/SCP (if available)
scp scanner-targeted.php user@yoursite.com:~/public_html/
```

### Scanner Reports No Files Found

**Cause:** Incorrect path or scanner not in WordPress root

**Solutions:**

```bash
# Method 1: Specify full WordPress path
php scanner-targeted.php /full/path/to/wordpress

# Method 2: Navigate to WordPress root first
cd /var/www/html  # or your WordPress directory
php /path/to/scanner-targeted.php

# Method 3: Use pwd to verify current directory
pwd  # Should show WordPress root with wp-config.php
ls -la wp-config.php  # Verify you're in the right place
```

### Timeout Errors

**Problem:** Scanner times out on large WordPress installations

**Solutions:**

```bash
# Increase PHP timeout
php -d max_execution_time=600 wp-cli/security/scanner-wrapper.php

# Or edit scanner file directly (add at top after <?php):
ini_set('max_execution_time', 600);

# For WP-CLI
wp eval-file scanner-targeted.php --path=/var/www/html --skip-plugins --skip-themes
```

### Memory Errors

**Problem:** PHP runs out of memory

**Solutions:**

```bash
# Increase memory limit
php -d memory_limit=512M wp-cli/security/scanner-wrapper.php

# Or edit scanner file directly (add at top after <?php):
ini_set('memory_limit', '512M');

# Check current memory limit
php -i | grep memory_limit
```

### Permission Errors

**Problem:** Cannot read files or directories

**Solutions:**

```bash
# Method 1: Run as web server user
sudo -u www-data wp eval-file wp-cli/security/scanner-targeted.php

# Method 2: Fix file permissions (carefully!)
# For development only - DO NOT run on production without understanding implications
sudo chown -R www-data:www-data /var/www/html
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;

# Method 3: Run scanner from a directory you own
cp scanner-targeted.php ~/scanner-targeted.php
php ~/scanner-targeted.php /var/www/html
```

### Browser Access Returns Blank Page

**Cause:** Usually PHP errors being suppressed

**Solutions:**

1. **Check server error logs:**
```bash
# Common log locations
tail -f /var/log/apache2/error.log  # Apache
tail -f /var/log/nginx/error.log    # Nginx
tail -f ~/logs/error_log             # cPanel
```

2. **Enable PHP error display** (temporarily, for debugging):
```php
// Add to top of scanner file (after <?php)
error_reporting(E_ALL);
ini_set('display_errors', 1);
```

3. **Check if your IP is whitelisted** (see Browser Access section)

4. **Verify PHP file execution is allowed** in that directory

### "Headers already sent" Error

**Cause:** Output or whitespace before PHP opening tag

**Solution:**

```bash
# Check for whitespace/BOM at start of scanner file
hexdump -C scanner-targeted.php | head -n 2

# Should start with: 3c 3f 70 68 70  (which is "<?php")
# If you see: ef bb bf before 3c 3f, that's a UTF-8 BOM - remove it

# Fix with text editor that can save as UTF-8 without BOM
```

---

## 📚 Related Documentation

- **[SECURITY-GUIDE.md](SECURITY-GUIDE.md)** - Complete usage guide with examples
- **[SCANNER-SUMMARY.md](SCANNER-SUMMARY.md)** - Quick reference for busy developers
- **[wp-cli/diagnostics/](../diagnostics/)** - WordPress diagnostic tools
- **[troubleshooting/](../../docs/troubleshooting/)** - Server and WordPress troubleshooting guides
- **[trellis/backup/](../../trellis/backup/)** - Backup operations before security cleanup

---

## 📈 Performance

### Benchmark Results

Tested on MacBook Pro M1, PHP 8.2:

| Scanner | Files | Time | Speed |
|---------|-------|------|-------|
| Targeted | 6,638 | 1.7s | 3,905 files/sec |
| General | 7,380 | 2.5s | 2,952 files/sec |
| Both | 7,380 | 4.2s | 1,757 files/sec |

**With Checksum Verification (v2.0):**
- Fewer files to scan (verified files skipped)
- Same scan speed for remaining files
- **Net result: ~10-30% faster** depending on site composition

### Optimization Tips

1. Exclude large directories (`node_modules`, `vendor`)
2. Run during off-peak hours for production
3. Use targeted scanner for frequent checks
4. Use general scanner for monthly deep scans
5. **NEW:** Ensure WP-CLI is available for automatic checksum verification

---

## 📜 License

MIT License - Part of the wp-ops project

---

## 🙏 Credits

- Based on malware detection patterns from WordPress Security Best Practices
- Inspired by [lookforbadguys.php](https://gist.github.com/jasperf/3191259)
- Originally built for Client WordPress site security investigation (November 2025)
- Integrated into wp-ops toolkit (December 2025)

---

**Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations**
