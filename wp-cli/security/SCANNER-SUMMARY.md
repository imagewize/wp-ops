# Security Scanner Suite - Quick Reference

**Created:** November 5, 2025
**Version:** 2.0.0
**Updated:** September 10, 2026

---

## 📁 Files Created

```
wp-cli/security/
├── checksum-verify.php           # Checksum verification module (NEW!)
├── scanner-wrapper.php          # Wrapper (runs both scanners)
├── scanner-targeted.php          # Site-specific threats
├── scanner-general.php          # Broad malware detection
├── SECURITY-GUIDE.md            # Complete documentation
└── SCANNER-SUMMARY.md            # This file
```

---

## 🎯 Which Scanner To Use?

| Situation | Scanner | Command |
|-----------|---------|---------|
| **Weekly monitoring** | Targeted | `php scanner-targeted.php` |
| **Monthly deep scan** | General | `php scanner-general.php` |
| **After deployment** | Targeted | `php scanner-targeted.php` |
| **After security incident** | Both | `php scanner-wrapper.php` |
| **Suspected compromise** | Both | `php scanner-wrapper.php` |
| **Before going live** | Both | `php scanner-wrapper.php` |

✨ **NEW in v2.0:** All scanners now include automatic checksum verification to eliminate false positives from unmodified WordPress core and plugin files!

---

## ⚡ Quick Start

**Run both scanners (comprehensive):**
```bash
cd /path/to/wordpress
php wp-content/themes/client/security-scanner.php
```

**Run targeted scanner only (quick check):**
```bash
php wp-content/themes/client/security-scanner-targeted.php
```

**Run general scanner only (malware check):**
```bash
php wp-content/themes/client/security-scanner-general.php
```

**Scan different directory:**
```bash
php wp-content/themes/client/security-scanner.php ~/code/client.nl
```

---

## 🔍 What Each Scanner Detects

### NEW: Checksum Verification (Both Scanners)
✅ **Automatically skips unmodified WordPress core files** - No more false positives from `wp-includes/kses.php`, `SimplePie/Misc.php`, etc.
✅ **Automatically skips verified plugin files** - Plugins from wordpress.org that pass checksum are skipped
✅ **Prioritizes checksum failures** - Modified core/plugin files are flagged as HIGH PRIORITY
✅ **Works with or without WP-CLI** - Falls back to pattern-only mode if WP-CLI unavailable

**Requires:** WP-CLI for full checksum verification (optional)

---

### Targeted Scanner (Site-Specific)
✅ Facebook redirect patterns (from Nov 2025 investigation)
✅ File disclosure vulnerabilities (like download.php issue)
✅ WordPress-specific exploits (unauthenticated AJAX)
✅ SQL injection patterns
✅ PHP malware (eval, base64_decode)
✅ Code obfuscation

**Speed:** ~1.7 seconds for 6,600 files (faster with checksum filtering!)
**False Positives:** Near zero for core files (with checksum verification)

### General Scanner (Broad Detection)
✅ Known malware filenames (c99.php, r57.php, shell.php, etc.)
✅ Pharmaceutical spam injection (viagra, cialis, etc.)
✅ SEO spam and hidden iframes
✅ Webshell signatures (FilesMan, WSO, etc.)
✅ Multiple encoding layers
✅ Backdoor functions
✅ Long base64/hex strings

**Speed:** ~2.5 seconds for 7,400 files (faster with checksum filtering!)
**False Positives:** Reduced (checksum verification eliminates core/plugin false positives)

---

## 📊 Test Results (November 5, 2025)

### Development Site (`~/code/client/`)
**Targeted Scanner:**
- Files scanned: 6,638
- Threats found: 0 ✅
- Facebook redirects: 0 ✅

**General Scanner:**
- Files scanned: 7,380
- Suspicious filenames: 21 (mostly false positives)
- Real threats: 0 ✅

### Staging Site (`~/code/client.nl/`)
**Targeted Scanner:**
- Files scanned: 6,623
- Threats found: 0 ✅
- Facebook redirects: 0 ✅

**General Scanner:**
- Files scanned: 7,400
- Suspicious filenames: 18 (mostly false positives)
- Real threats: 0 ✅

**Conclusion:** Both environments are clean. No malware detected.

---

## 🆕 Checksum Verification (NEW in v2.0)

### What Changed?
Previously, legitimate WordPress core files like `wp-includes/kses.php`, `wp-includes/class-json.php`, 
`wp-includes/SimplePie/src/Misc.php`, and `wp-includes/IXR/class-IXR-server.php` were 
**consistently flagged** as CRITICAL/HIGH matches due to patterns like:
- `file_get_contents('php://input')`
- `ob_start('ob_gzhandler')`
- Other legitimate but suspicious-looking code

