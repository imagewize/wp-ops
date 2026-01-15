# Trellis Security

WordPress security tools and configurations for Trellis-managed servers.

## Chapter Purpose

This chapter outlines the layered security controls used in Trellis environments and how to apply them safely.

Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations and server management.

---

## Important: SSH User for Admin Commands

**Note**: Commands in this guide use `admin_user` as a placeholder for your Trellis admin username.

- Trellis creates admin users via `group_vars/{env}/users.yml`
- Admin users have sudo access (require password for sudo commands)
- **Replace `admin_user` with your configured username** (e.g., `warden`, `deploy`, your name, etc.)
- Example: If your admin user is `warden`, use `ssh warden@yoursite.com`

For read-only operations (viewing logs), use the `web` user which doesn't require sudo:
- `ssh web@yoursite.com` - No sudo access, can read site files and logs

---

## Overview

This directory contains documentation and configurations for securing WordPress sites on Trellis infrastructure.

### Security Layers

```
┌─────────────────────────────────────────┐
│  Layer 1: Firewall (UFW)                │ ← fail2ban blocks IPs here
├─────────────────────────────────────────┤
│  Layer 2: Nginx (deny rules)            │ ← Manual IP blocks
├─────────────────────────────────────────┤
│  Layer 3: WordPress (plugins)           │ ← Wordfence, etc.
├─────────────────────────────────────────┤
│  Layer 4: Application (code)            │ ← Security scanners
└─────────────────────────────────────────┘
```

### Tools Covered

| Tool | Purpose | Maintenance | Docs |
|------|---------|-------------|------|
| **fail2ban** | Automatic IP blocking for brute force attacks | Zero (once configured) | [FAIL2BAN.md](./FAIL2BAN.md) |
| **Manual IP blocks** | Permanent Nginx-level IP blocking | Manual updates required | [MANUAL-IP-BLOCKING.md](./MANUAL-IP-BLOCKING.md) |
| **Security scanners** | Malware detection for WordPress | Run weekly/monthly | [wp-cli/security](../../wp-cli/security/) |

---

## Quick Start

### 1. Enable fail2ban WordPress Protection

**Recommended first step** for all WordPress sites.

```bash
# Edit trellis/group_vars/all/security.yml
# Set wordpress_wp_login enabled: "true"

# Apply
cd trellis
trellis provision --tags fail2ban production
```

**See**: [FAIL2BAN.md](./FAIL2BAN.md) for complete setup guide.

### 2. Monitor Security Activity

```bash
# Check fail2ban status (admin user requires password for sudo)
ssh admin_user@yoursite.com
sudo fail2ban-client status wordpress_wp_login

# View recent bans
sudo tail -50 /var/log/fail2ban.log

# Analyze attack patterns (web user, no sudo needed)
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20"
```

### 3. Run Security Scans

```bash
# Weekly malware scan
wp eval-file wp-cli/security/scanner-targeted.php

# Monthly deep scan
wp eval-file wp-cli/security/scanner-general.php
```

**See**: [wp-cli/security](../../wp-cli/security/) for scanner documentation.

---

## Documentation

### Automatic Protection

- **[FAIL2BAN.md](./FAIL2BAN.md)** - Automatic IP blocking for brute force attacks
  - Setup and configuration
  - Monitoring and management
  - Troubleshooting
  - Real-world statistics

### Manual Protection (Advanced)

- **[MANUAL-IP-BLOCKING.md](./MANUAL-IP-BLOCKING.md)** - Permanent Nginx IP blocks
  - When to use manual blocks vs fail2ban
  - Creating deny-ips.conf.j2
  - Managing IP lists
  - Known attacker reference list

### Application-Level Security

- **[wp-cli/security](../../wp-cli/security/)** - WordPress malware scanners
  - Targeted scanner (site-specific threats)
  - General scanner (broad malware detection)
  - Integration with fail2ban workflow

---

## Recommended Security Strategy

