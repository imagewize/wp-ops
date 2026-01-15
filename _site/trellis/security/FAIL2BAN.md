# fail2ban WordPress Protection

Automatic IP blocking for WordPress brute force attacks using fail2ban.

Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations and server management.

---

## Important: SSH User for Admin Commands

**Note**: This guide uses `admin_user` as a placeholder for your Trellis admin username.

- Trellis creates admin users via `group_vars/{env}/users.yml`
- Admin users have sudo access (require password for sudo commands)
- **Replace `admin_user` with your configured username** (e.g., `warden`, `deploy`, your name, etc.)
- Example: If your admin user is `warden`, use `ssh warden@yoursite.com`

For read-only operations (viewing logs), use the `web` user which doesn't require sudo:
- `ssh web@yoursite.com` - No sudo access, can read site files and logs

---

## Overview

**fail2ban** is a log-monitoring tool that automatically blocks IP addresses showing malicious behavior by updating firewall rules. On Trellis-managed servers, fail2ban is **pre-installed** but WordPress-specific jails are disabled by default.

### What It Does

- Monitors Nginx access logs for failed wp-login.php attempts
- Automatically blocks IPs after threshold is reached (default: 6 failed attempts)
- Temporary bans (default: 10 minutes) prevent permanent lockouts
- Works at firewall level (UFW) - blocked IPs can't even reach Nginx
- Zero maintenance required once configured

### Why Use fail2ban Instead of Manual IP Blocks

| Approach | Pros | Cons |
|----------|------|------|
| **fail2ban (automatic)** | ✅ Zero maintenance<br>✅ Catches new attackers instantly<br>✅ Temporary bans avoid false positives<br>✅ Already installed in Trellis | ⚠️ Requires initial configuration |
| **Manual IP blocks** | ✅ Permanent blocks<br>✅ Complete control | ❌ Constant maintenance<br>❌ Risk of blocking yourself<br>❌ Attackers rotate IPs anyway |

**Recommendation**: Use fail2ban as primary defense, manual blocks only for extreme cases.

---

## Quick Start

### 1. Enable WordPress Protection

Edit `trellis/group_vars/all/security.yml`:

```yaml
# Enable fail2ban WordPress protection
fail2ban_services_custom:
  - name: wordpress_wp_login
    filter: wordpress-wp-login
    enabled: "true"  # ← Change from "false" to "true"
    port: http,https
    logpath: "{{ www_root }}/**/logs/access.log"
```

### 2. Apply Configuration

```bash
cd trellis
trellis provision --tags fail2ban production
```

This will:
1. Update fail2ban jail configurations
2. Restart fail2ban service
3. Immediately start protecting WordPress login pages

### 3. Verify It's Working

```bash
# Check fail2ban status
ssh admin_user@yoursite.com "sudo fail2ban-client status"

# Check WordPress jail specifically
ssh admin_user@yoursite.com "sudo fail2ban-client status wordpress_wp_login"
```

**Expected output:**
```
Status for the jail: wordpress_wp_login
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     4
|  `- File list:        /srv/www/yoursite.com/logs/access.log
`- Actions
   |- Currently banned: 0
   |- Total banned:     1
   `- Banned IP list:
```

---

## Configuration

### Settings Location

All fail2ban settings are in `trellis/group_vars/all/security.yml`:

```yaml
# Ban duration (seconds)
fail2ban_bantime: 600  # 10 minutes

# Failed attempts before ban
fail2ban_maxretry: 6

# Time window for counting attempts (seconds)
fail2ban_findtime: 600  # 10 minutes

# WordPress-specific jails
fail2ban_services_custom:
  - name: wordpress_wp_login
    filter: wordpress-wp-login
    enabled: "true"
    port: http,https
    logpath: "{{ www_root }}/**/logs/access.log"
```

### Recommended Settings

**Default (Recommended):**
- `bantime: 600` (10 minutes)
- `maxretry: 6` (6 failed attempts)
- `findtime: 600` (10 minute window)

**Stricter Protection:**
```yaml
fail2ban_bantime: 1800    # 30 minutes
fail2ban_maxretry: 3      # 3 failed attempts
fail2ban_findtime: 300    # 5 minute window
```

**More Lenient:**
```yaml
fail2ban_bantime: 300     # 5 minutes
fail2ban_maxretry: 10     # 10 failed attempts
fail2ban_findtime: 600    # 10 minute window
```

### Applying Configuration Changes

After modifying `security.yml`:

```bash
cd trellis
trellis provision --tags fail2ban production
```

**Note**: This only updates fail2ban configuration, doesn't run full server provisioning.

---

## Available WordPress Jails

### wordpress_wp_login (Recommended)

**Purpose**: Blocks brute force attacks on wp-login.php

**Enable in** `security.yml`:
```yaml
- name: wordpress_wp_login
  filter: wordpress-wp-login
  enabled: "true"
  port: http,https
  logpath: "{{ www_root }}/**/logs/access.log"
