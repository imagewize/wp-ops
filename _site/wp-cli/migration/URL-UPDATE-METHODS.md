# Updating WordPress Site and Home URLs After Migration

When migrating a WordPress site to a new domain or URL, you need to update the site and home URLs in multiple places. Here are the most common and effective methods.

## Method 1: Using WP-CLI (Recommended)

WP-CLI is the fastest and most reliable method for updating URLs:

```bash
# Update both home and site URL
wp option update home 'https://newdomain.com'
wp option update siteurl 'https://newdomain.com'

# Search and replace old URLs in content
wp search-replace 'https://olddomain.com' 'https://newdomain.com'

# Include uploads if you have hardcoded URLs in content
wp search-replace 'https://olddomain.com/wp-content/uploads' 'https://newdomain.com/wp-content/uploads'

# Flush rewrite rules
wp rewrite flush
```

## Method 2: Using wp-config.php (Temporary Fix)

Add these constants to your `wp-config.php` file **before** the `/* That's all, stop editing! */` line:

```php
// Force WordPress to use these URLs
define('WP_HOME', 'https://newdomain.com');
define('WP_SITEURL', 'https://newdomain.com');
```

**Note:** This is a temporary solution. Remove these lines once you've updated the database permanently.

## Method 3: Direct Database Update

**⚠️ Always backup your database before making direct changes!**

### Update options table:

```sql
UPDATE wp_options 
SET option_value = 'https://newdomain.com' 
WHERE option_name = 'home';

UPDATE wp_options 
SET option_value = 'https://newdomain.com' 
WHERE option_name = 'siteurl';
```

### Update content URLs (if needed):

```sql
-- Update post content
UPDATE wp_posts 
SET post_content = REPLACE(post_content, 'https://olddomain.com', 'https://newdomain.com');

-- Update meta values
UPDATE wp_postmeta 
SET meta_value = REPLACE(meta_value, 'https://olddomain.com', 'https://newdomain.com');

-- Update comments
UPDATE wp_comments 
SET comment_content = REPLACE(comment_content, 'https://olddomain.com', 'https://newdomain.com');
```

## Method 4: Using WordPress Admin Panel

If you can access the admin panel:

1. Go to **Settings > General**
2. Update **WordPress Address (URL)** and **Site Address (URL)**
3. Save changes

## Method 5: Using functions.php (Temporary)

Add to your theme's `functions.php`:

```php
// Temporary URL override
update_option('siteurl', 'https://newdomain.com');
update_option('home', 'https://newdomain.com');
```

**Remove this code after the URLs are updated!**

## Post-Migration Checklist

After updating URLs, verify these items:

- [ ] WordPress admin is accessible
- [ ] Frontend loads correctly
- [ ] Images and media files display properly
- [ ] Internal links work correctly
- [ ] SSL certificate is properly configured
- [ ] Redirect old domain to new domain (if applicable)
- [ ] Update any hardcoded URLs in theme files
- [ ] Check and update any plugins with domain-specific settings
- [ ] Update CDN settings if applicable
- [ ] Test contact forms and other functionality

## Troubleshooting

### Can't Access Admin Panel
If you can't access the admin after URL change:

1. Use wp-config.php method first
2. Then use WP-CLI or database method to make permanent changes
3. Remove wp-config.php constants

### Mixed Content Issues
If you're moving from HTTP to HTTPS:

```bash
# Use WP-CLI to replace HTTP with HTTPS
wp search-replace 'http://yourdomain.com' 'https://yourdomain.com'
```

### Multisite Networks
For WordPress multisite:

```bash
# Update main site
wp option update home 'https://newdomain.com' --url=olddomain.com
wp option update siteurl 'https://newdomain.com' --url=olddomain.com

# Update each subsite
wp search-replace 'olddomain.com' 'newdomain.com' --network
```

## Best Practices

1. **Always backup** your database before making changes
2. Use **WP-CLI** when possible - it's the safest method
3. **Test thoroughly** after making changes
4. Keep wp-config.php constants as **temporary solutions only**
5. Update your **DNS records** and **SSL certificates** accordingly
6. Set up **301 redirects** from old domain to new domain if applicable

## Additional Resources

- [WP-CLI Official Documentation](https://wp-cli.org/)
- [WordPress Codex: Changing The Site URL](https://wordpress.org/support/article/changing-the-site-url/)
- [WordPress Migration Guide](https://wordpress.org/support/article/moving-wordpress/)