# Admin User Creation via WP-CLI

Create WordPress administrator users safely from the command line using WP-CLI.

**Recommended approach** over PHP snippets — no code to remove, credentials aren't stored in files, and you have full control via the command line.

## Quick Command

```bash
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(openssl rand -base64 16)"
```

This:
- Creates user `temp_admin` with email `temp@example.com`
- Assigns the `administrator` role
- Generates a secure random 16-character password
- Outputs the password to the terminal (visible during execution)

## Basic Usage

### Create a user with a specific password

```bash
wp user create username user@example.com --role=administrator --user_pass="YourStrongPassword123!"
```

### Create a user with a generated password (more secure)

```bash
# macOS/Linux - using openssl for random password
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(openssl rand -base64 16)"

# Alternative: using pwgen (if installed)
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(pwgen -s 16 1)"

# Fallback: using date-based password (less secure but works everywhere)
wp user create temp_admin temp@example.com --role=administrator --user_pass="TempPass-$(date +%s)"
```

### Create without specifying password (WP-CLI will generate one)

```bash
wp user create temp_admin temp@example.com --role=administrator
# WP-CLI auto-generates a password and displays it
```

## Practical Examples

### Emergency admin access after lockout

When you've been locked out of WordPress (lost admin password, plugin conflict, etc.):

```bash
# Connect to server via SSH
ssh admin_user@yoursite.com

# Navigate to WordPress directory
cd /srv/www/yoursite.com/current

# Create temporary admin user
wp user create recovery_admin recovery@yoursite.com --role=administrator --user_pass="$(openssl rand -base64 16)"

# Note: WP-CLI will output the password - copy it immediately
# Then log in at: https://yoursite.com/wp-admin

# After regaining access, delete the temporary user:
wp user delete recovery_admin --yes
```

### Create admin with display name

```bash
wp user create john.doe john@example.com --role=administrator --display_name="John Doe" --first_name=John --last_name=Doe
```

### Create multiple admin users from a list

```bash
# Using a simple text file with format: username,email
while IFS=, read -r username email; do
  wp user create "$username" "$email" --role=administrator --user_pass="$(openssl rand -base64 16)"
done < users.csv
```

### Create admin and immediately change their password

```bash
# Create user
wp user create temp_admin temp@example.com --role=administrator --user_pass="initial_password"

# Change password (user must use password reset link, or admin can change it via WP Admin)
wp user update temp_admin --user_pass="new_secure_password"
```

## Security Best Practices

### Always use strong passwords

```bash
# Good: Random base64 string (16 chars = ~95 bits of entropy)
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(openssl rand -base64 16)"

# Better: Random base64 string (24 chars = ~143 bits of entropy)
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(openssl rand -base64 24)"

# Best: Use a password manager to generate and store the password
```

### Use temporary email addresses

```bash
# Use a mailinator-style disposable address for temporary access
temp_email="temp-$(date +%s)@example.com"
wp user create temp_admin "$temp_email" --role=administrator --user_pass="$(openssl rand -base64 16)"
```

### Delete temporary users after use

```bash
# List all admin users
wp user list --role=administrator --format=csv

# Delete a temporary user by login
wp user delete temp_admin --yes

# Delete a temporary user by ID
wp user delete 123 --yes

# Delete and reassign their content to another user
wp user delete temp_admin --yes --reassign=1
```

## Common Issues & Solutions

### "Error: Could not create user because email already exists"

```bash
# Check if email exists
wp user list --field=user_email | grep temp@example.com

# Check if username exists
wp user get temp_admin --field=user_login

# Use a different email or username
wp user create temp_admin2 temp2@example.com --role=administrator
```

### "Error: This username is already registered"

```bash
# List all users
wp user list --field=user_login

# Choose a different username
wp user create different_username temp@example.com --role=administrator
```

### User created but can't log in

```bash
# Verify the user exists and has correct role
wp user get temp_admin --fields=user_login,role,user_email

# Reset the password
wp user update temp_admin --user_pass="new_password"

# Check if user is marked as spam (some plugins do this)
wp user meta get temp_admin wp_user_level
```

## Automation & Scripting

### Create admin user in a deployment script

```bash
#!/bin/bash
# create-temp-admin.sh

SITE_DIR="/srv/www/yoursite.com/current"
USERNAME="deploy_temp_admin"
EMAIL="deploy@yoursite.com"

cd "$SITE_DIR"

# Only create if doesn't exist
if ! wp user get "$USERNAME" &>/dev/null; then
  PASSWORD=$(openssl rand -base64 16)
  wp user create "$USERNAME" "$EMAIL" --role=administrator --user_pass="$PASSWORD"
  echo "Temporary admin created. Password: $PASSWORD"
  echo "REMEMBER: Delete this user after use with: wp user delete $USERNAME --yes"
fi
```

### Create admin with environment variables

```bash
# Set variables
export WP_USER="temp_$(date +%Y%m%d)"
export WP_EMAIL="${WP_USER}@yoursite.com"
export WP_PASS=$(openssl rand -base64 16)

# Create user
wp user create "$WP_USER" "$WP_EMAIL" --role=administrator --user_pass="$WP_PASS"

# Display credentials (be careful with terminal history)
echo "User: $WP_USER"
echo "Email: $WP_EMAIL"
echo "Password: $WP_PASS"
```

## Cleanup

### Remove temporary users

```bash
# Delete by username
wp user delete temp_admin --yes

# Delete by email (find user first)
USER_ID=$(wp user list --field=ID,user_email | grep temp@example.com | awk -F, '{print $1}')
wp user delete "$USER_ID" --yes

# Delete all temporary users with matching prefix
wp user list --field=ID,user_login | grep temp_ | while IFS=, read -r id login; do
  wp user delete "$id" --yes
done
```

### Remove the PHP snippet if you used it

If you previously used the `admin-user-creation.php` snippet:

```bash
# Remove from functions.php
# Edit your theme's functions.php and delete the entire wpops_create_temporary_admin_user block

# Or if you added it as a separate file in wp-content/mu-plugins/
rm /srv/www/yoursite.com/current/web/wp-content/mu-plugins/admin-user-creation.php
```

## See Also

- [PHP Snippet Alternative](admin-user-creation.php) - For when WP-CLI is not available
- [WP-CLI User Management Docs](https://developer.wordpress.org/cli/commands/user/)
