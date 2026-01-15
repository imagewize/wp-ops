---
layout: chapter
title: "Monitoring and Alerting"
chapter_number: 5
permalink: /chapters/monitoring-alerting/
---

# Nginx Log Monitoring

Tools and documentation for monitoring WordPress/Trellis sites via Nginx access and error logs. Includes traffic analysis, security monitoring, and detection of malicious actors.

## Chapter Purpose

This chapter shows how to observe live traffic and detect threats using Nginx logs and supporting scripts.

## Overview

This directory contains scripts and Ansible playbooks for:

- **Traffic Analysis** - Monitor legitimate traffic patterns, popular content, user agents
- **Security Monitoring** - Detect bad actors, attack patterns, suspicious requests
- **Automated Alerts** - Configure monitoring tasks that run via cron
- **Log Analysis** - Parse and analyze Nginx logs for insights

## Prerequisites

- Trellis-managed WordPress site with Nginx
- SSH access to server (root user recommended for log access)
- SSH key-based authentication configured (password authentication should be disabled)
- For Ansible playbooks: Trellis environment configured

### Log File Locations

Trellis can be configured to store Nginx logs in two ways:

**Per-site logs (Trellis default):**
- Access log: `/srv/www/example.com/logs/access.log`
- Error log: `/srv/www/example.com/logs/error.log`

**Global logs (alternative configuration):**
- Access log: `/var/log/nginx/access.log`
- Error log: `/var/log/nginx/error.log`

The Ansible playbooks in this repository **default to per-site logs** but can be overridden with `-e log_file=/path/to/log`. The shell scripts accept the log path as the first argument.

## Quick Start

### Manual Log Analysis

```bash
# SSH to server as root
ssh root@example.com

# For per-site logs (Trellis default):
LOG="/srv/www/example.com/logs/access.log"

# OR for global logs:
# LOG="/var/log/nginx/access.log"

# View recent successful requests (excluding known bots)
grep 'HTTP/1.[01]" 200' "$LOG" | grep -vE 'updown.io|bot|spider|crawl|Geedo|Semrush|DuckDuckBot'

# View recent 404 errors
grep 'HTTP/1.[01]" 404' "$LOG"

# View recent 50x server errors
grep 'HTTP/1.[01]" 5[0-9][0-9]' "$LOG"
```

**Note on Root Access:** These commands require root privileges to read log files. Using the root user with SSH key authentication is the recommended approach. **Root password authentication should always be disabled** for security. If you prefer not to use root SSH access, see the "Alternative Access Methods" section below.

### Using Monitoring Scripts

Copy scripts to your server and run them:

```bash
# Copy scripts to server
scp monitoring/scripts/*.sh root@example.com:/root/

# SSH and run
ssh root@example.com
cd /root
chmod +x *.sh

# For per-site logs (default):
./traffic-monitor.sh /srv/www/example.com/logs/access.log
./security-monitor.sh /srv/www/example.com/logs/access.log

# OR for global logs:
# ./traffic-monitor.sh /var/log/nginx/access.log
# ./security-monitor.sh /var/log/nginx/access.log
```

### Using Ansible Playbooks

Run from your Trellis directory:

```bash
# Run traffic analysis report (uses per-site logs by default)
ansible-playbook monitoring/trellis/traffic-report.yml -e site=example.com -e env=production

# Run security scan
ansible-playbook monitoring/trellis/security-scan.yml -e site=example.com -e env=production

# Setup automated monitoring (cron jobs)
ansible-playbook monitoring/trellis/setup-monitoring.yml -e site=example.com -e env=production

# Override to use global logs:
# ansible-playbook monitoring/trellis/traffic-report.yml -e site=example.com -e env=production -e log_file=/var/log/nginx/access.log
```

**Note:** The playbooks default to per-site logs at `/srv/www/{{ site }}/logs/access.log`. Override with `-e log_file=/path/to/log` if your Trellis uses global logs.

## Alternative Access Methods

While we recommend using root SSH access with key-based authentication, you can use alternative approaches if you prefer:

### Option 1: Use sudo with existing user

```bash
# SSH as web user and use sudo
ssh web@example.com
sudo ./traffic-monitor.sh
sudo ./security-monitor.sh
```

This requires entering the password each time unless you configure passwordless sudo (see below).

