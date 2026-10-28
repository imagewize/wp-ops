# fail2ban WordPress Protection

Automatic IP blocking for WordPress brute force attacks using fail2ban.

Part of the [wp-ops](https://github.com/imagewize/wp-ops) toolkit for WordPress operations and server management.

**Why it matters, how it works, and the filter fix that stopped false bans:**
[fail2ban for wp-login.php on Trellis: Turn the Jail On, Anchor the Filter, Keep an Nginx Deny List for the Rest](https://wpvilla.in/fail2ban-wordpress-wp-login-trellis-nginx-deny-list/).
This page is the command reference.

---

## SSH users

- `admin_user` below is a placeholder for your Trellis admin user (from
  `group_vars/{env}/users.yml`). It has sudo, which asks for a password, so use
  `ssh -t` for one-off commands.
- The `web` user has no sudo but can read site logs.

Trellis installs fail2ban and protects SSH by default. The WordPress jails ship
disabled.

---

## Enable

`trellis/group_vars/all/security.yml`:

```yaml
fail2ban_bantime: 600        # seconds banned
fail2ban_maxretry: 6         # failures before a ban (global, incl. sshd)
fail2ban_findtime: 600       # window the failures are counted in

fail2ban_services_custom:
  - name: wordpress_wp_login
    filter: wordpress-wp-login
    enabled: "true"
    port: http,https
    logpath: "{{ www_root }}/**/logs/access.log"
    # maxretry: 6            # optional per-jail override of the global value
```

Apply only the fail2ban role:

```bash
cd trellis
trellis provision --tags fail2ban production
```

Re-run the same command after any change to `security.yml`.

**`wordpress_xmlrpc`**: only enable it if `curl -I https://yoursite.com/xmlrpc.php`
does *not* return 403 or 444. If Nginx already refuses XML-RPC, the jail has
nothing to catch.

### Never ban your own IP

```yaml
ip_whitelist:
  - 127.0.0.0/8
  - "{{ ipify_public_ip | default('') }}"   # the machine you provision from
  - 203.0.113.0/24                           # office network (example)
```

`ip_whitelist` feeds fail2ban's `ignoreip`, so listed addresses are exempt from
the sshd and WordPress jails.

---

## Check

```bash
ssh -t admin_user@yoursite.com "sudo fail2ban-client status"
ssh -t admin_user@yoursite.com "sudo fail2ban-client status wordpress_wp_login"
ssh -t admin_user@yoursite.com "sudo tail -50 /var/log/fail2ban.log"
ssh -t admin_user@yoursite.com "sudo grep 'Ban ' /var/log/fail2ban.log | tail -20"
```

The jail status lists the monitored log files, failure and ban counts, and the
currently banned IPs.

## Ban and unban

```bash
sudo fail2ban-client set wordpress_wp_login banip 1.2.3.4
sudo fail2ban-client set wordpress_wp_login unbanip 1.2.3.4
sudo fail2ban-client unban --all
```

### Locked out

1. Unban yourself from another connection (phone hotspot, VPN) with `unbanip` above.
2. Or, from the provider's server console: `sudo systemctl stop fail2ban`, log in,
   add your IP to `ip_whitelist`, re-provision, `sudo systemctl start fail2ban`.

---

## Troubleshooting

Not banning attackers:

```bash
# Jail enabled and running?
ssh -t admin_user@yoursite.com "sudo fail2ban-client status | grep wordpress"
ssh -t admin_user@yoursite.com "sudo systemctl status fail2ban"

# Is the log being written?
ssh web@yoursite.com "tail /srv/www/yoursite.com/logs/access.log"

# Does the filter match? Look for a non-zero "matched" count.
ssh -t admin_user@yoursite.com "sudo fail2ban-regex \
  /srv/www/yoursite.com/logs/access.log \
  /etc/fail2ban/filter.d/wordpress-wp-login.conf"

# Config errors
ssh -t admin_user@yoursite.com "sudo fail2ban-client -d"
ssh -t admin_user@yoursite.com "sudo grep ERROR /var/log/fail2ban.log | tail -20"
```

Banning legitimate users: make sure the filter is anchored to the request field,
not the whole log line, or a `wp-login.php` referrer counts as a failure. The
anchored filter is in the post linked at the top:

```ini
failregex = ^<HOST> .* "POST [^"]*wp-login\.php[^"]*" 200
```

A failed login returns `200` (form shown again); a successful one returns `302`.

---

## Beyond fail2ban

- Persistent or high-volume attackers: permanent Nginx blocks in
  [MANUAL-IP-BLOCKING.md](./MANUAL-IP-BLOCKING.md)
- Malware detection: [wp-cli/security](../../wp-cli/security/) scanners
- Attack patterns in the logs: `wp-ops security-scan example.com production`

## Resources

- [Trellis security documentation](https://roots.io/trellis/docs/security/)
- [fail2ban documentation](https://github.com/fail2ban/fail2ban/wiki)
