# Troubleshooting WordPress Servers

This section contains guides for diagnosing and resolving common issues with WordPress servers. While examples reference Trellis-managed servers, the diagnostic techniques and solutions apply to most WordPress hosting environments.

## Chapter Purpose

This chapter gives a symptom-based entry point into deeper troubleshooting guides and quick triage commands.

## Guides

| Guide | Description |
|-------|-------------|
| [PHP-FPM.md](PHP-FPM.md) | Pool exhaustion, memory management, worker configuration |
| [MariaDB.md](MariaDB.md) | Startup failures, plugin issues, connection problems |
| [OOM.md](OOM.md) | Out of memory issues, WP-Cron memory leaks, PHP CLI limits |
| [MAIL.md](MAIL.md) | SMTP configuration issues after Trellis upgrades |

## Quick Diagnostic Commands

SSH to your server and run these commands to quickly assess server health.

### System Memory

```bash
# Memory overview
free -h

# Top memory consumers
ps aux --sort=-%mem | head -10
```

### PHP-FPM Workers

```bash
# Count active workers
pgrep -c php-fpm

# Memory usage per worker (replace 8.3 with your PHP version)
ps aux --sort=-%mem | grep 'php-fpm: pool' | head -5 | awk '{print $6/1024" MB - PID "$2}'

# Total PHP-FPM memory usage
ps aux | grep 'php-fpm: pool' | awk '{sum+=$6} END {print sum/1024" MB"}'

# Current pool configuration
cat /etc/php/8.3/fpm/pool.d/wordpress.conf | grep -E '^pm'
```

### PHP-FPM Logs

```bash
# Recent warnings (replace 8.3 with your PHP version)
grep 'seems busy\|max_children' /var/log/php8.3-fpm.log | tail -20

# Watch logs in real-time
tail -f /var/log/php8.3-fpm.log
```

### Nginx Logs

```bash
# Recent errors
tail -50 /var/log/nginx/error.log

# Site-specific errors
tail -50 /srv/www/example.com/logs/error.log
```

### WordPress Diagnostics

```bash
# Check WordPress memory limits (run as web user)
cd /srv/www/example.com/current
wp eval 'echo "WP_MEMORY_LIMIT: " . WP_MEMORY_LIMIT . "\nWP_MAX_MEMORY_LIMIT: " . WP_MAX_MEMORY_LIMIT;' --path=web/wp

# Check autoloaded options size
wp db query "SELECT COUNT(*) as count, ROUND(SUM(LENGTH(option_value))/1024) as size_kb FROM wp_options WHERE autoload='yes';" --path=web/wp
```

## Quick Health Check

One-liner to check overall server health:

```bash
ssh root@your-server.com "echo '=== Memory ===' && free -m | grep Mem && echo '' && echo '=== PHP-FPM Workers ===' && ps aux --sort=-%mem | grep 'php-fpm: pool' | head -5 | awk '{print \$6/1024 \" MB - PID \" \$2}'"
```

**Healthy indicators:**
- Memory: Available RAM > 1GB
- Workers: Each worker < 200MB
- No recent errors in logs