### For Most WordPress Sites

**Primary Defense**: fail2ban (automatic)
```yaml
# trellis/group_vars/all/security.yml
fail2ban_services_custom:
  - name: wordpress_wp_login
    enabled: "true"  # ← Enable this
```

**Regular Monitoring**:
- Weekly security scans with [scanner-targeted.php](../../wp-cli/security/)
- Monthly fail2ban log reviews
- Quarterly review of attack patterns

**Manual IP blocks**: Only for extreme cases (see criteria below)

### When to Add Manual IP Blocks

Use manual Nginx IP blocks **only** when:

1. ✅ **Extreme high-volume attack** - Single IP sending 1,000+ requests/minute
2. ✅ **Distributed attack** - Many IPs coordinating attack (doesn't trigger fail2ban thresholds)
3. ✅ **Known persistent attacker** - IP keeps returning after fail2ban bans expire

**Don't use manual blocks for**:
- ❌ Regular brute force attempts (fail2ban handles this)
- ❌ One-time attackers (fail2ban temporary ban is sufficient)
- ❌ IPs that might be shared (VPNs, corporate networks, etc.)

---

## Security Workflow

### Weekly Routine

```bash
# 1. Run security scanner (1-2 seconds)
wp eval-file wp-cli/security/scanner-targeted.php

# 2. Check fail2ban activity (optional)
ssh admin_user@yoursite.com
sudo fail2ban-client status wordpress_wp_login
```

### Monthly Deep Dive

```bash
# 1. Deep malware scan (2-3 seconds)
wp eval-file wp-cli/security/scanner-general.php

# 2. Review fail2ban logs
ssh admin_user@yoursite.com
sudo tail -100 /var/log/fail2ban.log

# 3. Analyze attack patterns (web user, no sudo)
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20"

# 4. Update WordPress and plugins
wp core update
wp plugin update --all
```

### After Suspected Compromise

```bash
# 1. Full security scan
wp eval-file wp-cli/security/scanner-wrapper.php

# 2. Check for suspicious users
wp user list --role=administrator

# 3. Verify core files
wp core verify-checksums

# 4. Check plugin integrity
wp plugin verify-checksums --all

# 5. Review recent file changes
ssh web@yoursite.com "find /srv/www/yoursite.com/current/web/wp-content -mtime -7 -type f"

# 6. Analyze access logs for unusual patterns
ssh web@yoursite.com "tail -1000 /srv/www/yoursite.com/logs/access.log | grep -v 'GET /' | grep -v '.css' | grep -v '.js'"
```

---

## Real-World Examples

### Case Study: imagewize.com

**Before fail2ban** (November-December 2025):
- 1,420 wp-login attempts from single IP (62.60.130.228)
- 860 wp-login attempts from single IP (141.98.11.120)
- 742 wp-login attempts from single IP (91.224.92.114)
- 40+ unique attacker IPs identified
- **No automatic blocking** - attacks continued unabated

**After fail2ban enabled** (2026-01-01):
- First attacker detected within 7 hours (167.99.215.209)
- **Automatic blocking** after 6 failed attempts
- 10-minute temporary bans deter most attackers
- Zero maintenance required

**Outcome**: All previous attacks would have been stopped after 6 attempts instead of hundreds.

### Typical Attack Pattern

**What fail2ban detects:**
```
2026-01-01 02:26:08 [wordpress_wp_login] Found 167.99.215.209
2026-01-01 02:26:15 [wordpress_wp_login] Found 167.99.215.209
2026-01-01 02:26:22 [wordpress_wp_login] Found 167.99.215.209
2026-01-01 02:26:29 [wordpress_wp_login] Found 167.99.215.209
2026-01-01 02:26:36 [wordpress_wp_login] Found 167.99.215.209
2026-01-01 02:26:43 [wordpress_wp_login] Found 167.99.215.209 ← 6th attempt
2026-01-01 02:26:43 [wordpress_wp_login] Ban 167.99.215.209  ← BANNED
```

**Without fail2ban** (before 2026-01-01):
- Same IP would continue attempting hundreds or thousands of times
- Server resources wasted processing login attempts
- Increased risk of successful brute force

---

## Configuration Files

### Trellis Security Configuration

All security settings are in `trellis/group_vars/all/security.yml`:

```yaml
# fail2ban settings
fail2ban_bantime: 600          # 10 minutes
fail2ban_maxretry: 6           # 6 failed attempts
fail2ban_findtime: 600         # 10 minute window

# IP whitelist (never ban these IPs)
ip_whitelist:
  - 127.0.0.0/8
  - "{{ ipify_public_ip | default('') }}"
  - 1.2.213.123  # Your static IP (example)

# fail2ban jails
fail2ban_services_custom:
  - name: wordpress_wp_login
    filter: wordpress-wp-login
    enabled: "true"              # ← Set to "true" to enable
    port: http,https
    logpath: "{{ www_root }}/**/logs/access.log"

  # Optional: XML-RPC protection (usually not needed if blocked at Nginx level)
  # - name: wordpress_xmlrpc
  #   filter: wordpress-xmlrpc
  #   enabled: "false"
  #   port: http,https
  #   logpath: "{{ www_root }}/**/logs/access.log"
```

### Manual IP Blocks (Optional)

For extreme cases only, create `trellis/nginx-includes/all/deny-ips.conf.j2`:

```nginx
# Manual IP deny list
# Only use for extreme high-volume attacks

deny 1.2.3.4;  # Description: reason for block
```

**See**: [MANUAL-IP-BLOCKING.md](./MANUAL-IP-BLOCKING.md) for details.

---

## Monitoring Commands

### Quick Status Check

```bash
# SSH in first (admin user requires password for sudo)
ssh admin_user@yoursite.com

# Is fail2ban running?
sudo systemctl status fail2ban

# WordPress jail status
sudo fail2ban-client status wordpress_wp_login

# Currently banned IPs
sudo fail2ban-client get wordpress_wp_login banip
```

### Analyze Attack Activity

```bash
# Top 20 IPs attempting wp-login
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20"

# Recent fail2ban bans
ssh admin_user@yoursite.com "sudo grep 'Ban ' /var/log/fail2ban.log | tail -20"

# How many requests were blocked by Nginx deny rules
ssh admin_user@yoursite.com "sudo grep 'access forbidden' /var/log/nginx/error.log | wc -l"
```

### Check for Malware

```bash
# Quick scan (1-2 seconds)
wp eval-file wp-cli/security/scanner-targeted.php

# Deep scan (2-3 seconds)
wp eval-file wp-cli/security/scanner-general.php
```

---

## Troubleshooting

### I Locked Myself Out

**Symptom**: Can't access your WordPress site (403 Forbidden)

**If banned by fail2ban**:
```bash
# Unban your IP
ssh admin_user@yoursite.com "sudo fail2ban-client set wordpress_wp_login unbanip YOUR.IP.HERE"

# Prevent future bans - add to whitelist in security.yml
ip_whitelist:
  - YOUR.IP.HERE
```

**If blocked by manual deny rule**:
```bash
# Via VPS console (not SSH)
sudo nano /etc/nginx/includes.d/all/deny-ips.conf
# Comment out or delete your IP
sudo systemctl reload nginx
```

### Attacker Not Being Blocked

**Possible causes**:

1. **fail2ban jail not enabled**
   ```bash
   # Check status
   ssh admin_user@yoursite.com "sudo fail2ban-client status"
   # Should list "wordpress_wp_login" - if not, it's disabled
   ```

2. **Attacker hasn't reached threshold yet**
   - Default: 6 failed attempts required for ban
   - Check: `sudo grep 'Found.*wp-login' /var/log/fail2ban.log | grep 'ATTACKER.IP.HERE'`

3. **Attacker rotating IPs**
   - Each new IP needs 6 attempts before ban
   - Solution: Manual block for the IP range (if persistent)

4. **Log file not being monitored**
   ```bash
   # Check which logs fail2ban is watching
   ssh admin_user@yoursite.com "sudo fail2ban-client get wordpress_wp_login logpath"
   ```

### fail2ban Not Starting

```bash
# Check for errors
ssh admin_user@yoursite.com "sudo systemctl status fail2ban"
ssh admin_user@yoursite.com "sudo journalctl -u fail2ban -n 50"

# Test configuration
ssh admin_user@yoursite.com "sudo fail2ban-client -d"

# Restart
ssh admin_user@yoursite.com "sudo systemctl restart fail2ban"
```

---

## Best Practices

### 1. Layer Your Security

Don't rely on a single tool. Use multiple layers:

- ✅ fail2ban (firewall-level blocking)
- ✅ Strong passwords (WordPress user accounts)
- ✅ 2FA (two-factor authentication)
- ✅ Security plugin (Wordfence, iThemes Security)
- ✅ Regular updates (WordPress core, plugins, themes)
- ✅ Security scans (weekly/monthly)
- ✅ Backups (automated daily/weekly)

### 2. Monitor Regularly

```bash
# Weekly: Check fail2ban activity
ssh admin_user@yoursite.com "sudo fail2ban-client status wordpress_wp_login"

# Monthly: Analyze attack patterns
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20"
```

### 3. Keep Security Configs in Version Control

All security configurations live in Git (Trellis repository):
- ✅ `group_vars/all/security.yml` (fail2ban config)
- ✅ `nginx-includes/all/deny-ips.conf.j2` (manual IP blocks)
- ✅ Changes tracked in Git history
- ✅ Easy rollback if needed

### 4. Test Before Deploying

```bash
# Always test Nginx config changes
cd trellis
ansible-playbook server.yml -e env=production --tags nginx --check

# Then deploy
trellis provision --tags nginx production
```

### 5. Document Everything

When adding manual IP blocks, always include:
- Why is this IP blocked?
- When was it observed?
- What was the attack pattern?

```nginx
# ✅ Good
deny 62.60.130.228;   # 1,420 wp-login attempts, Nov 2025, Kamatera NL

# ❌ Bad
deny 62.60.130.228;
```

---

## Related Documentation

### Security Tools
- **[wp-cli/security](../../wp-cli/security/)** - WordPress malware scanners
- **[troubleshooting/](../../troubleshooting/)** - Server troubleshooting guides

### Trellis Operations
- **[trellis/backup](../backup/)** - Database and file backups
- **[trellis/monitoring](../monitoring/)** - Server monitoring tools
- **[trellis/provision](../provision/)** - Server provisioning guides

### External Resources
- [Trellis Security Documentation](https://roots.io/trellis/docs/security/)
- [fail2ban Official Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [WordPress Security Best Practices](https://wordpress.org/support/article/hardening-wordpress/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

---

## Quick Reference

### Enable fail2ban

```bash
# 1. Edit security.yml
# Set wordpress_wp_login enabled: "true"

# 2. Apply
cd trellis && trellis provision --tags fail2ban production
```

### Add Manual IP Block

```bash
# 1. Create/edit file
nano trellis/nginx-includes/all/deny-ips.conf.j2

# 2. Add IP
# deny 1.2.3.4;  # Description

# 3. Deploy
cd trellis && trellis provision --tags nginx production
```

### Run Security Scan

```bash
# Quick scan
wp eval-file wp-cli/security/scanner-targeted.php

# Deep scan
wp eval-file wp-cli/security/scanner-general.php
```

### Check Security Status

```bash
# fail2ban status (admin user requires password for sudo)
ssh admin_user@yoursite.com
sudo fail2ban-client status wordpress_wp_login

# Recent attacks (web user, no sudo)
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | tail -50"
```

---

**Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations**