### Option 2: Add web user to adm group

The `adm` group has read access to log files. This is the cleanest non-root solution:

```bash
# As root, add web user to adm group
sudo usermod -aG adm web

# Log out and back in for group membership to take effect
exit
ssh web@example.com

# Now scripts can read logs without sudo
./traffic-monitor.sh
./security-monitor.sh
```

### Option 3: Configure passwordless sudo (not recommended)

You can grant specific sudo permissions without requiring a password. This requires server configuration changes:

```bash
# Create sudoers file for web user
sudo visudo -f /etc/sudoers.d/web-monitoring

# Add these lines:
# web ALL=(ALL) NOPASSWD: /usr/bin/awk * /var/log/nginx/access.log*
# web ALL=(ALL) NOPASSWD: /usr/bin/grep * /var/log/nginx/access.log*
# web ALL=(ALL) NOPASSWD: /bin/cat /var/log/nginx/access.log*
```

**Note:** This approach is complex and error-prone. The `adm` group method (Option 2) is cleaner.

### Security Considerations

- **Root password authentication:** Must always be disabled (`PermitRootLogin without-password` or `PermitRootLogin prohibit-password` in `/etc/ssh/sshd_config`)
- **SSH key-based authentication:** Required for all users with SSH access
- **Root SSH access:** Safe when using SSH keys; common practice for system administration
- **Regular user with sudo:** More granular but requires additional configuration

For production servers using SSH key authentication, root access is the most straightforward approach for system monitoring tasks.

## Traffic Analysis

### Monitoring Legitimate Traffic

**What to Monitor:**
- Page views and popular content
- Geographic distribution
- Traffic sources (direct, referral, search)
- Performance metrics (response times)
- User engagement patterns

**Commands:**

```bash
# Top 10 most requested pages (excluding bots, static files)
grep 'HTTP/1.[01]" 200' /var/log/nginx/access.log \
  | grep -vE 'updown.io|bot|spider|crawl|Geedo|Semrush|DuckDuckBot' \
  | grep -vE '\.(css|js|jpg|jpeg|png|gif|ico|woff|woff2|svg)' \
  | awk '{print $7}' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -10

# Unique visitor count (by IP, excluding bots)
grep 'HTTP/1.[01]" 200' /var/log/nginx/access.log \
  | grep -vE 'updown.io|bot|spider|crawl|Geedo|Semrush|DuckDuckBot' \
  | awk '{print $1}' \
  | sort -u \
  | wc -l

# Traffic by hour of day
awk '{print $4}' /var/log/nginx/access.log \
  | cut -c 14-15 \
  | sort \
  | uniq -c \
  | sort -n

# Response time statistics (if logging $request_time)
awk '{print $NF}' /var/log/nginx/access.log \
  | grep -E '^[0-9]+\.[0-9]+$' \
  | sort -n \
  | awk '{
      count++;
      sum+=$1;
      values[count]=$1
    }
    END {
      print "Avg:", sum/count;
      print "Min:", values[1];
      print "Max:", values[count];
      print "Median:", values[int(count/2)]
    }'

# Browser/User agent distribution (top 10)
awk -F'"' '{print $6}' /var/log/nginx/access.log \
  | grep -vE 'bot|spider|crawl|Geedo|Semrush|DuckDuckBot|updown.io' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -10
```

### Integration with updown.io

Since you already use updown.io for uptime monitoring, Nginx logs can complement this with:

- **Detailed error analysis** - updown.io detects downtime; logs show the cause
- **Performance trends** - Compare updown.io response times with server-side metrics
- **User impact** - Correlate downtime windows with actual user traffic
- **False positive verification** - Confirm if updown.io alerts match real user issues

## Security Monitoring

### Detecting Bad Actors

**Common Attack Patterns:**
- High request rates from single IP (DoS/DDoS)
- Requests for common exploit paths (`/wp-login.php`, `/xmlrpc.php`, `/wp-admin`)
- SQL injection attempts (query strings with `UNION`, `SELECT`, etc.)
- Directory traversal attempts (`../`, `%2e%2e/`)
- 404 errors from scanning tools
- User agent spoofing or missing user agents

**Commands:**