These were **documented false positives** that appeared on EVERY scan of EVERY site.

### What's New?
✅ **Checksum verification runs automatically** before pattern scanning
✅ **Files that pass checksum are skipped** in pattern scan entirely
✅ **Files that fail checksum are prioritized** as HIGH PRIORITY
✅ **Reduces false positives to near zero** for core files

### How It Works
1. Shell out to `wp core verify-checksums` to verify WordPress core integrity
2. Shell out to `wp plugin verify-checksums --all` to verify plugins
3. Files that pass verification are added to a "skip list"
4. Pattern scanning only runs on files that:
   - Failed checksum verification (MODIFIED - HIGH PRIORITY!)
   - Are in uploads, themes, mu-plugins (no checksum available)
   - Are custom/premium plugins (no checksum source)

### Results
- **Before:** ~50-100 false positive matches from core files on every scan
- **After:** 0 false positives from core files (they're skipped)
- **Checksum failures:** Now appear as HIGH PRIORITY alerts
- **Scan speed:** Slightly faster (fewer files to pattern-scan)

---

## 🚨 Common False Positives

### ❌ OBSOLETE - No Longer Applicable!
With checksum verification enabled, these **no longer appear** as false positives:
- `wp-includes/kses.php` - Now skipped via checksum ✅
- `wp-includes/class-json.php` - Now skipped via checksum ✅
- `wp-includes/SimplePie/src/Misc.php` - Now skipped via checksum ✅
- `wp-includes/IXR/class-IXR-server.php` - Now skipped via checksum ✅
- `wp-includes/rest-api/class-wp-rest-server.php` - Now skipped via checksum ✅
- `xmlrpc.php` - Now skipped via checksum ✅

All WordPress core files that pass checksum verification are **automatically excluded** from pattern matching!

---

### Still May Appear (Cannot Be Checksum-Verified)
These areas **cannot** use checksum verification and may still have false positives:

#### Targeted Scanner
- LiteSpeed Cache files - Legitimate optimization
- ACF Pro files - Legitimate frontend AJAX
- Gravity Forms - Legitimate form handling
- Custom/premium plugins (not from wordpress.org)
- Uploads directory (user content)
- Themes (custom code)
- mu-plugins (custom code)

#### General Scanner
- `adminer.php` in plugin directories - Legitimate database tool
- Base64 in vendor directories - Legitimate encoding
- Long strings in minified JS - Legitimate compression
- Non-wp.org plugins

---

## ⚠️ Real Threats (Examples)

If you see these, investigate immediately:

### CRITICAL
- `c99.php`, `r57.php`, `shell.php` in uploads directory
- `eval(base64_decode(...))` in your theme files
- `system($_GET['cmd'])` anywhere
- Files modified in last 24 hours with suspicious names

### HIGH
- New PHP files in `/wp-content/uploads/`
- Pharma keywords in your theme templates
- Hidden iframes in footer.php
- World-writable permissions (0777) on PHP files

---

## 🔒 Security Best Practices

**After Scanning:**
1. Delete scanner files from production (or move outside web root)
2. Review any CRITICAL matches immediately
3. Check file modification dates for suspicious changes
4. Compare with clean backups

**Regular Schedule:**
- [ ] Weekly: Run targeted scanner
- [ ] Monthly: Run general scanner
- [ ] After updates: Run targeted scanner
- [ ] After incidents: Run both scanners

**Additional Security:**
```bash
# Verify WordPress core integrity
wp core verify-checksums

# Verify plugin integrity
wp plugin verify-checksums --all

# Find PHP files in uploads (should be none)
find wp-content/uploads -name "*.php"

# Find recently modified files
find . -type f -name "*.php" -mtime -7
```

---

## 📚 Full Documentation

For complete documentation, see:
- **[SECURITY-SCANNER-GUIDE.md](SECURITY-SCANNER-GUIDE.md)** - Complete usage guide
- **[LOADING-ISSUES.md](LOADING-ISSUES.md)** - Background on November 2025 investigation
- **[LITESPEED-CACHE-TRADEOFF.md](LITESPEED-CACHE-TRADEOFF.md)** - Performance analysis

---

## 🆘 Support

**If you find malware:**
1. DO NOT delete immediately - document first
2. Check when file was created: `stat filename.php`
3. Review Git history: `git log --all -- path/to/file`
4. Isolate infected files
5. Change all passwords
6. Review access logs

**Contact:**
- Review [SECURITY-SCANNER-GUIDE.md](SECURITY-SCANNER-GUIDE.md) for troubleshooting
- Check WordPress Security best practices
- Consider professional security audit if compromised

---

**Last Updated:** November 5, 2025
**Status:** Production Ready
