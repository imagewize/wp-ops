# Manual IP Blocking via Nginx

Permanent IP blocking at the Nginx level for extreme cases.

Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations and server management.

**Note**: Commands in this guide use `admin_user` as a placeholder for your Trellis admin username.

- **Replace `admin_user` with your configured username** (e.g., `admin`, `deploy`, `warden`, your name, etc.)
- Example: If your admin user is `admin`, use `ssh admin@yoursite.com`

---

## Overview

**Manual IP blocking** via Nginx `deny` directives provides **permanent** IP blocks at the web server level. This is an advanced technique that should only be used when [fail2ban](./FAIL2BAN.md) automatic blocking is insufficient.

### When to Use Manual IP Blocks

| Scenario | Use fail2ban | Use Manual Blocks |
|----------|--------------|-------------------|
| Brute force wp-login attempts | ✅ Recommended | ❌ Not needed |
| XML-RPC abuse | ✅ Recommended | ❌ Not needed |
| Extreme high-volume attack (1,000+ req/min) | ⚠️ May not be fast enough | ✅ Yes |
| Distributed attack (many IPs) | ✅ Catches them individually | ❌ Too many to manage |
| Known persistent attacker | ✅ Auto-rebans | ✅ For permanent block |
| Attack on non-WordPress URLs | ❌ Can't detect | ✅ Yes, if needed |

### Pros and Cons

**Manual IP Blocks:**
- ✅ Permanent blocks (persist across reboots)
- ✅ Very fast (processed early in Nginx request handling)
- ✅ Works for any URL pattern
- ✅ Version controlled (in Trellis repository)
- ❌ Requires manual maintenance
- ❌ Risk of blocking yourself
- ❌ Attackers rotate IPs anyway

**fail2ban (Recommended):**
- ✅ Automatic detection and blocking
- ✅ Zero maintenance
- ✅ Temporary bans avoid false positives
- ✅ Already installed in Trellis
- ⚠️ Requires initial configuration

**Recommendation**: Use fail2ban as primary defense. Only use manual blocks for extreme cases.

---

## Implementation

### 1. Create deny-ips.conf.j2

Create `trellis/nginx-includes/all/deny-ips.conf.j2`:

```nginx
# Nginx IP Deny List for WordPress Security
# Managed via: trellis/nginx-includes/all/deny-ips.conf.j2
# Last updated: {{ ansible_date_time.date }}
#
# Apply changes: cd trellis && trellis provision --tags nginx production
#
# IMPORTANT: Always verify IPs before adding to avoid blocking legitimate traffic
# Check IP ownership: whois <IP>
# Check geolocation: https://whatismyipaddress.com/ip/<IP>

# Example format:
# deny 192.168.1.100;  # Description/reason for block

# Add your IP blocks below:
deny 62.60.130.228;   # 1,420 wp-login attempts (Nov 2025)
deny 141.98.11.120;   # 860 wp-login attempts (Nov 2025)
deny 91.224.92.114;   # 742 wp-login attempts (Nov 2025)
```

**Template features:**
- Ansible variable `{{ ansible_date_time.date }}` shows when it was last deployed
- Comments document why each IP is blocked
- Lives in version control (Git)

### 2. Apply Configuration

```bash
cd trellis
trellis provision --tags nginx production
```

This will:
1. Template `deny-ips.conf.j2` to `/etc/nginx/includes.d/all/deny-ips.conf`
2. Test Nginx configuration for syntax errors
3. Reload Nginx to apply new blocks

**Verify:**
```bash
# Check Nginx reloaded successfully
ssh admin_user@yoursite.com "sudo systemctl status nginx"

# Test blocked IP (from your machine, not the blocked IP!)
curl -I https://yoursite.com -H "X-Forwarded-For: 62.60.130.228"
# Should return: 403 Forbidden
```

### 3. Test Before Deploying

**Always test Nginx config after editing:**

```bash
# After editing deny-ips.conf.j2 locally
cd trellis
ansible-playbook server.yml -e env=production --tags nginx --check
```