```bash
# IPs with most requests (potential scrapers/attackers)
awk '{print $1}' /var/log/nginx/access.log \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -20

# IPs hitting wp-login.php repeatedly (brute force attempts)
grep 'wp-login.php' /var/log/nginx/access.log \
  | awk '{print $1}' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -10

# IPs generating most 404 errors (scanners)
grep 'HTTP/1.[01]" 404' /var/log/nginx/access.log \
  | awk '{print $1}' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -10

# SQL injection attempts
grep -iE "union.*select|concat.*\(|script>|javascript:" /var/log/nginx/access.log

# Directory traversal attempts
grep -E "\.\./|%2e%2e|%252e" /var/log/nginx/access.log

# Suspicious user agents (empty or suspicious)
awk -F'"' '$6 == "" || $6 == "-" {print $0}' /var/log/nginx/access.log \
  | head -20

# xmlrpc.php attacks (WordPress pingback/trackback abuse)
grep 'xmlrpc.php' /var/log/nginx/access.log \
  | awk '{print $1, $7, $9}' \
  | sort \
  | uniq -c \
  | sort -rn

# Check for referrer spam
awk -F'"' '{print $4}' /var/log/nginx/access.log \
  | grep -vE '^-$|^$' \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -20
```

### Response Actions

**When you detect a bad actor:**

1. **Verify** - Ensure it's actually malicious, not a legitimate crawler
2. **Block at Nginx** - Add to deny list in Trellis configuration
3. **Use fail2ban** - Automate blocking of repeated offenders
4. **Report** - For severe attacks, report to hosting provider or abuse contacts

**Blocking IP in Trellis:**

Edit `group_vars/<environment>/wordpress_sites.yml`:

```yaml
wordpress_sites:
  example.com:
    nginx_includes:
      - "{{ nginx_path }}/includes.d/deny-ips.conf"
```

Create `roles/wordpress-setup/templates/deny-ips.conf.j2`:

```nginx
# Blocked IPs
deny 192.168.1.100;
deny 203.0.113.0/24;
```

Then provision: `trellis provision production`

## Automated Monitoring with Ansible

The `setup-monitoring.yml` playbook configures automated monitoring tasks:

**Features:**
- Daily traffic reports sent via email
- Real-time security alerts for attack patterns
- Weekly summaries of top IPs, pages, errors
- Automatic log rotation checks

**Setup:**

```bash
# Configure email in playbook vars
ansible-playbook monitoring/trellis/setup-monitoring.yml \
  -e site=example.com \
  -e env=production \
  -e alert_email=admin@example.com
```

**What it creates:**
- Cron job for daily traffic analysis
- Cron job for security scanning (every 6 hours)
- Email alerts for suspicious activity
- Log rotation verification

## Log Format Configuration

Trellis default Nginx log format (in `/etc/nginx/nginx.conf`):

```nginx
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';
```

**Enhanced format with response time:**

```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';
```

To use enhanced logging, modify Trellis `roles/nginx/templates/nginx.conf.j2` and provision.

## Log Analysis Tools

### GoAccess (Real-time Web Log Analyzer)

Install on server:

```bash
sudo apt-get install goaccess
```

Usage:

```bash
# Real-time terminal dashboard
goaccess /var/log/nginx/access.log -c

# Generate HTML report
goaccess /var/log/nginx/access.log -o /var/www/report.html --log-format=COMBINED

# Real-time HTML dashboard
goaccess /var/log/nginx/access.log -o /var/www/report.html --log-format=COMBINED --real-time-html
```

### AWStats

More heavyweight option for detailed statistics:

```bash
# Install
sudo apt-get install awstats

# Configure for site
sudo cp /etc/awstats/awstats.conf /etc/awstats/awstats.example.com.conf

# Generate stats
sudo /usr/lib/cgi-bin/awstats.pl -config=example.com -update
```

## Fail2Ban Integration

Automate blocking of bad actors with fail2ban:

**Install:**

```bash
sudo apt-get install fail2ban
```

**WordPress-specific filters:**

Create `/etc/fail2ban/filter.d/wordpress.conf`:

```ini
[Definition]
failregex = ^<HOST> .* "POST /wp-login.php
            ^<HOST> .* "POST /xmlrpc.php
            ^<HOST> .* "GET /wp-admin
ignoreregex =
```

Create `/etc/fail2ban/jail.d/wordpress.conf`:

