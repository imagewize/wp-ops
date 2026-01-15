# WordPress Migration Guide

This guide documents various commands and techniques for migrating WordPress sites, particularly when using Roots Trellis and Bedrock stacks. These commands are especially useful when:

1. Migrating from local development to production environments
2. Setting up and fixing multisite installations
3. Converting regular WordPress image URLs to Bedrock-compatible paths
4. Migrating from traditional WordPress hosting to Trellis/Bedrock

## Chapter Purpose

This chapter lays out safe migration paths and the core commands needed to move sites between environments.

## Migration Scenarios

This directory contains guides for different migration scenarios:

### Single-Site Migration
- **[Regular WordPress to Trellis/Bedrock Migration](REGULAR-TO-TRELLIS.md)** - Complete step-by-step guide for migrating a single WordPress site from traditional hosting (shared hosting, Plesk, cPanel) to Trellis with Bedrock. Includes modern Trellis CLI workflow, `/etc/hosts` testing before DNS cutover, database migration, uploads transfer, and strategies for handling Bedrock path changes while maintaining compatibility with non-Sage themes.

### Multi-Site Migration
- **[Multi-Site Migration Guide](MULTI-SITE-MIGRATION.md)** - Strategies and best practices for migrating **multiple WordPress sites** to a single Trellis server. Covers time-saving tips, batch operations, parallel processing, managing multiple Bedrock installations, and common pitfalls to avoid when consolidating sites.

### Quick Reference
- **Current Document** - Commands and techniques for domain migrations and path conversions

## Domain Migration Commands

When moving a site between environments (e.g., from local to production), you need to update all URLs in the database:

### Basic Domain Migration

```bash
# Preview changes with --dry-run
wp search-replace 'http://example.test' 'https://example.com' --dry-run

# Apply the changes
wp search-replace 'http://example.test' 'https://example.com'

# Replace domain without protocol (for places where only the domain is stored)
wp search-replace 'example.test' 'example.com'
```

### Multisite Domain Migration

For WordPress multisite installations, use these flags for more precise control:

```bash
# Update URLs for a specific site in a multisite network
wp search-replace 'http://subsite.example.test' 'https://subsite.example.com' --all-tables --url=subsite.example.test

# Update across the entire network
wp search-replace 'http://subsite.example.test' 'https://subsite.example.com' --all-tables --network --url=subsite.example.test
```

## Bedrock Path Conversion

When migrating from a standard WordPress installation to a Bedrock-based installation, you'll need to update file paths in your database:

### Theme Path Migration

```bash
# Convert theme paths from standard WordPress to Bedrock structure
wp search-replace '/wp-content/themes/' '/app/themes/' --all-tables --url=example.com

# If you need to target a specific theme
wp search-replace '/wp-content/themes/specific-theme' '/app/themes/specific-theme' --all-tables --url=example.com
```

### Upload Path Migration

```bash
# Preview upload path changes
wp search-replace 'https://example.com/wp-content/uploads/' 'https://example.com/app/uploads/' --all-tables --precise --report-changed-only --dry-run

# Apply upload path changes
wp search-replace 'https://example.com/wp-content/uploads/' 'https://example.com/app/uploads/' --all-tables --precise --report-changed-only
```

## Command Options Explained

- `--dry-run`: Preview changes without modifying the database
- `--all-tables`: Search through all tables in the database, not just WordPress core tables
- `--network`: Apply changes across all sites in a multisite installation
- `--url=example.com`: Specify which site in a multisite installation to operate on
- `--precise`: Perform a slower but more thorough search, useful for encoded data
- `--report-changed-only`: Only show tables where changes were made (reduces output noise)

## Best Practices

1. **Always backup your database** before running search-replace operations
2. Always test with `--dry-run` first to preview changes
3. For multisite installations, run commands for each subsite individually
4. After migration, flush caches and permalinks with:
   ```bash
   wp cache flush
   wp rewrite flush
   ```
5. Test the site thoroughly after migration, especially forms and dynamic content

## Common Migration Workflow

1. Migrate the database from source to destination environment
2. Run appropriate domain search-replace commands
3. Update path structures if moving between different WordPress setups
4. Flush caches and permalinks
5. Test site functionality

## Troubleshooting

If you encounter issues after migration:

1. Check for hardcoded URLs in theme files and plugins
2. Look for serialized data issues (the `--precise` flag helps with this)
3. Inspect browser console for missing assets or 404 errors
4. Verify that all database tables were included in the search-replace operations
