# WordPress Block Pattern Requirements & Best Practices

**Version:** 1.2
**Last Updated:** December 15, 2025
**Analysis Based On:** 43 Elayne patterns + 98 Ollie patterns (141 total) + Official WordPress documentation

This document provides a comprehensive checklist and guidelines for creating WordPress block patterns that follow modern best practices and avoid common validation errors.

**Based on official WordPress documentation:**
- [Block Patterns - Starter Patterns](https://developer.wordpress.org/themes/patterns/starter-patterns/)
- [Block Patterns - Using PHP in Patterns](https://developer.wordpress.org/themes/patterns/using-php-in-patterns/)
- [Block Editor - Metadata in block.json](https://developer.wordpress.org/block-editor/reference-guides/block-api/block-metadata/)

---

## Table of Contents

1. [Pattern Header Requirements](#1-pattern-header-requirements)
2. [Metadata Attribute (Recommended)](#2-metadata-attribute-recommended)
3. [Structural Patterns](#3-structural-patterns)
4. [Spacing and Styling](#4-spacing-and-styling)
5. [Image Handling](#5-image-handling)
6. [Typography](#6-typography)
7. [Pattern Categories](#7-pattern-categories)
8. [Pattern-Specific Requirements](#8-pattern-specific-requirements)
9. [Accessibility](#9-accessibility-and-semantics)
10. [Using PHP in Patterns](#10-using-php-in-patterns)
11. [Internationalization](#11-internationalization-i18n)
12. [Common Mistakes to Avoid](#12-common-mistakes-to-avoid)
13. [Quick Checklist](#13-quick-reference-checklist)

---

## 1. Pattern Header Requirements

### PHP Pattern File Structure

**IMPORTANT:** Elayne uses PHP-based patterns. Pattern files are PHP documents placed in the `patterns/` directory. Each file begins with a documentation block containing metadata headers.

According to [WordPress documentation](https://developer.wordpress.org/themes/patterns/using-php-in-patterns/), pattern registration happens on the `init` hook. At this point, WordPress compiles the content of the pattern and saves a copy of it as HTML-based block markup.

### Required Fields (All Patterns)

Every pattern file must begin with a PHP comment block containing:

```php
<?php
/**
 * Title: Pattern Display Name
 * Slug: elayne/pattern-slug
 * Description: Brief description of what the pattern does
 * Categories: elayne/category1, elayne/category2
 */
?>
```

**Field Descriptions:**

- **Title:** Human-readable name shown in editor (e.g., "Modern Hero - Light")
- **Slug:** Theme-prefixed identifier using kebab-case (e.g., `elayne/hero-modern-light`)
  - Format: `namespace/pattern-name` where namespace is your theme or plugin name
  - Must be unique across all patterns
- **Description:** Brief explanation of pattern purpose and content
- **Categories:** Comma-separated list of registered pattern categories

### Optional Fields

```php
/**
 * Keywords: keyword1, keyword2, keyword3
 * Viewport Width: 1500
 * Block Types: core/post-content
 * Post Types: page, post
 * Template Types: front-page, home, page
 * Inserter: yes
 */
```

**Field Descriptions:**

- **Keywords:** Search terms for pattern discovery in inserter
- **Viewport Width:** Preview width in pixels (600, 800, 1200, 1500, 1920)
- **Block Types:** Specific block types the pattern targets (e.g., `core/post-content` for page patterns)
- **Post Types:** Associates pattern with specific post types (comma-separated)
  - Use `page` for page patterns that appear when creating new pages
  - Use `wp_template` for template patterns
- **Template Types:** Links patterns to specific template types
  - Supported: `index`, `home`, `front-page`, `singular`, `single`, `page`, `archive`, `author`, `category`, `taxonomy`, `date`, `tag`, `attachment`, `search`, `privacy-policy`, `404`
  - Often combined with `Inserter: no` to hide from block inserter
- **Inserter:** Boolean to show/hide in inserter (defaults to `yes`)
  - Set to `no` or `false` to disable pattern from appearing in inserter

### Pattern Types

**Page Patterns** require:
- `Block Types: core/post-content` designation
- `Post Types: page` (or custom post types supporting block editor)
- Function as starting points when creating new pages
- Display in a modal selection interface on Pages > Add New

**Template Patterns** require:
- `Template Types` field listing supported templates
- Typically include global elements (headers, footers, sidebars)
- Often disabled from block inserter via `Inserter: no`
- Present selection modal when creating new templates in Site Editor

### PHP Pattern Limitations

**CRITICAL:** Because pattern registration happens on the `init` hook, patterns cannot access post-specific functions:

❌ **Cannot use:**
- `is_page()` - The WordPress global query isn't available
- `get_post()` - Post-specific data not accessible
- `the_title()` - No post context during registration
- Any function dependent on the global query object

✅ **Can use:**
- Standard PHP functions (`foreach`, `array_map`, etc.)
- WordPress helper functions (`esc_html()`, `esc_url()`, `get_theme_file_uri()`, etc.)
- Translation functions (`__()`, `esc_html_e()`, etc.)
- Theme and plugin functions not dependent on global query

---

## 2. Metadata Attribute (Recommended)

### Recommendation & Context

Including a `metadata` attribute on the outermost block is **strongly recommended** for discoverability and portability (copy/paste) even though it is not a strict validation requirement.

According to [WordPress Gutenberg GitHub Issue #71687](https://github.com/wordpress/gutenberg/issues/71687), when inserting any pattern from the main inserter sidebar, WordPress automatically sets metadata attributes on the inserted block, including `categories`, `patternName`, and `name`.

```json
{
  "metadata": {
    "name": "Pattern Display Name",
    "categories": ["elayne/category1", "elayne/category2"],
    "patternName": "elayne/pattern-slug"
  }
}
```

### Metadata Attribute Components

**`name`** (string):
- Human-readable label for pattern display in user interfaces
- Must match the `Title:` field in pattern header
- Example: `"Modern Hero - Light"`

**`categories`** (array):
- Array of pattern classification slugs (NOT numeric IDs)
- Must match the `Categories:` field in pattern header
- Must use registered category slugs from `functions.php`
- Example: `["banner", "featured"]` or `["elayne/hero", "featured"]`

**`patternName`** (string):
- Namespaced identifier combining namespace and pattern identifier
- Must match the `Slug:` field in pattern header exactly
- Format: `namespace/pattern-name`
- Example: `"elayne/hero-modern-light"`

### Example Usage

```html
<!-- wp:group {
  "metadata": {
    "name": "Modern Hero - Light",
    "categories": ["banner", "featured"],
    "patternName": "elayne/hero-modern-light"
  },
  "align": "full",
  "backgroundColor": "base",
  ...
} -->
<div class="wp-block-group alignfull has-base-background-color has-background">
  <!-- Pattern content -->
</div>
<!-- /wp:group -->
```

### Why to Include It

**Pattern Discovery:** WordPress uses metadata for categorization and search
- The metadata enables WordPress to classify and organize patterns for discovery and filtering
- Users can filter patterns by category in the block inserter

**Editor UI:** Ensures pattern appears correctly in the patterns inserter
- Pattern identity is maintained when inserted into content
- Supports WordPress features like "contentOnly patterns" which require consistent metadata

**Copy/Paste Portability:** Keeps pattern identity intact when moving markup between sites
- When copying pattern HTML into another site, metadata preserves categories and the pattern name so it appears in the inserter as expected
- WordPress often injects metadata when inserting patterns; keeping it in the saved markup prevents identity loss if the content is reused elsewhere

**Validation Note:** Metadata is not required for block validity
- Missing metadata alone typically does **not** trigger block validation errors
- If metadata is present, ensure its values match the header fields to avoid inconsistent labeling

**Consistency:** Metadata fields must match header fields exactly
- `name` must match `Title:` header field
- `patternName` must match `Slug:` header field
- `categories` array must match `Categories:` header field (converted from comma-separated to array)

### Common Issues

- ❌ **Metadata attribute missing entirely** - Does not usually break validation but reduces discoverability and portability
- ❌ **Category names don't match registered categories** in `functions.php`
  - Example: Using `"hero"` when only `"elayne/hero"` is registered
- ❌ **`patternName` doesn't match the `Slug:` header field**
  - Must be exact match: `"elayne/hero-modern-light"` (not `"hero-modern-light"`)
- ❌ **`name` doesn't match the `Title:` header field**
  - Must be exact match: `"Modern Hero - Light"` (not `"Hero Modern Light"`)
- ❌ **Using category IDs instead of slugs** in categories array
  - Correct: `["banner", "featured"]` (slugs)
  - Wrong: `[1, 2]` (numeric IDs)

### Metadata vs Block.json

**Note:** The `metadata` attribute in patterns is different from the `block.json` metadata file used for custom block registration.

- **Pattern metadata attribute:** JSON object within block markup for pattern identification
- **Block.json metadata:** Separate file for registering custom block types with WordPress
- Both serve different purposes and should not be confused

---

## 3. Structural Patterns

### 3.1 Full-Width Sections (align="full")

**Usage:** Background sections that span viewport edge-to-edge
**Frequency:** 77% of Elayne patterns (33/43)

#### Critical Structure

```html
<!-- OUTER GROUP: ALWAYS use layout type="default" -->
<!-- wp:group {
  "align": "full",
  "layout": {"type": "default"},
  "backgroundColor": "primary",
  "style": {
    "spacing": {
      "margin": {"top": "0", "bottom": "0"},
      "padding": {
        "top": "var:preset|spacing|x-large",
        "bottom": "var:preset|spacing|x-large"
      }
    }
  }
} -->
<div class="wp-block-group alignfull has-primary-background-color has-background">

  <!-- INNER GROUP: Use constrained layout for content width -->
  <!-- wp:group {
    "layout": {"type": "constrained", "contentSize": "800px"}
  } -->
  <div class="wp-block-group">
    <!-- Centered content here -->
  </div>
  <!-- /wp:group -->

</div>
<!-- /wp:group -->
```

#### Key Requirements

1. **Outer `alignfull` group MUST use `"layout":{"type":"default"}`**
   - Never use `"type":"constrained"` on outer alignfull group
   - Prevents horizontal gaps and overflow issues

2. **Margin reset required:** `"margin":{"top":"0","bottom":"0"}`
   - WordPress adds automatic margin between blocks
   - Without reset, gaps appear between adjacent background patterns

3. **Inner groups use constrained layout**
   - `"layout":{"type":"constrained","contentSize":"800px"}` (or 900px, 1200px)
   - Centers and limits content width within full-width container

4. **Padding for breathing room**
   - Typically: `"padding":{"top":"var:preset|spacing|x-large","bottom":"var:preset|spacing|x-large"}`

### 3.2 Grid Layouts (Responsive Multi-Column)

**Usage:** Feature grids, pricing tables, team grids, client reviews
**DO NOT use `wp:columns` for responsive layouts**

#### Critical Structure

```html
<!-- Use grid with minimumColumnWidth for true responsiveness -->
<!-- wp:group {
  "align": "wide",
  "layout": {
    "type": "grid",
    "minimumColumnWidth": "20rem"
  }
} -->
<div class="wp-block-group alignwide">
  <!-- Direct children become grid items and wrap responsively -->

  <!-- wp:group --> Card 1 <!-- /wp:group -->
  <!-- wp:group --> Card 2 <!-- /wp:group -->
  <!-- wp:group --> Card 3 <!-- /wp:group -->

</div>
<!-- /wp:group -->
```

#### Why Not `wp:columns`?

- **Problem:** Columns force exact layout at all breakpoints
- **Tablet issue:** Goes 3 columns → 3 columns (cramped) → 1 column
- **Grid solution:** Goes 3 columns → 2 columns → 1 column based on available space

#### Responsive Behavior

With `minimumColumnWidth="20rem"`:

- **Desktop** (>60rem): 3 columns
- **Tablet** (40-60rem): 2 columns
- **Mobile** (<40rem): 1 column

### 3.3 Constrained Inner Groups

**Usage:** Nested inside full-width or wide groups to limit content width

**Common `contentSize` values:**
- `"800px"` - Narrow content (text-heavy sections)
- `"900px"` - Medium content
- `"1200px"` - Wide content (images, features)

**Example:**

```html
<!-- wp:group {
  "layout": {"type": "constrained", "contentSize": "900px"}
} -->
<div class="wp-block-group">
  <!-- Centered, max-width content -->
</div>
<!-- /wp:group -->
```

---

## 4. Spacing and Styling

### 4.1 Theme Variable Usage (Universal Requirement)

**100% compliance across all 141 analyzed patterns**

All spacing and colors MUST use theme.json variables, never hardcoded values.

#### Spacing Variable Format

```html
<!-- In block attributes: -->
"style": {
  "spacing": {
    "padding": {"top": "var:preset|spacing|large"}
  }
}

<!-- In inline styles (WordPress converts automatically): -->
style="padding-top:var(--wp--preset--spacing--large)"
```

#### Common Spacing Sizes

All use responsive `clamp()` for fluid scaling:

- `small` → ~0.5rem to 1rem
- `medium` → ~1.5rem to 2rem
- `large` → ~2rem to 3rem
- `x-large` → ~3rem to 5rem
- `xx-large` → ~4rem to 7rem
- `xxx-large` → ~6rem to 10rem

#### Color Variable Format

```html
<!-- In block attributes: -->
"backgroundColor": "primary"

<!-- Generates class: -->
class="has-primary-background-color has-background"

<!-- In inline styles: -->
style="background-color:var(--wp--preset--color--primary)"
```

#### Semantic Color Naming

- **Brand:** `primary`, `primary-accent`, `primary-dark`
- **Contrast:** `main` (dark gray), `main-accent` (medium gray)
- **Base:** `base` (white), `secondary` (light gray), `tertiary` (very light gray)
- **Borders:** `border-light`, `border-dark`

### 4.2 Margin Reset on Background Sections

**ALWAYS add margin reset to patterns with:**
- Background colors
- Full-width (`align="full"`) or wide (`align="wide"`) alignment

#### Structure

```html
<!-- wp:group {
  "align": "full",
  "backgroundColor": "primary",
  "style": {
    "spacing": {
      "margin": {"top": "0", "bottom": "0"},
      "padding": {
        "top": "var:preset|spacing|x-large",
        "bottom": "var:preset|spacing|x-large"
      }
    }
  }
} -->
```

#### Why Required

- WordPress core adds `margin-block-start` between blocks in constrained layouts
- Without reset, unwanted gaps appear between adjacent patterns
- Inline styles preferred over CSS overrides (explicit, visible control)

#### When to Apply

- Full-width sections with backgrounds
- Hero sections, CTAs, testimonials, feature grids
- Any pattern stacking vertically with other background patterns

### 4.3 Border Radius

**Common values across patterns:**

- `"5px"` - Most common (cards, small elements)
- `"8px"` - Slightly larger cards and buttons
- `"12px"` - Large cards, images
- `"100px"` or `"500px"` - Circular avatars/images

#### Structure

```json
{
  "style": {
    "border": {
      "radius": "5px"
    }
  }
}
```

#### Specific Corners

```json
{
  "style": {
    "border": {
      "radius": {
        "topLeft": "5px",
        "topRight": "5px"
      }
    }
  }
}
```

---

## 5. Image Handling

### 5.1 Image Path Format (Critical)

#### ❌ WRONG - Hardcoded Media IDs

```html
<!-- NEVER use hardcoded media IDs: -->
<!-- wp:image {"id":59,"sizeSlug":"full"} -->
<figure class="wp-block-image">
  <img src="http://example.com/wp-content/uploads/2024/image.jpg" alt=""/>
</figure>
<!-- /wp:image -->
```

**Problems with hardcoded IDs:**
- Causes "Block validation failed" errors in console
- Media queries fail on fresh installations (media doesn't exist)
- Database-dependent, breaks portability
- Performance issues from failed queries

#### ✅ CORRECT - Theme URI Paths

```html
<!-- wp:image {"sizeSlug":"full","linkDestination":"none"} -->
<figure class="wp-block-image size-full">
  <img src="<?php echo esc_url( get_template_directory_uri() . '/patterns/images/filename.webp' ); ?>"
       alt="Descriptive alt text"/>
</figure>
<!-- /wp:image -->
```

#### Alternative Method (get_theme_file_uri)

```html
<img src="<?php echo esc_url( get_theme_file_uri( 'patterns/images/filename.svg' ) ); ?>"
     alt="Descriptive alt text"/>
```

### 5.2 Image Attributes

#### Responsive Image Configuration

```json
{
  "sizeSlug": "full",
  "linkDestination": "none",
  "aspectRatio": "1",
  "scale": "cover",
  "align": "center",
  "width": "95px"
}
```

#### Featured Images in Post Patterns

```html
<!-- wp:post-featured-image {
  "isLink": true,
  "aspectRatio": "2/3",
  "sizeSlug": "elayne-portrait-small",
  "style": {"border": {"radius": "5px"}}
} /-->
```

**Custom image sizes** (defined in `functions.php`):
- `elayne-portrait-small` - 380×570 (2:3 ratio)
- `elayne-portrait-medium` - 380×507 (3:4 ratio)
- `elayne-portrait-large` - 380×475 (4:5 ratio)
- `elayne-single-hero` - 700×400 (~16:9 ratio)

---

## 6. Typography

### 6.1 Font Size Variables

**All sizes use responsive `clamp()` for fluid scaling:**

- `x-small` → 0.825rem to 0.95rem
- `small` → 0.9rem to 1.05rem
- `base` → 1rem to 1.165rem
- `medium` → 1.2rem to 1.65rem
- `large` → 1.5rem to 2.75rem
- `x-large` → 1.875rem to 3.5rem
- `xx-large` → 2.25rem to 4.3875rem

#### Usage

```json
{
  "fontSize": "large",
  "style": {
    "typography": {
      "fontWeight": "600"
    }
  }
}
```

### 6.2 Font Families

**Semantic font family variables:**

- `primary` - Mona Sans (headings, display text)
- `secondary` - Open Sans (body text)
- Serif options - Bitter (optional accent)
- Monospace - System monospace (code blocks)

#### Usage

```json
{
  "fontFamily": "primary",
  "style": {
    "typography": {
      "fontWeight": "800",
      "lineHeight": "1.2"
    }
  }
}
```

### 6.3 Typography Inline Styles

```json
{
  "style": {
    "typography": {
      "fontWeight": "600",
      "fontStyle": "normal",
      "lineHeight": "1.3",
      "letterSpacing": "-0.02em",
      "fontSize": "clamp(2.75rem, 6vw, 4.5rem)"
    }
  }
}
```

**Common values:**
- **Font weight:** 300 (light), 400 (regular), 600 (semibold), 700 (bold), 800 (extrabold)
- **Line height:** 1.1-1.7 (headings: 1.1-1.3, body: 1.5-1.7)
- **Letter spacing:** -0.02em to -0.01em (tight for headings)

---

## 7. Pattern Categories

### Elayne Theme Categories

**Registered in `functions.php`:**

- **Header/Footer:** `header`, `footer`
- **Hero/Banner:** `elayne/hero`, `banner`, `featured`
- **Features:** `elayne/features`
- **Call-to-Action:** `elayne/call-to-action`
- **Cards:** `elayne/card`
- **Blog/Posts:** `elayne/blog`, `posts`, `elayne/posts`
- **Testimonials:** `elayne/testimonial`
- **Team:** `elayne/team`
- **Statistics:** `elayne/statistics`
- **Contact:** `elayne/contact`
- **Pages:** `elayne/pages` (template patterns)

### Category Usage Guidelines

1. **Multiple categories allowed:** Patterns can belong to multiple categories
2. **Theme prefix:** Use `elayne/` prefix for custom categories
3. **WordPress core:** Can use core categories like `banner`, `featured`, `posts`
4. **Consistency:** Match category names exactly (case-sensitive)

---

## 8. Pattern-Specific Requirements

### 8.1 Full-Width Background Patterns

**Examples:** Hero sections, CTAs, testimonials, feature grids with backgrounds

**Checklist:**
- ✅ Margin reset: `"margin":{"top":"0","bottom":"0"}`
- ✅ Outer group uses `"layout":{"type":"default"}`
- ✅ Nested constrained groups for content
- ✅ Padding for spacing: `"padding":{"top":"var:preset|spacing|x-large",...}`
- ✅ Background color or gradient applied
- ✅ `align="full"` on outer group

### 8.2 Card/Box Patterns

**Examples:** Feature cards, pricing boxes, testimonial cards

**Checklist:**
- ✅ Constrained layout (not full-width)
- ✅ Border radius: typically `"5px"` or `"8px"`
- ✅ Padding: typically `medium` or `large`
- ✅ Background color: `base`, `tertiary`, or brand colors
- ✅ Optional border: `"border":{"width":"1px","color":"var:preset|color|border-light"}`

### 8.3 Feature Grids

**Examples:** 3-column features, services showcase, team grid

**Checklist:**
- ✅ Use `"layout":{"type":"grid","minimumColumnWidth":"20rem"}`
- ✅ Direct children are grid items (responsive wrapping)
- ✅ Each item is a `wp:group` with consistent styling
- ❌ Avoid `wp:columns` block
- ✅ Consistent spacing between items

### 8.4 Template Patterns

**Examples:** Page templates, post templates, archive layouts

**Checklist:**
- ✅ Include `Post Types: wp_template` in header
- ✅ Categories include `elayne/pages` or similar
- ✅ Must include `post-content` block for dynamic content
- ✅ Use `<!-- wp:post-content {"layout":{"type":"constrained"}} /-->`
- ✅ Semantic tags: `"tagName":"main"` for main content

### 8.5 Query-Based Patterns

**Examples:** Blog post grid, recent posts, archive listings

**Checklist:**
- ✅ Use `wp:query` block for dynamic post loops
- ✅ Configure: `queryId`, `perPage`, `postType`, `orderBy`
- ✅ Include `wp:post-template` for loop markup
- ✅ Add `wp:query-no-results` for empty state
- ✅ Use post blocks: `wp:post-title`, `wp:post-date`, `wp:post-featured-image`, `wp:post-excerpt`

**Example structure:**

```html
<!-- wp:query {"queryId":1,"query":{"perPage":6,"postType":"post"}} -->
<div class="wp-block-query">

  <!-- wp:post-template {"layout":{"type":"grid","minimumColumnWidth":"20rem"}} -->
    <!-- wp:post-featured-image /-->
    <!-- wp:post-title /-->
    <!-- wp:post-excerpt /-->
  <!-- /wp:post-template -->

  <!-- wp:query-no-results -->
    <p>No posts found.</p>
  <!-- /wp:query-no-results -->

</div>
<!-- /wp:query -->
```

---

## 9. Accessibility and Semantics

### 9.1 Semantic HTML Tags

**Use correct heading hierarchy:**

```html
<!-- First heading should be h1 -->
<!-- wp:heading {"level":1} -->
<h1>Main Page Heading</h1>
<!-- /wp:heading -->

<!-- Subheadings use h2, h3, h4 in order -->
<!-- wp:heading {"level":2} -->
<h2>Section Heading</h2>
<!-- /wp:heading -->

<!-- wp:heading {"level":3} -->
<h3>Subsection Heading</h3>
<!-- /wp:heading -->
```

**Guidelines:**
- Never skip heading levels (h1 → h3)
- Only one h1 per page/template
- Maintain logical hierarchy

### 9.2 Image Alt Text

**All images MUST have descriptive alt text:**

```php
alt="<?php esc_attr_e( 'Team member photo showing person in professional attire', 'elayne' ); ?>"
```

**Guidelines:**
- Describe image content and context
- Keep concise (< 125 characters recommended)
- Use `esc_attr_e()` for translatable alt text
- Don't include "image of" or "photo of" (redundant)
- Decorative images can use empty alt: `alt=""`

### 9.3 Landmark Elements

**For template patterns, use semantic HTML5 tags:**

```json
{
  "tagName": "header"  // Site header
}
```

```json
{
  "tagName": "footer"  // Site footer
}
```

```json
{
  "tagName": "main"    // Main content area
}
```

```json
{
  "tagName": "section" // Major content sections
}
```

**Benefits:**
- Screen reader navigation
- Semantic document structure
- SEO improvements

### 9.4 ARIA Labels (When Needed)

```html
<!-- wp:navigation {"ariaLabel":"Primary navigation"} /-->
```

```html
<button aria-label="<?php esc_attr_e( 'Close menu', 'elayne' ); ?>">
  <span aria-hidden="true">×</span>
</button>
```

---

## 10. Using PHP in Patterns

### 10.1 PHP Pattern Security (CRITICAL)

According to [WordPress documentation](https://developer.wordpress.org/themes/patterns/using-php-in-patterns/), **all dynamic content must be properly escaped for security**.

**Security Requirements:**

✅ **Text output:** Use `esc_html()` or `esc_html_e()` for user-facing text
```php
<h2><?php esc_html_e( 'Welcome to My Site', 'elayne' ); ?></h2>
```

✅ **URLs:** Apply `esc_url()` to dynamic asset paths
```php
<img src="<?php echo esc_url( get_theme_file_uri( 'patterns/images/hero.jpg' ) ); ?>" alt="">
```

✅ **Attributes:** Use `esc_attr()` or `esc_attr_e()` for HTML attributes
```php
<div aria-label="<?php esc_attr_e( 'Main navigation', 'elayne' ); ?>">
```

✅ **HTML content:** Use `wp_kses_post()` for HTML-containing text
```php
<?php echo wp_kses_post( __( '<strong>Bold text</strong> to translate', 'elayne' ) ); ?>
```

**Why escaping is critical:**
- Prevents XSS (Cross-Site Scripting) attacks
- Ensures data is safe for output in specific contexts
- WordPress coding standards requirement
- Combines security with internationalization

### 10.2 Common PHP Use Cases in Patterns

**Dynamic Asset Paths** (REQUIRED for images):
```php
<?php echo esc_url( get_template_directory_uri() . '/patterns/images/hero.webp' ); ?>
<!-- OR -->
<?php echo esc_url( get_theme_file_uri( 'patterns/images/hero.webp' ) ); ?>
```

**Internationalization** (REQUIRED for all text):
```php
<?php esc_html_e( 'Read More', 'elayne' ); ?>
```

**Repetitive Content** (DRY principle):
```php
<?php
$features = [
    ['icon' => 'star.svg', 'title' => 'Quality'],
    ['icon' => 'check.svg', 'title' => 'Reliability'],
    ['icon' => 'heart.svg', 'title' => 'Support'],
];

foreach ( $features as $feature ) : ?>
    <!-- wp:group -->
    <div class="wp-block-group">
        <img src="<?php echo esc_url( get_theme_file_uri( 'patterns/images/' . $feature['icon'] ) ); ?>" alt="">
        <h3><?php echo esc_html( $feature['title'] ); ?></h3>
    </div>
    <!-- /wp:group -->
<?php endforeach; ?>
```

### 10.3 PHP Pattern Execution Context

**Registration Timing:**
- Patterns register on the `init` hook
- WordPress compiles pattern content and saves as HTML block markup
- Happens BEFORE WordPress global query is available

**Available Functions:**
- ✅ Standard PHP functions (`foreach`, `array_map`, etc.)
- ✅ WordPress helper functions (`esc_html()`, `esc_url()`, etc.)
- ✅ Theme functions (`get_theme_file_uri()`, `get_template_directory_uri()`)
- ✅ Translation functions (`__()`, `esc_html_e()`, etc.)
- ❌ Query-dependent functions (`is_page()`, `get_post()`, `the_title()`)

---

## 11. Internationalization (i18n)

### 11.1 Text Domain

**Elayne theme:** `'elayne'`
**Ollie theme:** `'ollie'`

### 11.2 Translation Functions

**All user-facing text must be translatable AND properly escaped:**

```php
<!-- For echoing text (combines escaping + translation): -->
<?php esc_html_e( 'Text to translate', 'elayne' ); ?>

<!-- For returning text (must also escape): -->
<?php echo esc_html__( 'Text to translate', 'elayne' ); ?>

<!-- For attributes (combines escaping + translation): -->
alt="<?php esc_attr_e( 'Alt text to translate', 'elayne' ); ?>"

<!-- For HTML-containing text (sanitize + translate): -->
<?php echo wp_kses_post( __( '<strong>Bold text</strong> to translate', 'elayne' ) ); ?>
```

**Why combine escaping with translation:**
WordPress documentation states: "To both escape the text for security and make it ready for translators," you must use the combined escaping/translation functions (`esc_html_e()`, `esc_attr_e()`, etc.).

### 11.3 Translation Guidelines

**What to translate:**
- All visible text content
- Image alt text
- Button labels
- Form placeholders
- Navigation labels
- Error messages

**What NOT to translate:**
- CSS class names
- Block attribute names
- HTML tags
- URLs
- Code/developer comments (optional)

### 11.4 Example Pattern with i18n

```php
<!-- wp:heading {"level":2} -->
<h2><?php esc_html_e( 'Our Services', 'elayne' ); ?></h2>
<!-- /wp:heading -->

<!-- wp:paragraph -->
<p><?php esc_html_e( 'We provide comprehensive solutions for your business needs.', 'elayne' ); ?></p>
<!-- /wp:paragraph -->

<!-- wp:button -->
<div class="wp-block-button">
  <a class="wp-block-button__link">
    <?php esc_html_e( 'Learn More', 'elayne' ); ?>
  </a>
</div>
<!-- /wp:button -->
```

---

## 12. Common Mistakes to Avoid

### Critical Errors (Cause Validation Failures)

1. **❌ Unescaped PHP output (SECURITY VULNERABILITY)**
   - Example: `<img src="<?php echo get_theme_file_uri('image.jpg'); ?>">` (WRONG)
   - Causes: XSS (Cross-Site Scripting) vulnerabilities, WordPress coding standards violations
   - Fix: Always escape output: `<?php echo esc_url( get_theme_file_uri('image.jpg') ); ?>`
   - **Required escaping functions:**
     - URLs: `esc_url()`
     - Text: `esc_html()` or `esc_html_e()`
     - Attributes: `esc_attr()` or `esc_attr_e()`
     - HTML: `wp_kses_post()`

2. **❌ Hardcoded media IDs in `wp:image` blocks**
   - Causes: Database queries, console errors, validation failures
   - Fix: Use `get_template_directory_uri()` with file paths and proper escaping

3. **❌ Root-level attributes nested inside `style` object**
   - Example: `"style":{...,"backgroundColor":"base"}`
   - Causes: Block validation errors
   - Fix: Move `backgroundColor`, `layout`, `align` to root level

4. **❌ Block comment attributes don't match rendered HTML**
   - Example: Padding declared in block JSON (`left/right`) not present in rendered `style` attributes
   - Causes: Block validation errors because serialized markup differs from saved HTML
   - Fix: Ensure rendered HTML includes all declared padding/margin/border attributes; compare saved HTML to block comment JSON

5. **❌ `align="full"` with `"layout":{"type":"constrained"}` on same group**
   - Causes: Horizontal gaps, overflow issues
   - Fix: Use `"layout":{"type":"default"}` on outer alignfull group

6. **❌ Using `wp:columns` for responsive multi-column layouts**
   - Causes: Cramped tablet layout (3→3→1 instead of 3→2→1)
   - Fix: Use `"layout":{"type":"grid","minimumColumnWidth":"20rem"}`

### Best Practice Violations

7. **❌ Missing metadata attribute on outermost block**
   - Causes: Reduced pattern discovery/copy-paste portability (not typically a validation blocker)
   - Fix: Add metadata with name, categories, patternName to keep inserter labeling intact

8. **❌ Hardcoded colors/sizes instead of theme variables**
   - Example: `"style":{"color":{"background":"#f0f0f0"}}`
   - Fix: Use `"backgroundColor":"tertiary"` or theme color variables

9. **❌ Missing margin reset on background patterns**
   - Causes: Unwanted gaps between adjacent patterns
   - Fix: Add `"margin":{"top":"0","bottom":"0"}`

10. **❌ No alt text on images**
    - Causes: Accessibility violations, SEO issues
    - Fix: Add descriptive `alt="..."` to all images with proper escaping

11. **❌ Untranslated user-facing text**
    - Causes: Non-translatable interface, missing security escaping
    - Fix: Wrap all text in `esc_html_e()` or combine with `__()` + escaping functions

12. **❌ Inconsistent spacing/padding between sections**
    - Causes: Visual rhythm issues
    - Fix: Use consistent spacing variables from theme.json

13. **❌ Using HTML blocks instead of native WordPress blocks**
    - Example: `<!-- wp:html --><div class="custom">...</div><!-- /wp:html -->`
    - Causes: Non-editable in block editor, breaks pattern editing
    - Fix: Use `wp:group`, `wp:list`, `wp:separator` with CSS classes

14. **❌ Font sizes in pixels instead of responsive units**
    - Example: `"fontSize":"16px"`
    - Fix: Use font size variables or `clamp()` values

15. **❌ Missing border-radius on cards/buttons**
    - Causes: Sharp corners inconsistent with design
    - Fix: Add `"border":{"radius":"5px"}` or `"8px"`

16. **❌ Layout type mismatches**
    - Example: Full-width section with constrained inner layout directly
    - Fix: Always nest: alignfull (default) → constrained group → content

17. **❌ Using query-dependent PHP functions in patterns**
    - Example: `<?php if ( is_page() ) { ... } ?>` (WRONG - not available during init)
    - Causes: Functions not available during pattern registration on `init` hook
    - Fix: Only use functions available during `init` (helper functions, theme functions, translations)

---

## 13. Quick Reference Checklist

### For Every Pattern, Verify:

#### Header & Metadata
- [ ] Header has Title, Slug, Description, Categories
- [ ] Outermost block includes metadata attribute (recommended for discovery/copy-paste, not required for validation)
- [ ] If metadata is present, fields match header (name = Title, patternName = Slug)
- [ ] Slug format: `elayne/pattern-slug` (theme-prefixed)
- [ ] Categories registered in `functions.php`

#### Structure & Layout
- [ ] Full-width groups use `"layout":{"type":"default"}`
- [ ] Nested groups use `"layout":{"type":"constrained"}` with contentSize
- [ ] Multi-column layouts use grid (not columns) for responsive behavior
- [ ] Block comment attributes match rendered HTML (padding, margin, border) to avoid validation errors
- [ ] Background sections have margin reset: `"margin":{"top":"0","bottom":"0"}`
- [ ] Consistent padding: typically x-large or xx-large for sections

#### Styling
- [ ] All colors use theme variables (no hardcoded hex/rgb)
- [ ] All spacing uses theme variables (no hardcoded px/rem)
- [ ] Border-radius applied to cards: typically `"5px"` or `"8px"`
- [ ] Typography uses font size variables (not pixels)
- [ ] Font weights appropriate (600-800 for headings, 400 for body)

#### Images
- [ ] No hardcoded media IDs in `wp:image` blocks
- [ ] All images use `get_template_directory_uri()` or `get_theme_file_uri()`
- [ ] All images have descriptive alt text
- [ ] Image paths point to `patterns/images/` directory
- [ ] Aspect ratio set for consistent sizing

#### PHP & Security
- [ ] All PHP output properly escaped (URLs: `esc_url()`, Text: `esc_html()`, Attributes: `esc_attr()`)
- [ ] All user-facing text uses translation functions (`esc_html_e()`, `esc_attr_e()`)
- [ ] No query-dependent functions used (`is_page()`, `get_post()`, `the_title()`)
- [ ] Only functions available during `init` hook
- [ ] Dynamic asset paths use `get_theme_file_uri()` with `esc_url()`

#### Accessibility
- [ ] Heading hierarchy correct (h1 → h2 → h3)
- [ ] Semantic HTML tags used (`header`, `footer`, `main`, `section`)
- [ ] All user text uses i18n functions with escaping (`esc_html_e()`, `esc_attr_e()`)
- [ ] ARIA labels where needed (navigation, buttons)
- [ ] Alt text translated and escaped: `alt="<?php esc_attr_e( '...', 'elayne' ); ?>"`

#### Validation
- [ ] No validation errors in browser console
- [ ] Pattern appears in editor inserter
- [ ] Pattern preview renders correctly
- [ ] Text/content editable in block editor
- [ ] Works at different viewport widths (mobile, tablet, desktop)

#### Testing Checklist
- [ ] Test pattern insertion in WordPress editor
- [ ] Verify pattern appears in correct category
- [ ] Check responsive behavior at 375px, 768px, 1024px, 1440px
- [ ] Validate no console errors (F12 → Console)
- [ ] Ensure all links/buttons functional
- [ ] Test with different theme colors (if applicable)

---

## Additional Resources

### Official WordPress Documentation
- [Block Patterns - Starter Patterns](https://developer.wordpress.org/themes/patterns/starter-patterns/) - Pattern headers, types, and registration
- [Block Patterns - Using PHP in Patterns](https://developer.wordpress.org/themes/patterns/using-php-in-patterns/) - PHP security, escaping, and limitations
- [Block Pattern API](https://developer.wordpress.org/block-editor/reference-guides/block-api/block-patterns/) - Technical API reference
- [Block Editor Handbook](https://developer.wordpress.org/block-editor/) - Block editor fundamentals
- [Theme.json Reference](https://developer.wordpress.org/block-editor/how-to-guides/themes/theme-json/) - Theme configuration and design tokens
- [Block Serialization & Validation](https://developer.wordpress.org/block-editor/reference-guides/block-api/block-serialization/) - How block attributes map to saved HTML
- [Metadata in block.json](https://developer.wordpress.org/block-editor/reference-guides/block-api/block-metadata/) - Block metadata structure
- [WordPress Gutenberg Issue #71687](https://github.com/wordpress/gutenberg/issues/71687) - Pattern metadata attribute implementation

### Theme Documentation
- [Elayne CLAUDE.md](../demo/web/app/themes/elayne/CLAUDE.md) - Comprehensive theme development guide
- [Elayne AGENTS.md](../demo/web/app/themes/elayne/AGENTS.md) - Repository guidelines and workflows
- [Block Validation Errors](./BLOCK-VALIDATION-ERRORS.md) - Common errors and fixes

### Analysis Sources
- **Elayne patterns:** 43 patterns in `/demo/web/app/themes/elayne/patterns/`
- **Ollie patterns:** 98 patterns in `~/code/ollie/patterns/`
- **Total analyzed:** 141 production-ready block patterns
- **WordPress official documentation:** Pattern guidelines and PHP security requirements

---

**Document Version:** 1.2
**Last Updated:** December 15, 2025
**Maintained By:** Imagewize Development Team

**Changelog:**
- **v1.2 (Dec 15, 2025):** Clarified metadata as recommended (not required), documented block comment vs rendered HTML validation issues, added block serialization reference, and updated checklist accordingly
- **v1.1 (Dec 15, 2024):** Added official WordPress documentation on PHP patterns, security requirements, pattern registration timing, metadata attribute details, template types, and PHP execution context limitations
- **v1.0 (Dec 15, 2024):** Initial version based on analysis of 141 production patterns
