# Monitoring Quick Reference

Quick command reference for common monitoring tasks.

**Prerequisites:** Root SSH access with key-based authentication (password auth disabled). See main [README.md](README.md) for alternative access methods.

**Log Paths:** Trellis defaults to per-site logs (`/srv/www/site/logs/`). Adjust paths below if using global logs (`/var/log/nginx/`).

## Shell Scripts (Direct Server Access)

```bash
# SSH to server as root
ssh root@example.com

# Define your log path (per-site is Trellis default)
LOG="/srv/www/example.com/logs/access.log"

# Run traffic analysis (last 24 hours)
./traffic-monitor.sh "$LOG"

# Run traffic analysis (last 6 hours)
./traffic-monitor.sh "$LOG" 6

# Run security scan (last 24 hours)
./security-monitor.sh "$LOG"

# Run security scan (last 1 hour, alert threshold 50)
./security-monitor.sh "$LOG" 1 50
```

**Alternative:** If not using root, run with `sudo` or add user to `adm` group (see [README.md](README.md#alternative-access-methods)).

## Ansible Playbooks (From Trellis Directory)

```bash
# Quick status check
ansible-playbook monitoring/trellis/quick-status.yml -e site=example.com -e env=production

# Generate traffic report
ansible-playbook monitoring/trellis/traffic-report.yml -e site=example.com -e env=production

# Generate traffic report (last 6 hours)
ansible-playbook monitoring/trellis/traffic-report.yml -e site=example.com -e env=production -e hours=6

# Save report to file
ansible-playbook monitoring/trellis/traffic-report.yml -e site=example.com -e env=production -e save_report=true

# Run security scan
ansible-playbook monitoring/trellis/security-scan.yml -e site=example.com -e env=production

# Run security scan with email alerts
ansible-playbook monitoring/trellis/security-scan.yml -e site=example.com -e env=production -e alert_email=admin@example.com

# Setup automated monitoring
ansible-playbook monitoring/trellis/setup-monitoring.yml -e site=example.com -e env=production -e email=admin@example.com
```

## One-Liner Commands

**Note:** Run these commands as root or with `sudo` prefix if using another user. Set `LOG` variable to your log path first.

```bash
# Set log path (per-site or global)
LOG="/srv/www/example.com/logs/access.log"
```

### Traffic Analysis

```bash
# Real traffic (excluding bots) last hour
grep 'HTTP/1.[01]" 200' "$LOG" | grep -vE 'updown.io|bot|spider|crawl|Geedo|Semrush|DuckDuckBot' | tail -100

# Top 10 pages today
grep "$(date +%d/%b/%Y)" "$LOG" | awk '{print $7}' | sort | uniq -c | sort -rn | head -10

# Unique visitors today
grep "$(date +%d/%b/%Y)" "$LOG" | awk '{print $1}' | sort -u | wc -l

# Traffic by hour
awk '{print $4}' "$LOG" | cut -c 14-15 | sort | uniq -c
```

### Security Monitoring

```bash
# Top IPs by request count
awk '{print $1}' "$LOG" | sort | uniq -c | sort -rn | head -20

# wp-login.php attempts
grep 'wp-login.php' "$LOG" | awk '{print $1}' | sort | uniq -c | sort -rn

# 404 errors (potential scanners)
grep 'HTTP/1.[01]" 404' "$LOG" | awk '{print $1, $7}' | tail -20

# SQL injection attempts
grep -iE "union.*select|concat\(|script>" "$LOG"

# Suspicious user agents
awk -F'"' '$6 ~ /sqlmap|nikto|nmap/ {print $0}' "$LOG"
```

### Error Analysis

```bash
# Recent 5xx errors
grep 'HTTP/1.[01]" 5[0-9][0-9]' "$LOG" | tail -20

# Recent 4xx errors
grep 'HTTP/1.[01]" 4[0-9][0-9]' "$LOG" | tail -20

# Nginx error log (per-site)
ERROR_LOG="/srv/www/example.com/logs/error.log"
tail -50 "$ERROR_LOG"

# PHP-FPM slow log (check your PHP version)
tail -50 /var/log/php8.2-fpm-slow.log
```

## Blocking Bad Actors

### Temporary Block (Immediate)

```bash
# Add to Nginx config (requires sudo)
sudo nano /etc/nginx/sites-available/example.com.conf

# Add inside server block:
deny 192.168.1.100;
deny 203.0.113.0/24;

# Reload Nginx
sudo systemctl reload nginx
```

### Permanent Block (via Trellis)

1. Create `roles/wordpress-setup/templates/deny-ips.conf.j2`:
   ```nginx
   # Blocked IPs
   deny 192.168.1.100;
   deny 203.0.113.0/24;
   ```

2. Update `group_vars/<environment>/wordpress_sites.yml`:
   ```yaml
   wordpress_sites:
     example.com:
       nginx_includes:
         - "{{ nginx_path }}/includes.d/deny-ips.conf"
   ```

3. Provision:
   ```bash
   trellis provision production
   ```

## Monitoring Cron Jobs Status

```bash
# View monitoring cron jobs
crontab -l | grep monitoring

# View monitoring logs
ls -lh ~/monitoring/logs/

# Tail live security monitoring
tail -f ~/monitoring/logs/security-*.txt

# Check recent traffic reports
cat ~/monitoring/logs/traffic-$(date +%Y-%m-%d).txt
```

## updown.io Integration

### Check Correlation

When updown.io alerts you to downtime:

```bash
# Check logs at that time (replace HH:MM with time)
grep "$(date +%d/%b/%Y):HH:MM" /var/log/nginx/access.log | grep 'HTTP/1.[01]" 5[0-9][0-9]'

# Check error log
grep "$(date +%Y/%m/%d) HH:MM" /var/log/nginx/error.log

# Run analysis for that hour
./monitoring/security-monitor.sh /var/log/nginx/access.log 1
```

### Webhook Integration

1. Setup webhook receiver on server
2. Configure updown.io webhook URL
3. Automatic log analysis on downtime events

See [updown-webhook-receiver.php](updown-webhook-receiver.php) for implementation.

## Real-Time Monitoring

```bash
# Watch access log live
tail -f /var/log/nginx/access.log

# Watch only errors
tail -f /var/log/nginx/access.log | grep 'HTTP/1.[01]" [45][0-9][0-9]'

# Watch specific IP
tail -f /var/log/nginx/access.log | grep "192.168.1.100"

# Watch login attempts
tail -f /var/log/nginx/access.log | grep 'wp-login.php'
```

## GoAccess (Real-Time Dashboard)

```bash
# Install
sudo apt-get install goaccess

# Real-time terminal dashboard
goaccess /var/log/nginx/access.log -c

# Generate HTML report
goaccess /var/log/nginx/access.log -o /var/www/example.com/current/web/report.html --log-format=COMBINED

# Real-time HTML dashboard (updates automatically)
goaccess /var/log/nginx/access.log -o /var/www/example.com/current/web/report.html --log-format=COMBINED --real-time-html --ws-url=wss://example.com
```

## Performance Monitoring

```bash
# Average response time (if logging $request_time)
awk '{print $NF}' /var/log/nginx/access.log | grep -E '^[0-9]+\.[0-9]+$' | awk '{sum+=$1; count++} END {print "Avg:", sum/count}'

# Slow requests (> 1 second)
awk '{if ($NF > 1.0) print $NF, $7}' /var/log/nginx/access.log

# Bandwidth usage today
grep "$(date +%d/%b/%Y)" /var/log/nginx/access.log | awk '{sum+=$10} END {print sum/1024/1024 " MB"}'
```

## System Resources

```bash
# Disk space
df -h

# Memory usage
free -h

# Active connections
ss -tn | grep -E ':80|:443' | wc -l

# Nginx status
sudo systemctl status nginx

# PHP-FPM status
sudo systemctl status php*-fpm

# Check PHP-FPM pool
sudo systemctl status php8.2-fpm

# Database connections (if MySQL/MariaDB)
mysqladmin -u root -p processlist
```

## Troubleshooting

### No logs appearing

```bash
# Check Nginx config
sudo nginx -t

# Check log file permissions
ls -la /var/log/nginx/

# Restart Nginx
sudo systemctl restart nginx
```

### Script permission denied

```bash
chmod +x ~/monitoring/*.sh
```

### Ansible playbook errors

```bash
# Verify site exists in wordpress_sites
ansible-inventory --host <environment>_hosts -i hosts/

# Test connection
ansible web -m ping -e env=production
```

## Additional Resources

- Main documentation: [README.md](README.md)
- Traffic monitoring script: [scripts/traffic-monitor.sh](scripts/traffic-monitor.sh)
- Security monitoring script: [scripts/security-monitor.sh](scripts/security-monitor.sh)
- Trellis documentation: https://roots.io/trellis/
