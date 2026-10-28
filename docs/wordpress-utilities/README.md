# WordPress Utilities

A collection of reusable WordPress components, scripts, and tools for common functionality and diagnostics. These utilities are designed to be copied into WordPress themes or used as reference implementations.

## Overview

This directory contains self-contained utilities that can be integrated into any WordPress project. Each utility is documented with installation instructions, dependencies, and usage examples.

## Available Utilities

### Analytics

Implementation notes and curl-based detection for Site Kit, Google Analytics, Tag Manager and Matomo now live on the blog: [Which Analytics Is This WordPress Site Running?](https://wpvilla.in/detect-wordpress-analytics-curl-site-kit-gtm-matomo/).

### [Snippets](snippets/)

WP-CLI guides for Trellis and Bedrock sites.

**Available:**
- `admin-user-creation-wpcli.md` — WP-CLI commands for safe admin user creation
- `wp-template-db-override-wpcli.md` — Fix block theme templates frozen by a Site Editor database override

The non-Trellis snippets (WooCommerce attributes, post-expiry noindex, WebP featured images, the age gate) are on the blog; the [snippets README](snippets/README.md) links them.

### [Speed Optimization](speed-optimization/)

Performance testing tools and TTFB (Time To First Byte) analysis utilities.

**Features:**
- curl-based TTFB measurement
- wget timing diagnostics
- Google web.dev performance guidelines (≤ 0.8s target)
- Response header analysis
- Server cache validation (LiteSpeed, etc.)

**Performance Targets:**
- Good: TTFB ≤ 0.8 seconds
- Needs Improvement: 0.8 - 1.8 seconds
- Poor: > 1.8 seconds

**Key Files:**
- `README.md` - The bundled TTFB scripts, with a link to the full measuring guide

## Installation

Each utility is self-contained and can be integrated independently:

1. Navigate to the specific utility directory
2. Review the README.md for requirements and dependencies
3. Copy the necessary files to your WordPress theme or plugin
4. Follow the installation and configuration instructions

### General Prerequisites

Most utilities may require one or more of:
- WordPress 5.0+
- WP-CLI (for command-line utilities)
- PHP 7.4+ or 8.0+

## Usage Patterns

### Development Workflow

1. **Test locally first**: Always test utilities in a development environment
2. **Review dependencies**: Check README files for required plugins and libraries
3. **Customize as needed**: Utilities are templates - adapt to your specific requirements
4. **Version control**: Track customizations separately from source utilities

### Integration Examples

**Speed Testing in deployment scripts:**
```bash
#!/bin/bash
# Post-deployment performance check
DOMAIN="example.com"
TTFB=$(curl -w "%{time_starttransfer}" -o /dev/null -s https://$DOMAIN)

if (( $(echo "$TTFB > 0.8" | bc -l) )); then
    echo "WARNING: TTFB is ${TTFB}s (target: ≤0.8s)"
fi
```

**Analytics Detection in site audits:**
```bash
# Quick check for analytics implementation
curl -sL https://example.com | grep -E 'googlesitekit|matomo|gtag'
```
See [the detection post](https://wpvilla.in/detect-wordpress-analytics-curl-site-kit-gtm-matomo/) for the full set of checks.

## Best Practices

### Security

- **Never commit sensitive data**: API keys, tracking IDs should be in environment variables
- **Validate user input**: Especially for utilities that accept user data
- **Keep dependencies updated**: Regularly update plugins and other dependencies
- **Use HTTPS**: All external script references should use secure protocols

### Performance

- **Minimize JavaScript**: Only load scripts on pages where needed
- **Use conditional loading**: Check for required conditions before enqueuing assets
- **Cache static assets**: Leverage browser caching for CSS/JS files

### Maintenance

- **Document customizations**: Track changes made to base utilities
- **Test after WordPress updates**: Verify compatibility with major WordPress releases
- **Monitor deprecations**: Watch for deprecated functions in utilities
- **Regular audits**: Periodically review utility usage and necessity

## Architecture

### File Organization

Each utility follows this structure:
```
utility-name/
├── README.md           # Complete documentation
└── examples/           # Usage examples (optional)
```

## Contributing

When adding new utilities:

1. Create a dedicated directory with descriptive name
2. Include comprehensive README.md with:
   - Feature overview
   - Installation instructions
   - Dependencies and requirements
   - Usage examples
   - Troubleshooting guide
3. Follow existing code patterns
4. Test with current WordPress version
5. Update this main README.md

## Related Tools

These utilities complement other tools in the wp-ops repository:

- **[wp-cli/](../../wp-cli/)** - WordPress command-line operations
- **[nginx/](../nginx/)** - Web server configurations for performance
- **[scripts/](../../scripts/)** - Automation and deployment scripts
- **[trellis/](../../trellis/)** - Server provisioning and deployment

## License

These utilities are provided as-is for use in WordPress projects. Refer to individual utility directories for specific licensing information.

## Support

For issues or questions:
- Review the specific utility's README.md
- Check WordPress Codex and plugin documentation
- Consult related troubleshooting guides in [../troubleshooting/](../troubleshooting/)

---

*Part of the [wp-ops](../) repository - Tools and documentation for WordPress operations*
