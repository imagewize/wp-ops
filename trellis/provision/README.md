# Provisioning

## Chapter Purpose

This chapter collects the setup and provisioning steps you need to bring Trellis environments online and keep deployments repeatable.

## Table of Contents

### Setup Guides
- [New Machine Setup](NEW-MACHINE.md) - Configure Mac for Trellis development (install tools, understand architecture)
- [Project Setup](PROJECT-SETUP.md) - Clone and setup existing Trellis/Bedrock projects

### Configuration Guides
- [WordPress Cron](CRON.md) - How Trellis handles WordPress cron with system cron

### Command Reference
- [General Provisioning](#navigate-to-trellis-directory) - Common provisioning commands (below)

---

## Quick Command Reference

This section provides common Trellis provisioning and deployment commands. These are the day-to-day commands you'll use after your machine and project are set up.

For initial setup, see the [Setup Guides](#setup-guides) above.

## Navigate to trellis directory

```bash
cd trellis
```

## Provision development environment

```bash
ansible-playbook dev.yml
```

## Deploy to staging/production

```bash
ansible-playbook deploy.yml -e env=staging
ansible-playbook deploy.yml -e env=production
```

## Re-provision production with specific tags

Use `trellis provision` command instead of `ansible-playbook server.yml`:

```bash
trellis provision --tags php,nginx,composer production
```

## Full server provisioning

Use sparingly:

```bash
trellis provision production
```

## PHP Version Upgrade Process

1. Update `php_version` in `trellis/group_vars/all/main.yml`
2. Run with `php`, `nginx`, `wordpress-setup`, `users`, and `memcached` tags:

```bash
trellis provision --tags php,nginx,wordpress-setup,users,memcached production
```

**Why these tags are required:**
- `php` - Installs new PHP version and extensions
- `nginx` - Updates Nginx configuration for new PHP-FPM socket
- `wordpress-setup` - Creates `/etc/php/X.X/fpm/pool.d/wordpress.conf`
- `users` - **Critical**: Regenerates sudoers with new PHP version for passwordless `php-fpm reload`
- `memcached` - Installs PHP version-specific memcached extension (e.g., `php8.3-memcached`)

**Note:** Without the `users` tag, deployments will fail when trying to reload PHP-FPM because the sudoers configuration still references the old PHP version.

## WordPress Cron

Trellis automatically configures system cron instead of WordPress's built-in WP-Cron for more reliable scheduled task execution.

For complete documentation on how WordPress cron works with Trellis, including:
- How system cron replaces WP-Cron
- Verification and troubleshooting
- Customization options
- Migration considerations

See [CRON.md](CRON.md).