```

**What it detects:**
- Failed login attempts (POST to wp-login.php with 200 status)
- Repeated authentication failures
- Password brute forcing

**Recommended**: ✅ **Enable this** - critical for WordPress security

### wordpress_xmlrpc (Usually Not Needed)

**Purpose**: Blocks XML-RPC brute force attacks

**Note**: If you already block XML-RPC at Nginx level (recommended), this jail is redundant.

**Check if you need it:**
```bash
# Test if XML-RPC is blocked
curl -I https://yoursite.com/xmlrpc.php

# If you see "444 No Response" or "403 Forbidden", you don't need this jail
```

**Enable only if** XML-RPC is publicly accessible:
```yaml
- name: wordpress_xmlrpc
  filter: wordpress-xmlrpc
  enabled: "true"
  port: http,https
  logpath: "{{ www_root }}/**/logs/access.log"
```

---

## Monitoring & Management

### Check Status

**Overall fail2ban status:**
```bash
# SSH in first (admin user requires password for sudo)
ssh admin_user@yoursite.com

# Then run commands
sudo fail2ban-client status
```

**WordPress jail status:**
```bash
ssh admin_user@yoursite.com
sudo fail2ban-client status wordpress_wp_login
```

**Example output:**
```
Status for the jail: wordpress_wp_login
|- Filter
|  |- Currently failed: 2
|  |- Total failed:     47
|  `- File list:        /srv/www/imagewize.com/logs/access.log
                        /srv/www/demo.imagewize.com/logs/access.log
`- Actions
   |- Currently banned: 1
   |- Total banned:     12
   `- Banned IP list:   167.99.215.209
```

### View Banned IPs

```bash
ssh admin_user@yoursite.com
sudo fail2ban-client get wordpress_wp_login banip
```

### View fail2ban Logs

**Recent activity (last 50 lines):**
```bash
ssh admin_user@yoursite.com
sudo tail -50 /var/log/fail2ban.log
```

**Watch live (real-time monitoring):**
```bash
ssh admin_user@yoursite.com
sudo tail -f /var/log/fail2ban.log
```

**Search for specific IP:**
```bash
ssh admin_user@yoursite.com
sudo grep '167.99.215.209' /var/log/fail2ban.log
```

### Manual IP Management

**Ban an IP immediately:**
```bash
ssh admin_user@yoursite.com
sudo fail2ban-client set wordpress_wp_login banip 192.168.1.100
```

**Unban an IP (if locked yourself out):**
```bash
# Use server console if completely locked out
ssh admin_user@yoursite.com
sudo fail2ban-client set wordpress_wp_login unbanip 1.2.3.4
```

**Unban all IPs (emergency):**
```bash
ssh admin_user@yoursite.com
sudo fail2ban-client unban --all
```

---

## Preventing Self-Lockout

### IP Whitelist

Prevent fail2ban from banning your own IP address by adding it to the whitelist in `security.yml`:

```yaml
# IP addresses that will NEVER be banned by fail2ban
ip_whitelist:
  - 127.0.0.0/8              # Localhost
  - "{{ ipify_public_ip | default('') }}"  # Provisioning machine IP
  - 1.2.213.123              # Your static IP (example)
  - 203.0.113.0/24           # Your office network (example)
```

**Apply changes:**
```bash
cd trellis
trellis provision --tags fail2ban production
```

### If You Get Locked Out

**Option 1: Unban from different IP**

If you have access from another IP:
```bash
ssh admin_user@yoursite.com "sudo fail2ban-client set wordpress_wp_login unbanip YOUR.IP.HERE"
```

**Option 2: Disable fail2ban temporarily**

Via server console/VPS control panel:
```bash
sudo systemctl stop fail2ban
# Try logging in
sudo systemctl start fail2ban
```

**Option 3: Add to whitelist via server console**

Edit `/etc/fail2ban/jail.local` and add under `[DEFAULT]`:
```ini
ignoreip = 127.0.0.1/8 YOUR.IP.HERE
```

Then restart:
```bash
sudo systemctl restart fail2ban
```

---

## Troubleshooting

### Check if fail2ban is Running

```bash
ssh admin_user@yoursite.com
sudo systemctl status fail2ban
```

**Expected:**
```
● fail2ban.service - Fail2Ban Service
   Loaded: loaded (/lib/systemd/system/fail2ban.service; enabled)
   Active: active (running) since Wed 2026-01-01 02:33:13 UTC; 1h 23min ago
```

### Restart fail2ban

```bash
ssh admin_user@yoursite.com
sudo systemctl restart fail2ban
```

### Check Configuration Syntax

```bash
ssh admin_user@yoursite.com
sudo fail2ban-client -d
```

### View Which Logs Are Monitored

