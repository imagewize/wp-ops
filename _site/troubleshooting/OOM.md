# Out of Memory (OOM) Troubleshooting Guide

## Table of Contents

1. [Problem Overview](#problem-overview)
2. [Quick Diagnosis Commands](#quick-diagnosis-commands)
3. [The Discovery](#the-discovery)
4. [Root Cause Analysis](#root-cause-analysis)
5. [Investigation Process](#investigation-process)
   - [System Cron Jobs Audit](#system-cron-jobs-audit)
   - [WordPress Cron Events](#wordpress-cron-events)
   - [Action Scheduler Context](#action-scheduler-context)
   - [System Status Check](#system-status-check)
6. [Trellis WP-Cron Configuration](#trellis-wp-cron-configuration)
7. [Next Steps](#next-steps)

## Problem Overview

When a server runs out of memory, the Linux kernel's OOM (Out of Memory) killer terminates processes to free up resources. This guide documents troubleshooting an OOM issue on a 4GB Trellis/WordPress server where processes were being killed due to memory exhaustion.

## Quick Diagnosis Commands

### Check for OOM Events in Previous Boot

The most effective command to find OOM killer events:

```sh
ssh root@domain.com 'journalctl -k -b -2 | grep -Ei "oom|killed process|out of memory"'
```

This checks the kernel logs from 2 boots ago (`-b -2`), which is crucial if the server has been restarted since the issue occurred.

### Check Current Memory Usage

```sh
ssh root@domain.com "ps aux --sort=-%mem | head -10"
```

### Check PHP-FPM Worker Memory

```sh
ssh root@domain.com "ps aux --sort=-%mem | grep 'php-fpm: pool' | head -5 | awk '{print \$6/1024 \" MB - PID \" \$2}'"
```

### Check WordPress Cron Events

```sh
ssh web@domain.com "cd /srv/www/domain.com/current && wp cron event list --path=web/wp"
```

### Audit All System Cron Jobs

```sh
ssh root@domain.com 'ls -lah /etc/cron* /var/spool/cron/crontabs'
```

## The Discovery

After checking current boot logs and finding no issues, the critical discovery came from checking **previous boot logs**:

```sh
ssh root@domain.com 'journalctl -k -b -2 | grep -Ei "oom|killed process|out of memory"'
```

### The Smoking Gun

Two OOM events were found on November 24, approximately 30 minutes apart:

**Event 1 - Nov 24 01:48:27:**
```
Nov 24 01:48:27 server kernel: systemd invoked oom-killer: gfp_mask=0x140cca(GFP_HIGHUSER_MOVABLE|__GFP_COMP), order=0, oom_score_adj=0
Nov 24 01:48:27 server kernel: oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/,mems_allowed=0,global_oom,task_memcg=/system.slice/cron.service,task=php,pid=70787,uid=1000
Nov 24 01:48:27 server kernel: Out of memory: Killed process 70787 (php) total-vm:3621976kB, anon-rss:3235148kB, file-rss:5760kB, shmem-rss:69120kB, UID:1000 pgtables:6960kB oom_score_adj:0
```

**Event 2 - Nov 24 02:21:02:**
```
Nov 24 02:21:02 server kernel: systemd invoked oom-killer: gfp_mask=0x140cca(GFP_HIGHUSER_MOVABLE|__GFP_COMP), order=0, oom_score_adj=0
Nov 24 02:21:02 server kernel: oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/,mems_allowed=0,global_oom,task_memcg=/system.slice/cron.service,task=php,pid=71246,uid=1000
Nov 24 02:21:02 server kernel: Out of memory: Killed process 71246 (php) total-vm:3236952kB, anon-rss:2517056kB, file-rss:5632kB, shmem-rss:69120kB, UID:1000 pgtables:6188kB oom_score_adj:0
```

## Root Cause Analysis

### Key Findings from OOM Logs

Both OOM events show identical characteristics:

1. **Process Name:** `php` (NOT `php-fpm: pool wordpress`)
2. **User ID:** `1000` (deploy user, not `www-data`)
3. **Parent Service:** `task_memcg=/system.slice/cron.service`
4. **Memory Consumption:** 2.5-3.2 GB RSS per process
   - Event 1: `anon-rss:3235148kB` (3.08 GB)
   - Event 2: `anon-rss:2517056kB` (2.40 GB)

### Critical Insight

🔥 **This is NOT a PHP-FPM issue.**

The OOM logs clearly show:
- **Standalone PHP processes** triggered by system cron
- Each consuming 2.5-3.2 GB of RAM
- On a 4GB server, this is catastrophic

The key indicator:
```
task_memcg=/system.slice/cron.service, task=php, uid=1000
```

This means:
- ❗ A **cron job** is running a PHP script
- ❗ That script consumes massive memory (likely a leak or heavy task)
- ❗ PHP-FPM workers were healthy (~120-130 MB each) during the incident
- ❗ The culprit runs every ~30 minutes based on timing

## Investigation Process

### System Cron Jobs Audit

Checking all cron jobs on the system:

```sh
ssh root@domain.com 'ls -lah /etc/cron* /var/spool/cron/crontabs'
```

**Relevant cron files in `/etc/cron.d/`:**

```
-rw-r--r-- 1 root root  712 Sep 27  2024 php
-rw-r--r-- 1 root root  162 Nov 22 04:28 php-fpm-monitor
-rw-r--r-- 1 root root  138 Feb 13  2025 wordpress-example_com
-rw-r--r-- 1 root root  210 Apr  4  2025 wordpress-multisite-example_com
-rw-r--r-- 1 root root  141 Feb 13  2025 letsencrypt-certificate-renewal
```

**WordPress cron jobs** are the prime suspects:
- `wordpress-example_com` - Main site WP-Cron (every 15 minutes)
- `wordpress-multisite-example_com` - Multisite WP-Cron
- These trigger curl requests to wp-cron.php which spawns PHP processes

### WordPress Cron Events

Current scheduled WordPress cron events:

```sh
ssh web@domain.com "cd /srv/www/domain.com/current && wp cron event list --path=web/wp"
```

**Output:**
```
hook                                         next_run_gmt         next_run_relative      recurrence
action_scheduler_run_queue                   2025-11-25 03:45:57  now                    1 minute
rocket_update_dynamic_lists                  2025-11-25 03:56:19  now                    1 week
rocket_preload_clean_rows_time_event         2025-11-25 04:06:19  8 minutes 27 seconds   1 week
jetpack_clean_nonces                         2025-11-25 04:20:32  22 minutes 40 seconds  1 hour
wp_privacy_delete_old_export_files           2025-11-25 04:33:15  35 minutes 23 seconds  1 hour
wc_admin_process_orders_milestone            2025-11-25 04:40:31  42 minutes 39 seconds  1 hour
wc_admin_unsnooze_admin_notes                2025-11-25 04:42:46  44 minutes 54 seconds  1 hour
wp_scheduled_delete                          2025-11-25 05:13:18  1 hour 15 minutes      1 day
delete_expired_transients                    2025-11-25 05:13:18  1 hour 15 minutes      1 day
```

**Suspects:**
- `action_scheduler_run_queue` - Runs every minute, processes WooCommerce background jobs
- `rocket_update_dynamic_lists` - WP Rocket cache plugin
- `wc_admin_*` - WooCommerce admin tasks

### Action Scheduler Context

#### Previous Mitigation Attempt

A MU plugin was previously deployed to disable Action Scheduler's async runner:

`app/mu-plugins/disable-action-scheduler-async.php`:
```php
<?php
/**
 * Plugin Name: Disable Action Scheduler Async Runner
 * Description: Disables WooCommerce Action Scheduler async AJAX runner to prevent PHP-FPM worker memory accumulation.
 * Version: 1.0.0
 *
 * The async runner constantly polls via admin-ajax.php, accumulating memory in PHP-FPM workers.
 * This filter disables the async runner - Action Scheduler will use WP-Cron instead.
 */

add_filter('action_scheduler_allow_async_request_runner', '__return_false');
```

This MU plugin was later **removed** as it didn't resolve the original PHP-FPM pool exhaustion issue. However, this may have inadvertently shifted the problem to WP-Cron context.

#### Checking for Failed Action Scheduler Jobs

```sh
ssh web@domain.com "cd /srv/www/domain.com/current && wp db query 'SELECT action_id, hook, status, scheduled_date_gmt, attempts FROM wp_actionscheduler_actions WHERE status = \"failed\" ORDER BY scheduled_date_gmt DESC LIMIT 50;' --path=web/wp"
```

Failed or stuck Action Scheduler jobs can consume excessive memory during processing.

### System Status Check

When checking the system **after** the OOM events (current boot), everything appeared normal:

#### PHP-FPM Worker Memory (Healthy)

```sh
ssh root@domain.com "ps aux --sort=-%mem | grep 'php-fpm: pool' | head -5"
```

**Output:**
```
127.105 MB - PID 12214
121.93 MB - PID 12227
120.766 MB - PID 12215
119.559 MB - PID 12219
118.961 MB - PID 12218
```

PHP-FPM workers consuming 120-130 MB each is normal and healthy. This confirms the issue is **not** with PHP-FPM.

#### Service Memory Peak (From previous boot)

```sh
ssh root@domain.com "journalctl --since '2025-11-25 00:00:00' --until '2025-11-25 23:59:59' | grep -i 'memory peak'"
```

**Key findings:**
```
php8.3-fpm.service: Consumed 3h 18min 9.892s CPU time, 2.8G memory peak, 774.8M memory swap peak
mariadb.service: Consumed 4min 999ms CPU time, 191.3M memory peak, 146.7M memory swap peak
nginx.service: Consumed 3min 55.066s CPU time, 71.6M memory peak, 15.0M memory swap peak
```

- PHP-FPM peaked at 2.8GB **total** across all workers (normal for busy site)
- Individual workers were healthy
- The OOM culprit was a **separate PHP process**, not part of PHP-FPM

#### Database Health Check

```sh
ssh web@domain.com "cd /srv/www/domain.com/current && wp db check --path=web/wp"
```

All 163 WordPress tables checked successfully - database was not corrupted by the OOM events.

## Trellis WP-Cron Configuration

Trellis disables WordPress's default polling mechanism (`DISABLE_WP_CRON=true`) and uses system cron to trigger `wp-cron.php`:

**From Trellis `wordpress-setup` role:**
```yaml
- name: Setup WP system cron
  cron:
    name: "{{ item.key }} WordPress cron"
    minute: "*/15"
    user: "{{ web_user }}"
    job: "curl -k -s {{ site_env.wp_siteurl }}/wp-cron.php > /dev/null 2>&1"
    cron_file: "wordpress-{{ item.key | replace('.', '_') }}"
  with_dict: "{{ wordpress_sites }}"
  when: site_env.disable_wp_cron and not item.value.multisite.enabled | default(false)
```

This creates `/etc/cron.d/wordpress-domain_com` that runs every 15 minutes.

**The Problem:**
- Cron triggers `wp-cron.php` via curl
- WordPress spawns a **standalone PHP process** (not PHP-FPM)
- This process uses **PHP CLI settings**, not PHP-FPM pool limits
- Trellis provides `php_cli_memory_limit` variable (default: `-1` unlimited)
- **If not explicitly set** in `group_vars/*/main.yml`, PHP CLI has unlimited memory
- Heavy scheduled tasks can consume unbounded memory until OOM
- On 4GB server, 3GB consumption = catastrophic

## Next Steps

### Immediate Actions

1. **Verify PHP CLI memory limit is unlimited:**
   ```sh
   ssh root@domain.com "php -i | grep memory_limit"
   ```

   **Expected output:**
   ```
   memory_limit => -1 => -1
   ```

   This confirms PHP CLI has **unlimited memory**, which is the root cause.

   **Fix via Trellis:** Add `php_cli_memory_limit` to your `group_vars/production/main.yml`:
   ```yaml
   php_cli_memory_limit: 512M
   ```

   Then re-provision:
   ```sh
   trellis provision production
   ```

   **Manual fix (alternative):** Edit `/etc/php/8.3/cli/php.ini` directly:
   ```ini
   memory_limit = 512M
   ```

   **Note:** Trellis provides the `php_cli_memory_limit` variable (from `roles/php/defaults/main.yml`), but it defaults to `-1` (unlimited) if not explicitly set in your `group_vars/*/main.yml`.

2. **Identify the problematic WordPress cron task:**
   - Check Action Scheduler queue for stuck/failed jobs
   - Review WP Rocket cache tasks
   - Check WooCommerce admin tasks
   - Monitor which cron hook runs when OOM occurs

3. **Add monitoring:**
   ```sh
   # Log PHP processes spawned by cron
   */5 * * * * root ps aux | grep -E "php.*cron" >> /var/log/php-cron-monitor.log
   ```

4. **Consider memory limits per cron job:**
   Modify WP-Cron trigger to include memory limit:
   ```sh
   php -d memory_limit=512M wp-cron.php
   ```

### Long-term Solutions

1. **Upgrade server RAM** if workload requires it (consider 8GB)
2. **Optimize heavy scheduled tasks:**
   - Break large tasks into smaller batches
   - Add time/memory limits to custom cron jobs
   - Review Action Scheduler queue regularly
3. **Implement proper monitoring:**
   - Alert on OOM events
   - Track PHP process memory consumption
   - Monitor cron job execution times
4. **Consider dedicated cron server** for large sites

### Verification

After implementing fixes, verify with:
```sh
# Check for new OOM events (run daily)
ssh root@domain.com 'journalctl -k --since "24 hours ago" | grep -Ei "oom|killed process"'

# Monitor PHP CLI process memory
ssh root@domain.com 'watch "ps aux | grep php | grep -v php-fpm | grep -v grep"'
```