The `--check` flag runs in dry-run mode (no changes applied).

---

## Adding/Removing IPs

### Add IP Block

1. **Research the IP first:**
```bash
# Check who owns it
whois 1.2.3.4

# Check geolocation
curl "https://ipapi.co/1.2.3.4/json/"
```

2. **Add to deny-ips.conf.j2:**
```nginx
deny 1.2.3.4;  # Description: reason for block, date observed
```

3. **Deploy:**
```bash
cd trellis
trellis provision --tags nginx production
```

### Remove IP Block

1. **Delete or comment out the line:**
```nginx
# deny 1.2.3.4;  # Removed: reason for unblocking
```

2. **Deploy:**
```bash
cd trellis
trellis provision --tags nginx production
```

### Bulk Add IPs

For multiple IPs from log analysis:

```bash
# Example: Extract top 20 wp-login attackers
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20"

# Output:
#    1420 62.60.130.228
#     860 141.98.11.120
#     742 91.224.92.114
#     ...
```

Add to `deny-ips.conf.j2`:
```nginx
deny 62.60.130.228;   # 1,420 wp-login attempts
deny 141.98.11.120;   # 860 wp-login attempts
deny 91.224.92.114;   # 742 wp-login attempts
```

---

## File Organization

### Directory Structure

Trellis supports multiple nginx-includes locations:

```
trellis/nginx-includes/
├── all/                    # Applied to ALL sites (development, staging, production)
│   └── deny-ips.conf.j2   # ← IP blocks for all environments
├── development/            # Development-only
├── staging/                # Staging-only
└── production/             # Production-only
    └── deny-ips.conf.j2   # ← Alternatively, production-only blocks
```

**Recommendation**: Use `all/` for IP blocks unless you have different attackers per environment.

### Why .j2 Extension?

`.j2` = Jinja2 template. Allows Ansible variables like:

```nginx
# Last deployed: {{ ansible_date_time.iso8601 }}
# Server: {{ ansible_hostname }}
```

These get replaced with actual values during provisioning.

---

## Advanced Usage

### Block IP Ranges (CIDR)

```nginx
# Block entire subnet
deny 192.168.1.0/24;  # Blocks 192.168.1.0 - 192.168.1.255

# Block larger range
deny 10.0.0.0/8;      # Blocks 10.0.0.0 - 10.255.255.255
```

**Caution**: Only block ranges if you're certain. Blocking cloud provider ranges (AWS, DigitalOcean, etc.) will block many legitimate users.

### Allow Specific IPs (Whitelist)

```nginx
# Block everyone except whitelisted IPs
# (Use with extreme caution!)

# Allow specific IPs
allow 1.2.3.4;         # Your IP
allow 5.6.7.8;         # Office IP

# Block all others
deny all;
```

**Warning**: This blocks ALL traffic except whitelisted IPs. Only use for maintenance mode or staging sites.

### Conditional Blocking

Block IPs only for specific locations:

Create `trellis/nginx-includes/all/deny-ips-wp-admin.conf.j2`:

```nginx
# Block attackers from accessing /wp-admin only
location ~ ^/wp-admin {
    deny 62.60.130.228;
    deny 141.98.11.120;

    # Allow all others to proceed
    try_files $uri $uri/ /index.php?$args;
}
```

**Use case**: Block known attackers from admin area while still allowing them to view public site.

---

## Monitoring Blocked IPs

### View Active deny Rules

```bash
ssh admin_user@yoursite.com "cat /etc/nginx/includes.d/all/deny-ips.conf"
```

### Check Nginx Error Log

When an IP is blocked, Nginx logs it:

```bash
ssh admin_user@yoursite.com "sudo grep 'access forbidden' /var/log/nginx/error.log | tail -20"
```

**Example log entry:**
```
2026/01/01 12:34:56 [error] 12345#12345: *67890 access forbidden by rule,
client: 62.60.130.228, server: imagewize.com, request: "POST /wp-login.php HTTP/1.1"
```

