# Mail Configuration Issues

## SSH User Access

**Important**: When troubleshooting mail issues, use the appropriate SSH user:

- **`web` user** (Recommended for most operations)
  - Read-only access to logs and files
  - Can run WP-CLI commands
  - No sudo access (passwordless)
  - Example: `ssh web@example.com`

- **`admin_user`** (For administrative tasks)
  - Full sudo access with password
  - Required for: viewing system logs, checking protected config files
  - Use when commands require `sudo`
  - Example: `ssh admin_user@example.com "sudo journalctl"`
  - **Replace `admin_user` with your configured username** (e.g., `admin`, `deploy`, `warden`, your name, etc.)

- **`root` user** (Avoid - limited availability)
  - Only available on machines that provisioned the server
  - Not accessible from most machines
  - Trellis best practice: Don't use root for routine operations

**Throughout this guide**: Commands use `web@example.com` or `admin_user@example.com` as placeholders. Replace `admin_user` with your server's configured admin username.

---

## Table of Contents

- [Issue 1: sSMTP Configuration After Trellis Upgrade](#issue-1-ssmtp-configuration-after-trellis-upgrade)
  - [Problem](#problem)
  - [Symptoms](#symptoms)
  - [Diagnosis](#diagnosis)
  - [Solution](#solution)
  - [Prevention](#prevention)
- [Issue 2: WordPress Email Bounces - Non-Existent Admin Email](#issue-2-wordpress-email-bounces---non-existent-admin-email)
  - [Problem](#problem-1)
  - [Symptoms](#symptoms-1)
  - [Diagnosis](#diagnosis-1)
  - [Solution](#solution-1)
  - [Testing](#testing)
  - [Prevention](#prevention-1)

---

## Issue 1: sSMTP Configuration After Trellis Upgrade

### Problem

After a Trellis upgrade, mail functionality stopped working because the main configuration file `trellis/group_vars/all/mail.yml` was overwritten with default settings.

### Symptoms

System logs show repeated SMTP connection failures with error messages like:

- `Unable to locate smtp.example.com`
- `Cannot open smtp.example.com:587`
- `MAIL (mailed X bytes of output but got status 0x0001 from MTA)`

### Diagnosis

#### Check System Logs

SSH into the server and examine recent logs for mail-related errors:

```bash
ssh admin_user@domain.com "sudo journalctl -b | tail -50"
```

Note: Use your admin user (with sudo access) for administrative tasks. The `web` user does not have sudo access.

#### Key Error Messages to Look For

```
sSMTP[12502]: Unable to locate smtp.example.com
cron[12502]: sendmail: Cannot open smtp.example.com:587
sSMTP[12502]: Cannot open smtp.example.com:587
CRON[12499]: (root) MAIL (mailed 65 bytes of output but got status 0x0001 from MTA
```

#### Verify Mail Configuration

Check if `trellis/group_vars/all/mail.yml` contains default placeholder values instead of actual SMTP credentials.

### Solution

#### Restore Proper Mail Settings

Edit `trellis/group_vars/all/mail.yml` with your actual SMTP configuration:

```yml
# Documentation: https://roots.io/trellis/docs/mail/
mail_smtp_server: smtp.yourdomain.com:587
mail_admin: admin@yourdomain.com
mail_hostname: yourdomain.com
mail_user: your_smtp_username
mail_password: "{{ vault_mail_password }}" # Define this variable in group_vars/all/vault.yml
```

#### Set Vault Password

Ensure the SMTP password is securely stored in `trellis/group_vars/all/vault.yml`:

```yml
vault_mail_password: your_actual_smtp_password
```

#### Re-provision Server

Apply the updated mail configuration:

```bash
trellis provision production
```

Or provision only the sSMTP configuration:

```bash
trellis provision --tags ssmtp production
```

### Prevention

#### Before Upgrading Trellis

1. **Backup configuration files** - Especially `group_vars/all/mail.yml`
2. **Review upgrade notes** - Check if configuration file formats have changed
3. **Use version control** - Commit current configuration before upgrading
4. **Document custom settings** - Keep a record of non-default values

#### After Upgrading Trellis

1. **Review configuration files** - Check for overwritten or reset values
2. **Compare with backup** - Verify custom settings were preserved
3. **Test mail functionality** - Send test emails after provisioning
4. **Monitor logs** - Watch for SMTP errors in the first 24 hours

#### Recommended Tools

Check mail configuration on remote server:

```bash
# Using admin user (requires sudo for protected files)
ssh admin_user@domain.com "sudo cat /etc/ssmtp/ssmtp.conf"
```

Test mail sending:

```bash
echo "Test message" | mail -s "Test Subject" your-email@example.com
```

---

## Issue 2: WordPress Email Bounces - Non-Existent Admin Email

### Problem

WordPress sends emails to the configured admin email address (e.g., site registration notifications, password resets, user notifications). If this email address doesn't exist, emails will bounce with "soft bounce" or "connection closed by recipient's server" errors.

This is especially common with **WordPress Multisite** where:
- Network admin emails are set to non-existent addresses (e.g., `admin@demo.example.com`)
- New site registrations trigger emails to the network admin
- Subsite admin emails may also be invalid

**Important**: This issue occurs even when sSMTP is properly configured. The server successfully sends the email through SMTP relay (e.g., Brevo), but the recipient's mail server rejects it because the mailbox doesn't exist.

### Symptoms

Email delivery logs or monitoring services (e.g., Brevo dashboard) show:

- **Soft bounce**: "Connection closed by recipient's server"
- **Hard bounce**: "Mailbox does not exist" or "User unknown"
- Email status: "Deferred" or "Failed"
- Emails successfully leave your server but never arrive

Example from Brevo logs:
```
From: wordpress@demo.example.com
To: admin@demo.example.com
Status: Soft bounce
Error: connection closed by recipient's server
```

### Diagnosis

#### Check WordPress Admin Email

**For single sites:**
```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp option get admin_email --path=web/wp"
```

**For multisite networks:**
```bash
# Check network-wide admin email
ssh web@example.com "cd /srv/www/example.com/current && \
  wp site option get admin_email --path=web/wp --url=https://example.com"

# Check all subsites
ssh web@example.com "cd /srv/www/example.com/current && \
  for site in \$(wp site list --field=url --path=web/wp --url=https://example.com); do \
    echo \"Site: \$site - Admin: \$(wp option get admin_email --path=web/wp --url=\$site)\"; \
  done"
```

#### Verify Email Address Exists

Check if the admin email address is actually a working mailbox:
- Try sending a test email to the address from another account
- Check with your email hosting provider (Dreamhost, Google Workspace, etc.)
- Verify DNS MX records are correct for the domain

#### Test WordPress Email Function

Send a test email from WordPress:
```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp eval \"wp_mail('your-real-email@example.com', 'Test Email', 'This is a test from WordPress'); \
  echo wp_mail('your-real-email@example.com', 'Test', 'Test') ? 'SUCCESS' : 'FAILED';\" \
  --path=web/wp --url=https://example.com"
```

### Solution

#### Update Single Site Admin Email

```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp option update admin_email 'real-email@example.com' --path=web/wp"
```

#### Update Multisite Network Admin Email

```bash
# Update network-wide admin email
ssh web@example.com "cd /srv/www/example.com/current && \
  wp site option update admin_email 'real-email@example.com' \
  --path=web/wp --url=https://example.com"

# Update main site admin email
ssh web@example.com "cd /srv/www/example.com/current && \
  wp option update admin_email 'real-email@example.com' \
  --path=web/wp --url=https://example.com"
```

#### Update All Subsites (Bulk Operation)

If you have multiple subsites with invalid admin emails:

```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  for site in \$(wp site list --field=url --path=web/wp --url=https://example.com); do \
    echo \"Updating \$site...\"; \
    wp option update admin_email 'real-email@example.com' --path=web/wp --url=\$site; \
  done"
```

#### Verify Changes

```bash
# Check network admin email
ssh web@example.com "cd /srv/www/example.com/current && \
  wp site option get admin_email --path=web/wp --url=https://example.com"

# Check all subsites
ssh web@example.com "cd /srv/www/example.com/current && \
  for site in \$(wp site list --field=url --path=web/wp --url=https://example.com); do \
    echo \"Site: \$site - Admin: \$(wp option get admin_email --path=web/wp --url=\$site)\"; \
  done"
```

### Testing

#### Test Server-Level Email (sSMTP)

Verify the server can send emails through SMTP relay:

```bash
ssh web@example.com "echo -e 'Subject: Test Email\n\nThis is a test' | \
  /usr/sbin/sendmail -v your-email@example.com"
```

Expected output should show successful SMTP authentication and delivery:
```
[<-] 220 smtp-relay.brevo.com ESMTP Service Ready
[->] EHLO example.com
[<-] 235 2.0.0 Authentication succeeded
[<-] 250 2.0.0 OK: queued as <...>
```

#### Test WordPress Email Function

```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp eval \"
  \\\$to = 'your-email@example.com';
  \\\$subject = 'Test: WordPress Email';
  \\\$message = 'This is a test email from WordPress.';
  \\\$result = wp_mail(\\\$to, \\\$subject, \\\$message);
  echo \\\$result ? 'Email sent successfully' : 'Email failed to send';
  \" --path=web/wp --url=https://example.com"
```

#### Test New Site Registration Email (Multisite)

For multisite networks, create a test subsite to verify registration emails work:

```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp site create --slug=test-registration --title='Test Site' \
  --email=your-email@example.com --path=web/wp --url=https://example.com"
```

You should receive a "New Site Registration" email at your address.

### Prevention

#### Initial WordPress Setup

When setting up a new WordPress site or multisite network:

1. **Use a real, working email address** for the admin email during installation
2. **Verify the email address exists** before completing WordPress installation
3. **Test email delivery** immediately after setup

#### Regular Audits

Periodically check for invalid email addresses:

```bash
# Audit all admin emails in multisite
ssh web@example.com "cd /srv/www/example.com/current && \
  for site in \$(wp site list --field=url --path=web/wp --url=https://example.com); do \
    email=\$(wp option get admin_email --path=web/wp --url=\$site); \
    echo \"Site: \$site\"; \
    echo \"Admin: \$email\"; \
    echo \"---\"; \
  done"
```

#### Email Monitoring

- Use email service dashboards (Brevo, Mailgun, SendGrid) to monitor bounces
- Set up alerts for soft/hard bounces
- Regularly review email delivery reports

#### Documentation

Document the correct admin email addresses for:
- Production sites
- Staging sites
- Development/demo sites

Keep this information in your project's `README.md` or operations documentation.

#### Common Pitfalls to Avoid

1. **Don't use non-existent subdomains**: Avoid `admin@demo.example.com` unless you've created that mailbox
2. **Don't use `.test` domains in production**: Replace development emails (`admin@example.test`) before deploying
3. **Don't assume email works**: Always test email delivery after WordPress setup or migrations
4. **Don't ignore bounce reports**: Soft bounces often indicate configuration issues