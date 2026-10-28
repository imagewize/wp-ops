# Age Verification Script

Cookie-based age verification modal that shows or hides gated content blocks based on the visitor's declared age. How it works, the age rules, the ACF fields and its limits (it is a self-declared gate, not real verification):
[A Cookie-Based Age Gate for WordPress](https://wpvilla.in/wordpress-age-verification-modal-cookie-acf-jquery/).

## Files Included

- `age-verification.js` - Main JavaScript functionality
- `footer.php` - Complete HTML template with modal structure and ACF fields
- `modal.css` - Styling for the modal components

## Dependencies

- jQuery library
- Advanced Custom Fields (ACF) WordPress plugin
- A `d-none` rule (`display: none !important`) in the theme; content blocks use the `.code-block` class

## Installation

```php
wp_enqueue_style('age-verification-modal', get_template_directory_uri() . '/age-verification/modal.css');
wp_enqueue_script('age-verification', get_template_directory_uri() . '/age-verification/age-verification.js', ['jquery'], null, true);
```

Include `footer.php` in the theme footer, or copy its markup into your own template, and add `.code-block` to the blocks that should be gated.
