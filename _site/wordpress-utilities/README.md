# WordPress Utilities

A collection of reusable WordPress components, scripts, and tools for common functionality and diagnostics. These utilities are designed to be copied into WordPress themes or used as reference implementations.

## Overview

This directory contains self-contained utilities that can be integrated into any WordPress project. Each utility is documented with installation instructions, dependencies, and usage examples.

## Available Utilities

### [Age Verification](age-verification/)

Cookie-based age verification system with modal interface and ACF integration.

**Features:**
- Age-based content filtering (under 18, 18-23, over 24)
- Cookie persistence with configurable expiration
- Modal overlay interface
- Dynamic content toggling for restricted elements
- Advanced Custom Fields (ACF) integration for content management

**Use Cases:**
- Alcohol/cannabis industry websites
- Adult content restriction
- Age-gated promotions
- Casino/gambling advertisement control

**Key Files:**
- `age-verification.js` - Core functionality
- `modal.css` - Modal styling
- `footer.php` - Complete HTML template with ACF fields

### [Analytics](analytics/)

Implementation guides and detection methods for popular analytics platforms.

**Covered Platforms:**
- Google Analytics (GA4 and Universal Analytics)
- Google Site Kit plugin
- Google Tag Manager
- Matomo (self-hosted and cloud)

**Features:**
- Installation guides for plugin and manual implementations
- curl-based detection scripts
- Privacy compliance best practices
- Performance optimization recommendations
- Troubleshooting common issues

**Key Files:**
- `README.md` - Complete implementation and detection guide
- Bash scripts for analytics detection across multiple platforms

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
- `README.md` - Command-line testing tools and interpretation guide

## Installation

Each utility is self-contained and can be integrated independently:

1. Navigate to the specific utility directory
2. Review the README.md for requirements and dependencies
3. Copy the necessary files to your WordPress theme or plugin
4. Follow the installation and configuration instructions

### General Prerequisites

Most utilities may require one or more of:
- WordPress 5.0+
- jQuery (for JavaScript utilities)
- Advanced Custom Fields (ACF) plugin (for age-verification)
- WP-CLI (for command-line utilities)
- PHP 7.4+ or 8.0+

## Usage Patterns

### Development Workflow

1. **Test locally first**: Always test utilities in a development environment
2. **Review dependencies**: Check README files for required plugins and libraries
3. **Customize as needed**: Utilities are templates - adapt to your specific requirements
4. **Version control**: Track customizations separately from source utilities

### Integration Examples

**Age Verification in theme's functions.php:**
```php
// Enqueue age verification assets
function enqueue_age_verification() {
    wp_enqueue_style(
        'age-verification-modal',
        get_template_directory_uri() . '/age-verification/modal.css'
    );

    wp_enqueue_script(
        'age-verification',
        get_template_directory_uri() . '/age-verification/age-verification.js',
        array('jquery'),
        '1.0',
        true
    );
}
add_action('wp_enqueue_scripts', 'enqueue_age_verification');
```

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

## Best Practices

### Security

- **Never commit sensitive data**: API keys, tracking IDs should be in environment variables
- **Validate user input**: Especially for utilities that accept user data
- **Keep dependencies updated**: Regularly update jQuery, ACF, and other dependencies
- **Use HTTPS**: All external script references should use secure protocols

### Performance

- **Minimize JavaScript**: Only load scripts on pages where needed
- **Use conditional loading**: Check for required conditions before enqueuing assets
- **Optimize images**: WebP/AVIF formats for modal graphics
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
├── main-script.js      # Core functionality (if applicable)
├── styles.css          # Component styles (if applicable)
├── template.php        # WordPress template integration (if applicable)
└── examples/           # Usage examples (optional)
```

### Coding Standards

- **WordPress Coding Standards**: PHP code follows WordPress coding standards
- **ES5+ JavaScript**: Compatible with modern browsers and IE11+
- **Semantic HTML**: Accessible markup with proper ARIA attributes
- **BEM CSS**: Block Element Modifier naming convention where applicable

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

- **[wp-cli/](../wp-cli/)** - WordPress command-line operations
- **[nginx/](../nginx/)** - Web server configurations for performance
- **[scripts/](../scripts/)** - Automation and deployment scripts
- **[trellis/](../trellis/)** - Server provisioning and deployment

## License

These utilities are provided as-is for use in WordPress projects. Refer to individual utility directories for specific licensing information.

## Support

For issues or questions:
- Review the specific utility's README.md
- Check WordPress Codex and plugin documentation
- Consult related troubleshooting guides in [../troubleshooting/](../troubleshooting/)

---

*Part of the [wp-ops](../) repository - Tools and documentation for WordPress operations*
