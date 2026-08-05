# Age Verification Script

A JavaScript-based age verification system for WordPress websites that manages content visibility based on user age and preferences.

## Features

- **Age-based content filtering**: Restricts access to specific content blocks based on user age
- **Cookie-based persistence**: Remembers user preferences across sessions
- **Modal interface**: Clean, overlay-based age verification form
- **Content toggling**: Dynamically shows/hides casino highlight blocks based on verification status
- **Checkbox preference**: Allows users over 24 to opt-in/out of seeing advertisements

## How It Works

### Age Categories
- **Under 18**: Users cannot see casino/advertisement content
- **18-23**: Users cannot see casino/advertisement content  
- **Over 24**: Users can choose whether to see casino/advertisement content via checkbox

### Cookie Management
- Sets `canSeeAds` cookie with appropriate value based on age selection
- Cookie expires after 1 day for under-24 users, 365 days for over-24 users
- Automatically checks existing cookie on page load to maintain user preferences

### Content Control
The script targets elements with the `.code-block` class to show/hide casino-related content:
- Adds `d-none` class to hide content
- Removes `d-none` class to show content

### Modal Behavior
- Shows modal overlay on first visit (no existing cookie)
- Hides modal after age verification
- Prevents body scrolling while modal is active via `overflow-hidden` class

## Required HTML Elements

The script expects specific HTML elements to be present. A complete modal template is provided in `footer.php` which includes:

- Modal container (`.modal-verification` with `#modal_verification` ID)
- Overlay background (`.modal-overlayer`) 
- Age selection buttons (`#under-18`, `#18-23`, `#over-24`)
- Advertisement preference checkbox (`#age_verify`)
- Content blocks with `.code-block` class for controlled visibility

**Advanced Custom Fields (ACF) Integration:**
The modal template uses ACF fields for dynamic content management:
- `avs_header_logo` - Modal header logo
- `avs_heading` - Main heading text
- `avs_subheading` - Subheading text  
- `avs_description` - Description text
- `avs_button_1`, `avs_button_2`, `avs_button_3` - Age selection button labels
- `avs_verification_check_text` - Checkbox label text
- `avs_confirmation_text` - Bottom confirmation text

**To use the provided template:**
1. Install and configure Advanced Custom Fields (ACF) plugin
2. Set up the required ACF option fields
3. Include `footer.php` in your WordPress theme
4. Or copy the modal HTML structure to your existing template files

## CSS Classes Used

- `.modal-visible`: Shows the verification modal
- `.visible`: Shows the overlay background
- `.overflow-hidden`: Prevents body scrolling
- `.d-none`: Hides content blocks
- `.code-block`: Target elements for content control

## Installation

1. Install and configure the Advanced Custom Fields (ACF) WordPress plugin
2. Set up the required ACF option fields (see ACF Integration section above)
3. Include jQuery (script dependency)
4. Add the `age-verification.js` script to your WordPress theme
5. Include the `modal.css` stylesheet in your theme (or copy styles to your main stylesheet)
6. Include the `footer.php` template in your WordPress theme or copy its HTML structure to your existing templates
7. Ensure content blocks use the `.code-block` class for age-based visibility control

**To enqueue the CSS file in WordPress:**
Add this to your theme's `functions.php`:
```php
wp_enqueue_style('age-verification-modal', get_template_directory_uri() . '/age-verification/modal.css');
```

## Files Included

- `age-verification.js` - Main JavaScript functionality
- `footer.php` - Complete HTML template with modal structure
- `modal.css` - Professional styling for the modal components
- `README.md` - Documentation

## Dependencies

- jQuery library
- Advanced Custom Fields (ACF) WordPress plugin
- CSS classes for modal visibility and content hiding