# WordPress Cron with Trellis

## Overview

Trellis automatically configures **system cron** instead of WordPress's built-in WP-Cron for more reliable scheduled task execution.

## How It Works

### Traditional WordPress (WP-Cron)

Regular WordPress installations use **WP-Cron**, which only runs when someone visits your site:

```php
// wp-config.php (standard WordPress)
define('DISABLE_WP_CRON', false); // Default behavior
```

**Problems with WP-Cron:**
- Only triggers on page visits (if site has low traffic, tasks may never run)
- Multiple simultaneous visitors can trigger multiple cron runs
- Adds overhead to every page load
- Unreliable timing for scheduled tasks

### Trellis Approach (System Cron)

Trellis disables WP-Cron and uses **system cron** for reliable, predictable execution:

**1. WP-Cron is disabled** in `trellis/roles/deploy/vars/main.yml`:

```yaml
disable_wp_cron: true
```

This sets `DISABLE_WP_CRON` constant to `true` in WordPress configuration.

**2. System cron job is created** at `/etc/cron.d/wordpress-{site_name}`:

```bash
# Example: /etc/cron.d/wordpress-imagewize_com
#Ansible: example.com WordPress cron
*/15 * * * * web cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1
```

**What this does:**
- Runs every 15 minutes (*/15)
- Executes as the `web` user (same user that owns WordPress files)
- Changes to the current release directory
- Runs `wp cron event run --due-now` to process any due scheduled events
- Sends output to `/dev/null` (suppresses email notifications)

### WordPress Multisite Cron

For **WordPress multisite** installations, the cron configuration is different to ensure all subsites have their cron events processed:

```bash
# Example: /etc/cron.d/wordpress-demo_imagewize_com
#Ansible: demo.example.com WordPress cron
*/15 * * * * web cd /srv/www/demo.example.com/current && (wp site list --field=url | xargs -n1 -I % wp --url=% cron event run --due-now) > /dev/null 2>&1
```

**What this does:**
- `wp site list --field=url` - Lists all site URLs in the network
- `xargs -n1 -I % wp --url=% cron event run --due-now` - Runs cron for each site individually
- Ensures scheduled events are processed for all subsites, not just the main site

**Multisite cron log example:**

```
2025-11-28T02:30:01 ubuntu CRON[93961]: (web) CMD (cd /srv/www/demo.example.com/current && (wp site list --field=url | xargs -n1 -I % wp --url=% cron event run --due-now) > /dev/null 2>&1)
```

## Verification

### Check if WP-Cron is Disabled

```bash
# SSH into server
ssh admin@your.server.ip

# Check WordPress configuration
cd /srv/www/example.com/current
grep -i "DISABLE_WP_CRON" .env

# Should show:
# DISABLE_WP_CRON=true
```

### Check System Cron Configuration

```bash
# View the cron job
cat /etc/cron.d/wordpress-example_com

# Should show something like:
#Ansible: example.com WordPress cron
*/15 * * * * web cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1
```

### Verify Cron is Running

```bash
# Check system cron logs
sudo grep -i cron /var/log/syslog | tail -20

# Or on systems using journalctl
sudo journalctl -u cron | tail -20

# Test manually running the cron command
sudo -u web bash -c "cd /srv/www/example.com/current && wp cron event run --due-now"
```

**Example of successful cron execution in logs:**

```
2025-11-28T02:15:01 ubuntu CRON[93164]: (web) CMD (cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1)
2025-11-28T02:30:01 ubuntu CRON[93960]: (web) CMD (cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1)
2025-11-28T02:45:01 ubuntu CRON[94288]: (web) CMD (cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1)
```

If you see entries like these running every 15 minutes, your WordPress cron is working correctly.

**Filter logs for a specific site:**

```bash
# Check only cron logs for a specific site
sudo grep -i cron /var/log/syslog | grep "example.com" | tail -20

# Check cron logs for all sites
sudo grep -i cron /var/log/syslog | grep "(web) CMD" | tail -20

# Watch cron execution in real-time
sudo tail -f /var/log/syslog | grep -i cron
```

### List Scheduled WordPress Events

```bash
# SSH into server
cd /srv/www/example.com/current

# List all scheduled events
wp cron event list

# Show events grouped by schedule
wp cron event list --format=table

# Check when next events are due
wp cron event list --fields=hook,next_run_relative
```

## Common Cron Schedules

WordPress uses these default schedules:

- `hourly` - Once per hour
- `twicedaily` - Twice per day (12-hour intervals)
- `daily` - Once per day

Custom schedules can be added by plugins.

## Troubleshooting

### Issue: Scheduled Posts Not Publishing

**Symptoms:** Posts scheduled to publish remain in "Scheduled" status

**Solutions:**

```bash
# 1. Check if cron is running
sudo -u web bash -c "cd /srv/www/example.com/current && wp cron event run --due-now"

# 2. List scheduled publish events
wp cron event list | grep publish

# 3. Manually trigger the missed schedule check
wp cron event run --due-now

# 4. Check server timezone matches WordPress timezone
date
wp option get timezone_string

# 5. Check system cron is running
sudo systemctl status cron
```

### Issue: Plugin-Specific Scheduled Tasks Not Running

**Symptoms:** Backup plugins, cache clearing, or other scheduled tasks don't execute

**Solutions:**

