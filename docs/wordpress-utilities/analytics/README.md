# WordPress Analytics Tools Guide

This guide covers the implementation and detection of popular analytics tools on WordPress sites, including Google Analytics and Matomo.

## Overview

Analytics tools help track website performance, user behavior, and conversion metrics. The most common solutions for WordPress are:

- **Google Analytics** (via Google Site Kit plugin or manual implementation)
- **Matomo** (via official Matomo plugin or manual implementation)

## Google Analytics Implementation

### Method 1: Google Site Kit Plugin

The recommended approach for Google Analytics on WordPress is using the official Google Site Kit plugin.

**Installation:**
1. Install the "Site Kit by Google" plugin from WordPress repository
2. Activate and connect to your Google account
3. Configure Google Analytics through the Site Kit dashboard

**Features:**
- Automatic tracking code implementation
- Dashboard integration within WordPress admin
- Multiple Google services integration (Analytics, Search Console, AdSense, etc.)
- Automatic updates and maintenance

### Method 2: Manual Implementation

For advanced users who need custom tracking configurations:

1. Create a Google Analytics account and property
2. Get your Measurement ID (GA4) or Tracking ID (Universal Analytics)
3. Add tracking code to your theme's header or use a plugin like "Insert Headers and Footers"

## Matomo Implementation

### Method 1: Matomo Plugin

The official Matomo plugin provides easy integration:

**Installation:**
1. Install "Matomo Analytics - Ethical Stats" plugin
2. Choose between Matomo Cloud or self-hosted installation
3. Configure tracking settings in the plugin dashboard

**Features:**
- Privacy-focused analytics (GDPR compliant by default)
- Self-hosted option for complete data ownership
- Real-time analytics
- No data sampling
- Integrated heatmaps and session recordings

### Method 2: Manual Implementation

For self-hosted Matomo installations:

1. Set up Matomo on your server
2. Get your site ID and tracking code
3. Add the JavaScript tracking code to your theme

## Detection Methods

You can check if analytics tools are properly implemented on any WordPress site using curl commands.

### Detecting Google Site Kit

Check for Site Kit meta tags and configuration:

```bash
# Check for Site Kit meta tags and setup
curl -sL https://example.com | grep -E 'googlesitekit|gtagconfig'

# Expected output example:
# <meta name="googlesitekit-setup" content="abc123-def4-567g-8hij-klmnopqrstuv" />
# <meta name="generator" content="Site Kit by Google 1.150.0" />
```

### Detecting Google Analytics

Check for Google Analytics tracking code implementation:

```bash
# Check for Google Analytics tracking code
curl -sL https://example.com | grep -E 'gtag\(|googletagmanager|analytics\.js|GA_MEASUREMENT_ID'

# Check for DNS prefetch (performance optimization)
curl -sL https://example.com | grep -E 'dns-prefetch.*googletagmanager'

# Expected output example:
# <link rel='dns-prefetch' href='//www.googletagmanager.com' />
```

### Detecting Google Tag Manager

Check specifically for Google Tag Manager implementation:

```bash
# Check for GTM container
curl -sL https://example.com | grep -E 'googletagmanager\.com/gtm\.js\?id=GTM-'

# Expected output example:
# <script src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX"></script>
```

### Detecting Matomo

Check for Matomo tracking implementation:

```bash
# Check for Matomo tracking code (self-hosted)
curl -sL https://example.com | grep -E 'matomo\.js|piwik\.js|_paq\.push'

# Check for Matomo Cloud
curl -sL https://example.com | grep -E 'cdn\.matomo\.cloud'

# Check for Matomo tracking pixel
curl -sL https://example.com | grep -E 'matomo\.php\?|piwik\.php\?'

# Expected output examples:
# <script src="https://analytics.example.com/matomo.js"></script>
# var _paq = window._paq = window._paq || [];
# <script src="https://cdn.matomo.cloud/example.matomo.cloud/matomo.js"></script>
```

## Complete Site Analysis Script

Here's a comprehensive bash script to check for all analytics implementations:

```bash
#!/bin/bash

DOMAIN="example.com"

echo "=== Analytics Detection for $DOMAIN ==="
echo

echo "1. Checking for Google Site Kit..."
curl -sL https://$DOMAIN | grep -E 'googlesitekit|Site Kit by Google' | head -3
echo

echo "2. Checking for Google Analytics..."
curl -sL https://$DOMAIN | grep -E 'gtag\(|googletagmanager|GA_MEASUREMENT_ID' | head -3
echo

echo "3. Checking for Google Tag Manager..."
curl -sL https://$DOMAIN | grep -E 'googletagmanager\.com/gtm\.js\?id=GTM-' | head -3
echo

echo "4. Checking for Matomo..."
curl -sL https://$DOMAIN | grep -E 'matomo\.js|piwik\.js|_paq\.push|cdn\.matomo\.cloud' | head -3
echo

echo "5. Checking for other analytics..."
curl -sL https://$DOMAIN | grep -E 'facebook\.net/.*fbevents|hotjar\.com|segment\.com' | head -3
```

## Best Practices

### Privacy Compliance
- Always implement cookie consent mechanisms
- Consider privacy-focused alternatives like Matomo
- Anonymize IP addresses where required
- Provide clear privacy policies

### Performance Optimization
- Use DNS prefetching for external analytics scripts
- Implement analytics tracking asynchronously
- Consider server-side tracking for critical metrics

### WordPress Specific
- Use plugins for easier management and updates
- Test analytics implementation in staging environments
- Monitor for plugin conflicts
- Regular audits of tracking accuracy

## Troubleshooting

### Common Issues
1. **Tracking code not firing**: Check for JavaScript errors and plugin conflicts
2. **Duplicate tracking**: Ensure only one implementation method is active
3. **Missing data**: Verify tracking ID/Measurement ID configuration
4. **Plugin conflicts**: Disable other analytics plugins when testing

### Debugging Tools
- Google Analytics Debugger (Chrome extension)
- Google Tag Assistant
- Browser developer tools (Network tab)
- WordPress debug logs

## Recommended Plugins

### Google Analytics
- **Site Kit by Google** (Official Google plugin)
- **MonsterInsights** (Popular third-party option)
- **GA Google Analytics** (Lightweight option)

### Matomo
- **Matomo Analytics** (Official Matomo plugin)
- **WP-Matomo** (Alternative implementation)

## Security Considerations

- Keep analytics plugins updated
- Use HTTPS for all tracking requests
- Implement Content Security Policy headers
- Regular security audits of third-party scripts
- Consider self-hosted solutions for sensitive data

---

*Last updated: [Current Date]*
*For more WordPress tools and utilities, check the other directories in this repository.*