### Count Blocked Requests

```bash
# How many requests were blocked from each IP
ssh admin_user@yoursite.com "sudo grep 'access forbidden' /var/log/nginx/error.log | awk '{print \$13}' | sort | uniq -c | sort -rn"
```

**Example output:**
```
    847 62.60.130.228,
    592 141.98.11.120,
    301 91.224.92.114,
```

Shows blocking is working!

---

## Preventing Self-Lockout

### Check Your Current IP

**Before adding any blocks:**

```bash
# From your local machine
curl https://ipinfo.io/ip
```

**Never block your own IP!**

### Whitelist Your IP

Add to top of `deny-ips.conf.j2`:

```nginx
# WHITELIST - IPs that should NEVER be blocked
# (These must come BEFORE any deny rules)

allow 1.2.213.123;    # My Jakarta IP
allow 203.0.113.0/24; # Office network

# BLOCKLIST - Attackers
deny 62.60.130.228;
deny 141.98.11.120;
```

**Order matters**: Nginx processes `allow` and `deny` in order. Put `allow` first.

### Recovery If Locked Out

**Option 1: Remove blocks via VPS console**

Most VPS providers (DigitalOcean, Linode, etc.) offer web-based console access:

```bash
# Login via VPS console
sudo nano /etc/nginx/includes.d/all/deny-ips.conf

# Comment out your IP or delete the file
sudo systemctl reload nginx
```

**Option 2: Use fail2ban instead**

fail2ban supports IP whitelisting via `ip_whitelist` in `security.yml` (see [FAIL2BAN.md](./FAIL2BAN.md)).

---

## Troubleshooting

### Nginx Won't Reload After Adding deny Rule

**Cause**: Syntax error in deny-ips.conf.j2

**Solution**:
```bash
# Test Nginx config before deploying
ssh admin_user@yoursite.com "sudo nginx -t"

# Look for error message
# Example: "unknown directive" means syntax error
```

**Common mistakes**:
```nginx
# ❌ Wrong - missing semicolon
deny 1.2.3.4

# ✅ Correct
deny 1.2.3.4;

# ❌ Wrong - invalid IP format
deny 1.2.3.256;

# ✅ Correct
deny 1.2.3.4;
```

### Legitimate User Blocked

**Symptom**: User reports "403 Forbidden" on your site

**Check if their IP is blocked:**
```bash
# Get their IP (ask them to visit https://ipinfo.io/ip)
# Example: 5.6.7.8

# Check if it's in deny list
ssh admin_user@yoursite.com "grep '5.6.7.8' /etc/nginx/includes.d/all/deny-ips.conf"
```

**If found, remove it:**

1. Edit `trellis/nginx-includes/all/deny-ips.conf.j2`
2. Remove or comment out the line
3. Deploy: `cd trellis && trellis provision --tags nginx production`

### Block Not Working

**Symptom**: Attacker still accessing site despite being in deny list

**Check deployed config:**
```bash
ssh admin_user@yoursite.com "cat /etc/nginx/includes.d/all/deny-ips.conf | grep '62.60.130.228'"
```

**If not there:**
- Did you run `trellis provision --tags nginx`?
- Check for typos in IP address
- Ensure file is in correct location (`nginx-includes/all/`)

**If there but still not blocked:**
- Attacker might be using a different IP (check logs)
- Attacker might be using a proxy/VPN (check X-Forwarded-For header)

---

## Reference: Known Attacker IPs (imagewize.com)

From production logs analysis (November-December 2025):