```bash
# 1. List all scheduled events
wp cron event list

# 2. Check if the specific event exists
wp cron event list | grep plugin-name

# 3. Manually trigger the event
wp cron event run plugin_hook_name

# 4. Check plugin documentation for required WP-Cron support
# Some plugins may need wp-cron.php direct access

# 5. If plugin requires wp-cron.php access, add Nginx location block
# See "Alternative: Direct wp-cron.php Access" below
```

### Issue: Too Many Cron Events Running

**Symptoms:** High server load at cron execution times

**Solutions:**

```bash
# 1. List all events to identify heavy tasks
wp cron event list --format=csv > cron-events.csv

# 2. Identify duplicate or unnecessary events
wp cron event list | sort | uniq -c

# 3. Delete problematic events
wp cron event delete plugin_hook_name

# 4. Adjust cron frequency if needed (see "Customization" below)
```

## Customization

### Change Cron Frequency

The default is every 15 minutes (`*/15`). To change:

**Option 1: Edit Trellis Role (Recommended)**

Edit `trellis/roles/wordpress-setup/tasks/main.yml` and look for the cron task, then re-provision:

```bash
trellis provision production --tags wordpress-setup
```

**Option 2: Manual Edit (Not Recommended)**

```bash
# SSH into server
ssh admin@server.ip

# Edit cron file
sudo nano /etc/cron.d/wordpress-example_com

# Change schedule (e.g., every 5 minutes)
*/5 * * * * web cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1

# Cron will automatically reload changes
```

**Cron schedule examples:**
- `*/5 * * * *` - Every 5 minutes
- `*/10 * * * *` - Every 10 minutes
- `*/15 * * * *` - Every 15 minutes (default)
- `*/30 * * * *` - Every 30 minutes
- `0 * * * *` - Every hour (at :00)

### Add Email Notifications for Errors

By default, output is sent to `/dev/null`. To receive emails on errors:

```bash
# Edit cron file
sudo nano /etc/cron.d/wordpress-example_com

# Remove the redirect to capture errors
*/15 * * * * web cd /srv/www/example.com/current && wp cron event run --due-now 2>&1

# Or send to specific email
*/15 * * * * web cd /srv/www/example.com/current && wp cron event run --due-now 2>&1 | mail -s "WP Cron" admin@example.com
```

**Note:** Make sure your server has a mail transport agent (MTA) configured.

### Run Specific Events More Frequently

If you need certain events to run more often than every 15 minutes:

```bash
# Add additional cron entries for specific hooks
# Example: Run backups every hour

# Edit cron file
sudo nano /etc/cron.d/wordpress-example_com

# Add line:
0 * * * * web cd /srv/www/example.com/current && wp cron event run backup_hook --due-now > /dev/null 2>&1
```

## Alternative: Direct wp-cron.php Access

Some legacy plugins may require direct access to `wp-cron.php`. While not recommended, you can enable this:

**Add Nginx location block** in `trellis/roles/wordpress-setup/templates/wordpress-site.conf.j2`:

```nginx
# Allow direct wp-cron.php access (only if needed by legacy plugins)
location = /wp/wp-cron.php {
    include fastcgi_params;
    fastcgi_pass $upstream;
    fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
    fastcgi_param DOCUMENT_ROOT $realpath_root;
}
```

Then re-provision:

```bash
trellis provision production --tags nginx
```

**Warning:** This re-enables the WP-Cron problems mentioned above. Only use if absolutely necessary.

## Migration Considerations

When migrating from traditional WordPress hosting to Trellis:

### Before Migration

On your old hosting, if you had custom cron jobs in cPanel or similar:

1. Document all custom cron jobs
2. Note their schedules and commands
3. Identify if they're WordPress-related or server tasks

### After Migration

1. **WordPress cron events are automatically preserved** - They're stored in the database, so they migrate with your data
2. **System-level cron jobs need to be recreated** - Add them to `/etc/cron.d/` or use Trellis configuration

### Testing After Migration

```bash
# 1. Verify WP-Cron is disabled
grep DISABLE_WP_CRON /srv/www/example.com/current/.env

# 2. Check system cron exists
cat /etc/cron.d/wordpress-example_com

# 3. List WordPress scheduled events
wp cron event list

# 4. Manually run cron to test
sudo -u web bash -c "cd /srv/www/example.com/current && wp cron event run --due-now"

# 5. Check for errors
tail -f /var/log/syslog | grep -i cron
```

## Best Practices

1. **Keep default 15-minute interval** - It's a good balance between responsiveness and server load
2. **Monitor cron execution** - Set up alerts for failed cron jobs
3. **Don't rely on WP-Cron for critical tasks** - Use system cron or external monitoring for mission-critical tasks
4. **Test after major updates** - Verify cron still works after WordPress core or plugin updates
5. **Document custom schedules** - If you add custom cron frequencies, document them in your project README

## Additional Resources

- [WP-CLI Cron Commands](https://developer.wordpress.org/cli/commands/cron/)
- [WordPress Action Scheduler](https://actionscheduler.org/) - Alternative to WP-Cron for plugins
- [Crontab Guru](https://crontab.guru/) - Cron schedule expression generator
- [Trellis WordPress Setup](https://github.com/roots/trellis/tree/master/roles/wordpress-setup)

## Related Documentation

- [Provisioning Guide](README.md) - Trellis provisioning commands
- [Migration Guide](../../wp-cli/migration/REGULAR-TO-TRELLIS.md) - Migrating from traditional WordPress
- [Deployment](https://roots.io/trellis/docs/deployments/) - Trellis deployment process
