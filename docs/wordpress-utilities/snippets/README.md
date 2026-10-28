# WordPress Snippets

WP-CLI guides for Trellis and Bedrock sites.

## Available Snippets

### [admin-user-creation-wpcli.md](admin-user-creation-wpcli.md)

**Recommended approach** for creating WordPress administrator users safely from the command line.

**Features:**
- No code to add/remove from WordPress files
- Credentials aren't stored in files
- Full control via command line
- Secure random password generation examples
- Batch user creation from CSV files
- Emergency lockout recovery workflow

**Quick Start:**
```bash
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(openssl rand -base64 16)"
```

### [wp-template-db-override-wpcli.md](wp-template-db-override-wpcli.md)

Fix block theme templates that appear frozen — changes to PHP pattern files or `.html` template files are silently ignored because the Site Editor saved a DB override (`wp_template` post type) that takes precedence over the file on disk.

**Features:**
- Detect DB overrides by listing `wp_template` posts
- Option A: delete the DB copy to restore file-system control
- Option B: surgically update specific block markup in the DB copy using `wp eval` + `str_replace`
- Trellis VM variants for all commands
- Prevention guidance (`WP_DEVELOPMENT_MODE=theme`)

**Quick Start:**
```bash
# Find the frozen template post
wp post list --post_type=wp_template --fields=ID,post_name,post_status --path=web/wp --url=https://example.com/

# Delete it (restores file-system template)
wp post delete <ID> --force --path=web/wp --url=https://example.com/
```