```bash
ssh admin_user@yoursite.com
sudo fail2ban-client get wordpress_wp_login logpath
```

**Expected:**
```
/srv/www/yoursite.com/logs/access.log
/srv/www/demo.yoursite.com/logs/access.log
```

### Test Filter Pattern

Test if fail2ban can detect failures in your logs:

```bash
# On production server
ssh admin_user@yoursite.com
sudo fail2ban-regex /srv/www/yoursite.com/logs/access.log /etc/fail2ban/filter.d/wordpress-wp-login.conf
```

**Look for:**
```
Lines: 15234 lines, 0 ignored, 47 matched, 15187 missed
```

If "matched" shows failed login attempts, filter is working correctly.

### Common Issues

**Issue**: fail2ban not banning attackers

**Causes**:
1. Jail not enabled (`enabled: "false"` in security.yml)
2. Threshold not reached yet (need 6 failed attempts by default)
3. Logpath incorrect or logs not accessible
4. Filter pattern doesn't match log format

**Solution**:
```bash
# 1. Check jail is enabled
ssh admin_user@yoursite.com
sudo fail2ban-client status | grep wordpress

# 2. Check log file exists and has content (can use web user, no sudo needed)
ssh web@yoursite.com "tail /srv/www/yoursite.com/logs/access.log"

# 3. Test filter pattern (see above)
ssh admin_user@yoursite.com
sudo fail2ban-regex /srv/www/yoursite.com/logs/access.log /etc/fail2ban/filter.d/wordpress-wp-login.conf

# 4. Check for errors
ssh admin_user@yoursite.com
sudo grep ERROR /var/log/fail2ban.log | tail -20
```

---

## Integration with WordPress Scanners

fail2ban complements the [wp-cli/security](../../wp-cli/security/) malware scanners:

### Security Workflow

**1. Prevent attacks (fail2ban)**
```bash
# fail2ban runs automatically, no action needed
# View activity:
ssh admin_user@yoursite.com
sudo tail -20 /var/log/fail2ban.log
```

**2. Detect malware (security scanners)**
```bash
# Weekly scan for malware
wp eval-file wp-cli/security/scanner-targeted.php
```

**3. Analyze attack patterns (access logs)**
```bash
# View failed login attempts
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | tail -50"
```

---

## Real-World Statistics

### Production Site Analysis (imagewize.com)

**Period**: November-December 2025 (before fail2ban enabled)

**Attacks observed**:
- 1,420 wp-login attempts from single IP (62.60.130.228)
- 860 wp-login attempts from single IP (141.98.11.120)
- 742 wp-login attempts from single IP (91.224.92.114)
- 40+ unique attacker IPs identified
- Average: 20-200 failed login attempts per attacker

**Result**: With fail2ban enabled (6 attempts = ban), **all of these would have been blocked automatically** after their 6th attempt.

### After Enabling fail2ban (2026-01-01)

**First detection** (within 7 hours):
```
2026-01-01 02:26:08 - Found 167.99.215.209 (DigitalOcean VPS, US)
```

fail2ban is now automatically protecting against brute force attacks.

---

## Manual IP Blocking (Advanced)

While fail2ban handles most cases, manual Nginx IP blocks may be needed for:

1. **Extreme high-volume attacks** (1,000+ requests/minute from single IP)
2. **Distributed attacks** that don't trigger fail2ban thresholds
3. **Known persistent attackers** that keep returning

### Creating Manual Blocks

See [MANUAL-IP-BLOCKING.md](./MANUAL-IP-BLOCKING.md) for permanent IP blocking via Nginx.

---

## Quick Reference

### Enable WordPress Protection

```bash
# 1. Edit trellis/group_vars/all/security.yml
# Set wordpress_wp_login enabled: "true"

# 2. Apply
cd trellis && trellis provision --tags fail2ban production
```

### Monitor Activity

```bash
# Overall status
ssh admin_user@yoursite.com
sudo fail2ban-client status

# WordPress jail
sudo fail2ban-client status wordpress_wp_login

# View logs
sudo tail -50 /var/log/fail2ban.log
```

### Manage Bans

```bash
# SSH in first (admin user requires password for sudo)
ssh admin_user@yoursite.com

# Ban IP
sudo fail2ban-client set wordpress_wp_login banip 1.2.3.4

# Unban IP
sudo fail2ban-client set wordpress_wp_login unbanip 1.2.3.4

# Unban all
sudo fail2ban-client unban --all
```

### Emergency Disable

```bash
ssh admin_user@yoursite.com
sudo systemctl stop fail2ban
```

---

## Resources

- [Trellis Security Documentation](https://roots.io/trellis/docs/security/)
- [fail2ban Official Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [fail2ban WordPress Filter Source](https://github.com/fail2ban/fail2ban/blob/master/config/filter.d/wordpress-auth.conf)
- [wp-ops Security Scanners](../../wp-cli/security/)

---

**Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations**
