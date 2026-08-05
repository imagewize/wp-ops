# PHP-FPM Troubleshooting Guide

This guide covers PHP-FPM pool management, memory configuration, and troubleshooting for Trellis-managed WordPress servers.

## Table of Contents

- [Common Errors](#common-errors)
- [Understanding PHP-FPM Dynamic Pools](#understanding-php-fpm-dynamic-pools)
- [Memory Math: Calculating Safe Worker Counts](#memory-math-calculating-safe-worker-counts)
- [WordPress Memory Limits](#wordpress-memory-limits)
- [Worker Memory Accumulation](#worker-memory-accumulation)
- [The Low-Traffic Recycling Problem](#the-low-traffic-recycling-problem)
- [Recommended Configurations](#recommended-configurations)
- [Diagnostic Commands](#diagnostic-commands)
- [Applying Changes via Trellis](#applying-changes-via-trellis)
- [Solutions by Problem](#solutions-by-problem)

## Common Errors

### Pool Exhaustion

**Log message:**
```
[pool wordpress] seems busy (you may need to increase pm.start_servers, or pm.min/max_spare_servers), spawning 8 children, there are 0 idle, and 22 total children
[pool wordpress] server reached pm.max_children setting (30), consider raising it
```

**Symptom:** WordPress displays "There has been a critical error on this website"

**What's happening:**
1. All PHP-FPM workers are busy processing requests
2. New request comes in
3. No available workers → request fails
4. WordPress returns generic "critical error" message

### Memory Exhaustion

**Log message:**
```
Fatal error: Allowed memory size of 41943040 bytes exhausted
```

**What's happening:** WordPress's internal memory limit (often 40M default) is too low for plugins like WooCommerce or Acorn/Laravel.

## Understanding PHP-FPM Dynamic Pools

Trellis uses `pm = dynamic` by default, which spawns workers based on demand.

| Setting | Purpose |
|---------|---------|
| `pm.max_children` | Maximum workers allowed |
| `pm.start_servers` | Workers spawned on startup |
| `pm.min_spare_servers` | Minimum idle workers to maintain |
| `pm.max_spare_servers` | Maximum idle workers before killing extras |
| `pm.max_requests` | Requests per worker before recycling |

**Default Trellis values:**
```yaml
php_fpm_pm_max_children: 10
php_fpm_pm_start_servers: 2
php_fpm_pm_min_spare_servers: 1
php_fpm_pm_max_spare_servers: 3
php_fpm_pm_max_requests: 500
```

## Memory Math: Calculating Safe Worker Counts

Each PHP-FPM worker typically uses 100-250MB depending on your plugins.

### Formula

```
Safe max_children = Available RAM / Average worker memory
```

### Example Calculations

**4GB Server:**
```
Available RAM: ~3.5GB (after system/services)
Average worker: ~200MB
Safe workers: 3500MB / 200MB = ~17 workers
```

**8GB Server:**
```
Available RAM: ~7GB (after system/services)
Average worker: ~200MB
Safe workers: 7000MB / 200MB = ~35 workers
```

### The Resource Ceiling Conflict

On smaller servers, you face a trade-off:
- **For memory safety:** Fewer workers (prevent OOM)
- **For traffic handling:** More workers (handle concurrent requests)

**Solutions:**
1. Upgrade server RAM
2. Reduce worker memory via `pm.max_requests`
3. Add Redis caching to reduce per-request load
4. Optimize WordPress (fewer plugins, cleaner autoload)

## WordPress Memory Limits

WordPress has its **own memory limits** separate from PHP's limit.

| Setting | Purpose | WordPress Default |
|---------|---------|-------------------|
| `WP_MEMORY_LIMIT` | Memory for frontend requests | 40M |
| `WP_MAX_MEMORY_LIMIT` | Memory for admin/backend | 256M |
| `php_memory_limit` | PHP-FPM's overall limit | 512M (Trellis) |

**Key insight:** Even if PHP allows 768MB, WordPress caps itself at `WP_MEMORY_LIMIT` (40MB by default). This is often the hidden cause of memory errors.

### Setting WordPress Memory Limits

In your Bedrock site's `config/application.php`:

```php
/**
 * Memory Limits
 *
 * Increased for WooCommerce + modern themes/plugins.
 */
Config::define('WP_MEMORY_LIMIT', '256M');
Config::define('WP_MAX_MEMORY_LIMIT', '512M');
```

### Verify Memory Limits

```bash
wp eval 'echo "WP_MEMORY_LIMIT: " . WP_MEMORY_LIMIT . "\nWP_MAX_MEMORY_LIMIT: " . WP_MAX_MEMORY_LIMIT;' --path=web/wp
```

## Worker Memory Accumulation

PHP-FPM workers don't release memory between requests. Over time, they accumulate:

```
Request 1:    150 MB
Request 50:   250 MB
Request 100:  350 MB
Request 200:  500+ MB  ← Danger zone!
```

### The Solution: Worker Recycling

`pm.max_requests` controls how many requests a worker handles before being killed and respawned:

```yaml
pm.max_requests = 100   # Kill worker after 100 requests
```

**Trade-off:**
- Lower value = More recycling overhead, safer memory
- Higher value = Less overhead, risk of memory bloat

**Recommended:** Start with `100` for memory-heavy sites (WooCommerce, Acorn), use `200-500` for lighter sites.

### Testing Worker Recycling

```bash
# Generate traffic
for i in {1..200}; do
  curl -s -o /dev/null "https://example.com/?nocache=$(date +%s%N)$i" &
done
wait

# Check worker memory (should be low after recycling)
ps aux --sort=-%mem | grep 'php-fpm: pool' | head -5 | awk '{print $6/1024" MB - PID "$2}'
```

**Expected:** Workers should be 130-160MB after recycling, not 400MB+.

### The Low-Traffic Recycling Problem

On low-traffic sites, `pm.max_requests` may be ineffective because workers don't receive enough requests to trigger recycling:

```
Traffic rate: ~80 requests/hour
Workers: 15
Requests per worker per hour: ~5
Time to reach 100 requests: ~20 hours

Meanwhile, memory accumulates faster than recycling occurs.
```

**Symptoms:**
- Workers showing 500MB-800MB+ despite `pm.max_requests: 100`
- Memory exhaustion errors on basic requests (feeds, robots.txt, monitoring pings)
- Errors from uptime monitors and crawlers

**Solutions for low-traffic sites:**

| Option | Description | Trade-off |
|--------|-------------|-----------|
| Reduce `pm.max_requests` to 25-50 | More aggressive recycling | More spawn overhead |
| Reduce `pm.min_spare_servers` | Fewer idle workers accumulating memory | Slower response to traffic spikes |
| Add `pm.process_idle_timeout` | Kill idle workers after X seconds | May slow response times |
| Scheduled PHP-FPM restart | Cron job to restart nightly | Brief service interruption |
| Enable Redis object cache | Reduce per-request memory usage | Setup complexity |

**Recommended for low-traffic sites:**

```yaml
# Fewer workers, more aggressive recycling
php_fpm_pm_max_children: 15
php_fpm_pm_start_servers: 4
php_fpm_pm_min_spare_servers: 2
php_fpm_pm_max_spare_servers: 6
php_fpm_pm_max_requests: 50
```

## Recommended Configurations

### 4GB Server (Conservative)

```yaml
# trellis/group_vars/production/main.yml
php_fpm_pm: dynamic
php_fpm_pm_max_children: 20
php_fpm_pm_start_servers: 8
php_fpm_pm_min_spare_servers: 6
php_fpm_pm_max_spare_servers: 12
php_fpm_pm_max_requests: 100

php_memory_limit: 768M
```

### 4GB Server (Aggressive)

For sites with traffic spikes, accepting some memory risk:

```yaml
php_fpm_pm_max_children: 25
php_fpm_pm_start_servers: 12
php_fpm_pm_min_spare_servers: 10
php_fpm_pm_max_spare_servers: 18
php_fpm_pm_max_requests: 100
```

### 8GB Server

```yaml
php_fpm_pm_max_children: 40
php_fpm_pm_start_servers: 15
php_fpm_pm_min_spare_servers: 10
php_fpm_pm_max_spare_servers: 25
php_fpm_pm_max_requests: 200

php_memory_limit: 768M
```

### High-Traffic / WooCommerce

```yaml
php_fpm_pm_max_children: 50
php_fpm_pm_start_servers: 20
php_fpm_pm_min_spare_servers: 15
php_fpm_pm_max_spare_servers: 30
php_fpm_pm_max_requests: 100  # Keep low for WooCommerce
```

## Diagnostic Commands

### Check Worker Status

```bash
# Count active workers
pgrep -c php-fpm

# Memory per worker (replace 8.3 with your PHP version)
ps aux --sort=-%mem | grep 'php-fpm: pool' | head -10 | awk '{print $6/1024" MB - PID "$2}'

# Total PHP-FPM memory
ps aux | grep 'php-fpm: pool' | awk '{sum+=$6} END {print sum/1024" MB"}'

# Current pool configuration
cat /etc/php/8.3/fpm/pool.d/wordpress.conf | grep -E '^pm'
```

### Check Logs

```bash
# Pool exhaustion warnings
grep 'seems busy\|max_children' /var/log/php8.3-fpm.log | tail -20

# Watch logs in real-time
tail -f /var/log/php8.3-fpm.log
```

### Check System Memory

```bash
# Memory overview
free -h

# Detailed memory info
cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree'

# Top memory consumers
ps aux --sort=-%mem | head -15
```

### Check Autoload Options

Large autoloaded options increase per-request memory:

```bash
# Count and size
wp db query "SELECT COUNT(*) as count, ROUND(SUM(LENGTH(option_value))/1024) as size_kb FROM wp_options WHERE autoload='yes';" --path=web/wp

# Largest options
wp db query "SELECT option_name, LENGTH(option_value) as size_bytes FROM wp_options WHERE autoload='yes' ORDER BY size_bytes DESC LIMIT 10;" --path=web/wp
```

### Quick Health Check

Comprehensive one-liner to check PHP-FPM configuration and status:

```bash
ssh root@your-server.com "echo '=== PHP-FPM Pool Config ===' && cat /etc/php/8.3/fpm/pool.d/wordpress.conf | grep -E '^pm' && echo '' && echo '=== PHP Memory Limit ===' && grep memory_limit /etc/php/8.3/fpm/php.ini && echo '' && echo '=== Current Workers ===' && ps aux --sort=-%mem | grep 'php-fpm: pool' | head -5 | awk '{print \$6/1024 \" MB - PID \" \$2}' && echo '' && echo '=== Memory ===' && free -m | grep Mem"
```

**Note:** Replace `8.3` with your PHP version.

**Healthy output:**
- Pool config: Shows your pm.* settings
- Memory limit: Should match your Trellis config
- Workers: Each worker < 200MB
- Memory: Available RAM > 1GB

## Applying Changes via Trellis

### Update Configuration

Edit `trellis/group_vars/production/main.yml`:

```yaml
php_fpm_pm: dynamic
php_fpm_pm_max_children: 25
php_fpm_pm_start_servers: 10
php_fpm_pm_min_spare_servers: 8
php_fpm_pm_max_spare_servers: 15
php_fpm_pm_max_requests: 100
```

### Apply Changes

```bash
cd trellis
trellis provision --tags wordpress-setup production
```

This updates `/etc/php/8.3/fpm/pool.d/wordpress.conf` and reloads PHP-FPM.

### Verify Changes

```bash
ssh root@your-server.com "cat /etc/php/8.3/fpm/pool.d/wordpress.conf | grep -E '^pm'"
```

### Manual PHP-FPM Restart

If provisioning doesn't restart PHP-FPM:

```bash
ssh root@your-server.com "systemctl restart php8.3-fpm"
```

## Solutions by Problem

### Problem: "Critical error on this website"

1. Check `/var/log/php8.3-fpm.log` for `max_children` warnings
2. Check worker memory with `ps aux`
3. If workers > 200MB each: reduce `pm.max_requests` to 100
4. If pool exhausted: increase `max_children` (if RAM allows) or upgrade server

### Problem: Memory exhaustion errors

1. Check WordPress limits: `wp eval 'echo WP_MEMORY_LIMIT;'`
2. If 40M: add `WP_MEMORY_LIMIT` to `application.php`
3. Check `php_memory_limit` in Trellis config
4. Check for bloated transients in database

### Problem: Slow admin panel

1. Check autoloaded options size (should be < 1MB)
2. Consider Redis caching
3. Clean up expired transients: `wp transient delete --expired`

### Problem: 504 Gateway Timeout

1. Usually indicates workers are all busy
2. Check `max_children` setting
3. Increase idle workers (`min_spare_servers`, `start_servers`)
4. Look for long-running requests in access logs

### Problem: OOM (Out of Memory) during deploy

1. Reduce `max_children` temporarily
2. Deploy during low-traffic period
3. Upgrade server RAM
4. Check if `wp acorn optimize` is running (needs ~3GB headroom)

## Additional Resources

- [Trellis PHP Configuration](https://roots.io/trellis/docs/php/)
- [Trellis Redis Setup](https://roots.io/trellis/docs/redis/)
- [PHP-FPM Configuration Reference](https://www.php.net/manual/en/install.fpm.configuration.php)
