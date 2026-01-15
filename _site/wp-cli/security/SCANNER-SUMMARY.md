# Security Scanner Suite - Quick Reference

**Created:** November 5, 2025
**Version:** 1.0.0

---

## 📁 Files Created

```
wp-content/themes/robdisbergen/
├── security-scanner.php            # Wrapper (runs both scanners)
├── security-scanner-targeted.php   # Site-specific threats
├── security-scanner-general.php    # Broad malware detection
└── docs/
    ├── SECURITY-SCANNER-GUIDE.md   # Complete documentation
    └── SCANNER-SUMMARY.md          # This file
```

---

## 🎯 Which Scanner To Use?

| Situation | Scanner | Command |
|-----------|---------|---------|
| **Weekly monitoring** | Targeted | `php security-scanner-targeted.php` |
| **Monthly deep scan** | General | `php security-scanner-general.php` |
| **After deployment** | Targeted | `php security-scanner-targeted.php` |
| **After security incident** | Both | `php security-scanner.php` |
| **Suspected compromise** | Both | `php security-scanner.php` |
| **Before going live** | Both | `php security-scanner.php` |

---

## ⚡ Quick Start

**Run both scanners (comprehensive):**
```bash
cd /path/to/wordpress
php wp-content/themes/robdisbergen/security-scanner.php
```

**Run targeted scanner only (quick check):**
```bash
php wp-content/themes/robdisbergen/security-scanner-targeted.php
```

**Run general scanner only (malware check):**
```bash
php wp-content/themes/robdisbergen/security-scanner-general.php
```

**Scan different directory:**
```bash
php wp-content/themes/robdisbergen/security-scanner.php ~/code/robdisbergen.nl
```

---

## 🔍 What Each Scanner Detects

### Targeted Scanner (Site-Specific)
✅ Facebook redirect patterns (from Nov 2025 investigation)
✅ File disclosure vulnerabilities (like download.php issue)
✅ WordPress-specific exploits (unauthenticated AJAX)
✅ SQL injection patterns
✅ PHP malware (eval, base64_decode)
✅ Code obfuscation

**Speed:** ~1.7 seconds for 6,600 files
**False Positives:** Low (tuned for WordPress)

### General Scanner (Broad Detection)
✅ Known malware filenames (c99.php, r57.php, shell.php, etc.)
✅ Pharmaceutical spam injection (viagra, cialis, etc.)
✅ SEO spam and hidden iframes
✅ Webshell signatures (FilesMan, WSO, etc.)
✅ Multiple encoding layers
✅ Backdoor functions
✅ Long base64/hex strings

**Speed:** ~2.5 seconds for 7,400 files
**False Positives:** Medium (broad detection)

---

## 📊 Test Results (November 5, 2025)

### Development Site (`~/code/robdisbergen/`)
**Targeted Scanner:**
- Files scanned: 6,638
- Threats found: 0 ✅
- Facebook redirects: 0 ✅

**General Scanner:**
- Files scanned: 7,380
- Suspicious filenames: 21 (mostly false positives)
- Real threats: 0 ✅

### Staging Site (`~/code/robdisbergen.nl/`)
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

## 🚨 Common False Positives

### Targeted Scanner
These are **SAFE** and can be ignored:
- `xmlrpc.php` - Legitimate WordPress XML-RPC
- `wp-includes/rest-api/*` - Legitimate REST API
- LiteSpeed Cache files - Legitimate optimization
- ACF Pro files - Legitimate frontend AJAX
- Gravity Forms - Legitimate form handling

### General Scanner
These are **SAFE** and can be ignored:
- `SimplePie/Cache/MySQL.php` - Legitimate library
- `adminer.php` in plugin directories - Legitimate database tool
- Base64 in vendor directories - Legitimate encoding
- Long strings in minified JS - Legitimate compression

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