```nginx
# Top 20 wp-login brute force attackers (by attempt count)
# These IPs would be automatically blocked by fail2ban after 6 attempts

deny 62.60.130.228;   # 1,420 attempts - Kamatera, Netherlands
deny 141.98.11.120;   # 860 attempts - Giganet, UK
deny 91.224.92.114;   # 742 attempts - G-Core Labs, Luxembourg
deny 80.94.92.167;    # 628 attempts - Giganet, UK
deny 80.94.92.177;    # 502 attempts - Giganet, UK
deny 88.119.161.116;  # 467 attempts - M247, UK
deny 185.180.143.13;  # 391 attempts - Hostwinds, US
deny 195.178.110.30;  # 337 attempts - Giganet, UK
deny 80.94.92.168;    # 305 attempts - Giganet, UK
deny 186.96.145.241;  # 275 attempts - Telecentro, Argentina
deny 45.142.122.117;  # 212 attempts - Aeza Group, Netherlands
deny 185.246.221.79;  # 198 attempts - Stark Industries, Russia
deny 89.23.96.175;    # 187 attempts - Giganet, UK
deny 103.214.8.216;   # 164 attempts - Tata Communications, India
deny 103.21.161.207;  # 153 attempts - UAB Rakrejus, Singapore
deny 205.210.31.52;   # 142 attempts - QuadraNet, US
deny 45.142.122.86;   # 128 attempts - Aeza Group, Netherlands
deny 167.99.215.209;  # 118 attempts - DigitalOcean, US
deny 185.233.185.225; # 112 attempts - Giganet, UK
deny 185.246.221.80;  # 97 attempts - Stark Industries, Russia
```

**Note**: This list is for reference only. With fail2ban enabled, these IPs would be automatically blocked after their 6th failed attempt. Manual blocking is not necessary.

---

## Best Practices

### 1. Prefer fail2ban Over Manual Blocks

- fail2ban = automatic, zero maintenance
- Manual blocks = require constant updates as attackers rotate IPs

**Use manual blocks only for**:
- Extreme high-volume attacks (1,000+ req/min)
- Known persistent attackers that keep returning
- Attacks on non-WordPress URLs that fail2ban can't detect

### 2. Always Document Why IPs Are Blocked

```nginx
# ✅ Good - includes context
deny 62.60.130.228;   # 1,420 wp-login attempts, Nov 2025, Kamatera NL

# ❌ Bad - no context
deny 62.60.130.228;
```

Future you (or team members) will thank you.

### 3. Review Block List Regularly

Quarterly, review your deny list and remove IPs that are no longer threats.

**Why**: Attackers rotate IPs. Blocking old IPs has little value.

### 4. Test Changes Before Deploying

```bash
# Dry-run test
cd trellis
ansible-playbook server.yml -e env=production --tags nginx --check

# If no errors, deploy for real
trellis provision --tags nginx production
```

### 5. Keep a Backup

Before making large changes:

```bash
# Backup current config
ssh admin_user@yoursite.com "sudo cp /etc/nginx/includes.d/all/deny-ips.conf /tmp/deny-ips.conf.backup"

# If something breaks
ssh admin_user@yoursite.com "sudo cp /tmp/deny-ips.conf.backup /etc/nginx/includes.d/all/deny-ips.conf && sudo systemctl reload nginx"
```

---

## Quick Reference

### Create deny-ips.conf.j2

```bash
# Create file
touch trellis/nginx-includes/all/deny-ips.conf.j2

# Edit and add:
# deny 1.2.3.4;  # Description
```

### Deploy Changes

```bash
cd trellis
trellis provision --tags nginx production
```

### View Current Blocks

```bash
ssh admin_user@yoursite.com "cat /etc/nginx/includes.d/all/deny-ips.conf"
```

### Test Nginx Config

```bash
ssh admin_user@yoursite.com "sudo nginx -t"
```

### Monitor Blocked Requests

```bash
ssh admin_user@yoursite.com "sudo grep 'access forbidden' /var/log/nginx/error.log | tail -20"
```

---

## Resources

- [fail2ban WordPress Protection](./FAIL2BAN.md) - Automatic IP blocking (recommended)
- [Trellis nginx_includes Documentation](https://roots.io/trellis/docs/wordpress-sites/#nginx-includes)
- [Nginx ngx_http_access_module](http://nginx.org/en/docs/http/ngx_http_access_module.html)
- [wp-ops Security Scanners](../../wp-cli/security/) - Malware detection

---

**Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations**