```ini
[wordpress]
enabled = true
filter = wordpress
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 3600
findtime = 600
port = http,https
```

**Ansible playbook for fail2ban setup coming soon**

## Log Retention

Nginx logs rotate via logrotate (configured in Trellis):

**Default retention:** 14 days

**Check rotation config:**

```bash
cat /etc/logrotate.d/nginx
```

**Typical configuration:**

```
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
```

**Long-term archival:**

For compliance or historical analysis, archive compressed logs to S3/storage:

```bash
# Manual backup
tar -czf nginx-logs-$(date +%Y%m).tar.gz /var/log/nginx/*.log.*.gz
aws s3 cp nginx-logs-$(date +%Y%m).tar.gz s3://backups/logs/

# See backup playbooks for automated archival
```

## Performance Monitoring

### Response Time Tracking

If using enhanced log format with `$request_time`:

```bash
# Average response time by endpoint
awk '{print $(NF-4), $7}' /var/log/nginx/access.log \
  | grep '^rt=' \
  | sed 's/rt=//' \
  | awk '{times[$2]+=$1; count[$2]++}
         END {for (url in times) print times[url]/count[url], url}' \
  | sort -rn \
  | head -20

# Slow requests (> 1 second)
awk '{print $(NF-4), $7, $9}' /var/log/nginx/access.log \
  | grep '^rt=' \
  | sed 's/rt=//' \
  | awk '$1 > 1.0 {print $0}' \
  | sort -rn
```

### PHP-FPM Slow Log

Monitor slow PHP execution:

```bash
# Location: /var/log/php{VERSION}-fpm-slow.log
tail -f /var/log/php8.2-fpm-slow.log

# Analyze slow scripts
grep 'pool www' /var/log/php8.2-fpm-slow.log -A 10 \
  | grep 'script_filename' \
  | sort \
  | uniq -c \
  | sort -rn
```

## Complementing updown.io

**updown.io strengths:**
- External perspective (detects network issues)
- Simple uptime percentage tracking
- SSL certificate monitoring
- Multi-location checks

**Nginx logs complement with:**
- Internal server perspective
- Detailed error causes (500 errors, timeouts)
- User impact beyond uptime (slow responses, 404s)
- Attack/abuse detection
- Traffic patterns and trends

**Workflow:**
1. updown.io alerts you to downtime
2. Check Nginx logs for error details: `grep 'HTTP/1.[01]" 5[0-9][0-9]' /var/log/nginx/access.log | tail -50`
3. Check error log: `tail -50 /var/log/nginx/error.log`
4. Check PHP-FPM log if applicable: `tail -50 /var/log/php*-fpm.log`
5. Correlate timing with deployment, traffic spike, or attack

## Best Practices

1. **Regular Review** - Check logs weekly, even without alerts
2. **Baseline Understanding** - Know your normal traffic patterns to spot anomalies
3. **Retention Policy** - Archive important logs before rotation deletes them
4. **Alert Fatigue** - Tune monitoring to avoid false positives
5. **Privacy** - Be mindful of GDPR/privacy when storing/analyzing user data
6. **Automation** - Use Ansible playbooks to standardize monitoring across sites
7. **Multi-layer** - Combine updown.io (external) + Nginx logs (internal) + application logs

## Troubleshooting

### Empty or Missing Logs

```bash
# Check Nginx is logging
sudo nginx -T | grep access_log

# Check file permissions
ls -la /var/log/nginx/

# Check disk space
df -h

# Restart Nginx if needed
sudo systemctl restart nginx
```

### Log Parsing Errors

If log format doesn't match commands:

```bash
# Check actual format
head -5 /var/log/nginx/access.log

# Verify format in Nginx config
sudo grep log_format /etc/nginx/nginx.conf
```

## Additional Resources

- [Nginx Log Analysis Guide](https://www.nginx.com/blog/using-nginx-logging-for-application-performance/)
- [GoAccess Documentation](https://goaccess.io/man)
- [Fail2Ban Wiki](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [Trellis Documentation](https://roots.io/trellis/docs/)

## Contributing

Improvements to monitoring scripts and playbooks welcome. Follow existing patterns:
- Shell scripts: Configuration variables at top
- Ansible playbooks: Use variable-check.yml for validation
- Documentation: Include practical examples
