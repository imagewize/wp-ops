# MariaDB Troubleshooting Guide

This guide covers common MariaDB issues on Trellis-managed servers, including startup failures, plugin problems, and diagnostic approaches.

## Table of Contents

- [Common Errors](#common-errors)
- [Diagnostic Commands](#diagnostic-commands)
- [Compression Provider Plugin Failure](#compression-provider-plugin-failure)
- [Connection Issues](#connection-issues)
- [Performance Issues](#performance-issues)
- [Backup and Recovery](#backup-and-recovery)

## Common Errors

### Ansible "Set root user password" Fails

**Symptom:** During Trellis provision, the MariaDB role fails with:
```
TASK [mariadb : Set root user password] ****************************************
failed: [server-ip] (item=None) => {"censored": "...no_log: true..."}
```

**Common causes:**
1. MariaDB service is not running (most common)
2. Root password already set differently
3. Socket connection issues

**First step:** Always check if MariaDB is actually running before assuming password issues.

### Service Failed to Start

**Symptom:**
```
systemd[1]: mariadb.service: Main process exited, code=exited, status=7/NOTRUNNING
systemd[1]: mariadb.service: Failed with result 'exit-code'.
systemd[1]: Failed to start mariadb.service - MariaDB database server.
```

**Check the logs:**
```bash
sudo journalctl -u mariadb -n 50
```

## Diagnostic Commands

### Check Service Status

```bash
# Service status
sudo systemctl status mariadb

# Is MariaDB process running?
sudo ps aux | grep mysql

# Recent logs
sudo journalctl -u mariadb -n 50

# Watch logs in real-time
sudo journalctl -u mariadb -f
```

### Check Database Connectivity

```bash
# Test connection (get password from vault)
mysql -u root -p'[password]' -e "SELECT 1;"

# Check WordPress database
mysql -u root -p'[password]' -e "SHOW DATABASES;"

# Check user privileges
mysql -u root -p'[password]' -e "SELECT user, host FROM mysql.user;"
```

### Check Configuration

```bash
# Main configuration
cat /etc/mysql/mariadb.conf.d/50-server.cnf

# All configuration files
ls -la /etc/mysql/mariadb.conf.d/

# Search for specific settings
grep -r "innodb" /etc/mysql/
```

### Check Resources

```bash
# Disk space (MariaDB needs space for logs, temp tables)
df -h

# Memory usage
free -h

# MariaDB memory consumption
ps aux | grep mariadbd | awk '{print $6/1024" MB"}'
```

## Compression Provider Plugin Failure

A common issue on Ubuntu 24.04 with MariaDB 10.11+.

### Symptoms

MariaDB fails to start with errors like:
```
[ERROR] mariadbd: Can't open shared library '/usr/lib/mysql/plugin/provider_bzip2.so'
[ERROR] Couldn't load plugins from 'provider_bzip2.so'.
[ERROR] /usr/sbin/mariadbd: unknown variable 'provider_bzip2=force_plus_permanent'
[ERROR] Aborting
```

### Cause

Configuration files exist for compression plugins that aren't installed:
- `/etc/mysql/mariadb.conf.d/provider_bzip2.cnf`
- `/etc/mysql/mariadb.conf.d/provider_lz4.cnf`
- `/etc/mysql/mariadb.conf.d/provider_lzma.cnf`
- `/etc/mysql/mariadb.conf.d/provider_lzo.cnf`
- `/etc/mysql/mariadb.conf.d/provider_snappy.cnf`

This happens when:
- MariaDB was upgraded without installing plugin packages
- Ubuntu repository restructured plugin distribution
- Config files were manually added but packages never installed

### Solution A: Disable Plugins (Recommended)

These plugins are optional and not needed for WordPress:

```bash
# Disable all compression provider configs
sudo mv /etc/mysql/mariadb.conf.d/provider_lz4.cnf /etc/mysql/mariadb.conf.d/provider_lz4.cnf.disabled
sudo mv /etc/mysql/mariadb.conf.d/provider_snappy.cnf /etc/mysql/mariadb.conf.d/provider_snappy.cnf.disabled
sudo mv /etc/mysql/mariadb.conf.d/provider_lzo.cnf /etc/mysql/mariadb.conf.d/provider_lzo.cnf.disabled
sudo mv /etc/mysql/mariadb.conf.d/provider_bzip2.cnf /etc/mysql/mariadb.conf.d/provider_bzip2.cnf.disabled
sudo mv /etc/mysql/mariadb.conf.d/provider_lzma.cnf /etc/mysql/mariadb.conf.d/provider_lzma.cnf.disabled

# Start MariaDB
sudo systemctl start mariadb
sudo systemctl status mariadb
```

### Solution B: Install Plugin Packages

If you need compression plugins:

```bash
sudo apt update
sudo apt install mariadb-plugin-provider-bzip2 \
                 mariadb-plugin-provider-lz4 \
                 mariadb-plugin-provider-lzma \
                 mariadb-plugin-provider-lzo \
                 mariadb-plugin-provider-snappy

sudo systemctl restart mariadb
```

**Note:** Package names may vary by MariaDB version and Ubuntu release.

### Impact of Disabling Compression Plugins

**Low impact for WordPress sites:**
- WordPress databases don't use table-level compression by default
- Default zlib compression remains available (built-in)
- No data loss or performance degradation
- Only affects tables explicitly using `ROW_FORMAT=COMPRESSED`

## Connection Issues

### Socket Connection Errors

**Symptom:**
```
ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock'
```

**Solutions:**

```bash
# Check if socket exists
ls -la /var/run/mysqld/

# Check socket configuration
grep socket /etc/mysql/mariadb.conf.d/50-server.cnf

# Restart MariaDB
sudo systemctl restart mariadb
```

### Access Denied Errors

**Symptom:**
```
ERROR 1045 (28000): Access denied for user 'root'@'localhost'
```

**Check credentials in Trellis vault:**
```bash
# View vault (in your trellis directory)
ansible-vault view group_vars/production/vault.yml
```

**Reset root password (emergency):**
```bash
sudo systemctl stop mariadb
sudo mysqld_safe --skip-grant-tables &
mysql -u root

# In MySQL shell:
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_password';
FLUSH PRIVILEGES;
EXIT;

sudo systemctl restart mariadb
```

## Performance Issues

### Slow Queries

**Enable slow query log:**

Add to `/etc/mysql/mariadb.conf.d/50-server.cnf`:
```ini
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
```

**Analyze slow queries:**
```bash
sudo tail -50 /var/log/mysql/slow.log
```

### High Memory Usage

**Check current settings:**
```bash
mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
mysql -u root -p -e "SHOW VARIABLES LIKE 'key_buffer_size';"
```

**Recommended settings for small servers (4GB RAM):**
```ini
# In /etc/mysql/mariadb.conf.d/50-server.cnf
innodb_buffer_pool_size = 512M
key_buffer_size = 32M
```

### Table Lock Contention

**Check for locks:**
```bash
mysql -u root -p -e "SHOW PROCESSLIST;"
mysql -u root -p -e "SHOW ENGINE INNODB STATUS\G" | grep -A 20 "TRANSACTIONS"
```

## Backup and Recovery

### Quick Database Backup

```bash
# Backup single database
mysqldump -u root -p'[password]' database_name > backup.sql

# Backup all databases
mysqldump -u root -p'[password]' --all-databases > all_databases.sql

# Compressed backup
mysqldump -u root -p'[password]' database_name | gzip > backup.sql.gz
```

### Restore Database

```bash
# Restore from SQL file
mysql -u root -p'[password]' database_name < backup.sql

# Restore from compressed backup
gunzip < backup.sql.gz | mysql -u root -p'[password]' database_name
```

### Check Database Integrity

```bash
# Check all tables in a database
mysqlcheck -u root -p'[password]' --check database_name

# Repair tables
mysqlcheck -u root -p'[password]' --repair database_name
```

## After Fixing Issues

### Verify MariaDB is Running

```bash
sudo systemctl status mariadb
# Should show: Active: active (running)
```

### Test Database Connection

```bash
mysql -u root -p'[password]' -e "SELECT 1;"
```

### Continue Trellis Provision

```bash
cd trellis
trellis provision --tags mariadb production
# Or full provision
trellis provision production
```

### Test WordPress Sites

After fixing MariaDB issues, verify your WordPress sites are accessible and database operations work correctly.

## Prevention Tips

1. **Test provisions on staging first** - Always test major infrastructure changes before production

2. **Monitor MariaDB logs** - Set up log monitoring:
   ```bash
   sudo journalctl -u mariadb -f
   ```

3. **Regular backups** - Use the backup playbooks in this repository

4. **Check disk space** - MariaDB needs space for logs and temporary tables:
   ```bash
   df -h /var/lib/mysql
   ```

5. **Review Trellis updates** - When updating Trellis, review MariaDB role changes

## Lessons Learned

1. **Check service status first** - When database tasks fail, verify the service is running before assuming authentication issues

2. **Misleading Ansible errors** - "Set root user password failed" often means MariaDB isn't running, not a password problem

3. **Review full logs** - `journalctl -u mariadb` reveals the actual problem, which Ansible output may hide

4. **Optional plugins can break core service** - Missing plugin libraries can prevent MariaDB from starting entirely

5. **Simple solutions work** - Disabling unused optional features is often better than debugging them

## Related Resources

- [MariaDB Documentation](https://mariadb.com/kb/en/)
- [Trellis MariaDB Configuration](https://roots.io/trellis/docs/database-access/)
- [MariaDB Plugin Overview](https://mariadb.com/kb/en/plugin-overview/)
