---
layout: chapter
title: "Content Creation"
chapter_number: 8
permalink: /chapters/content-creation/
---

# Content Creation Guide for WordPress

WP-CLI, Trellis, and block-pattern tooling for creating and updating WordPress content in Bedrock/Trellis environments. Use this file as a landing page; the deep guides live alongside it.

## Chapter Purpose

This chapter provides the entry points and commands for repeatable content creation with WP-CLI and patterns.

## Table of Contents
- [What's in This Folder](#whats-in-this-folder)
- [Choose Your Path](#choose-your-path)
- [Quick WP-CLI Commands (Bedrock paths)](#quick-wp-cli-commands-bedrock-paths)
- [Pattern Essentials](#pattern-essentials)
- [Troubleshooting Pointers](#troubleshooting-pointers)

## What's in This Folder
- [`PAGE-CREATION.md`](PAGE-CREATION.md) – Full workflows for local (Trellis VM) and production deployments.
- [`PATTERN-REQUIREMENTS.md`](PATTERN-REQUIREMENTS.md) – Canonical block pattern standards and validation checklist.
- [`page-creation.sh`](page-creation.sh) – Automated production page deploy script (copies content, checks conflicts, verifies output).
- [`examples/example-page-content.html`](examples/example-page-content.html) – Gutenberg block markup sample to copy and customize.

## Choose Your Path
- **Create/update pages end-to-end:** Follow [`PAGE-CREATION.md`](PAGE-CREATION.md) (includes slug checks, remote commands, troubleshooting).
- **Automate production deploys:** Configure and run `./page-creation.sh path/to/content.html "Page Title" "page-slug"` (see script header for server vars).
- **Validate or author patterns:** Read [`PATTERN-REQUIREMENTS.md`](PATTERN-REQUIREMENTS.md) for required metadata, spacing, and layout rules before adding pattern-based content.
- **Need a starting template?** Copy [`examples/example-page-content.html`](examples/example-page-content.html) and edit the block markup to fit your page.

## Quick WP-CLI Commands (Bedrock paths)
```bash
# Create a page locally in Trellis VM (replace file/title/slug)
trellis vm shell --workdir /srv/www/example.com/current -- bash -c '
CONTENT=$(cat /srv/www/example.com/current/site/about-page-content.html)
wp post create --post_type=page --post_title="About" --post_name="about" \
  --post_status=publish --post_content="$CONTENT" --path=web/wp
'

# Check for slug conflicts before creating
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post list --name=about --post_type=any --path=web/wp \
  --fields=ID,post_type,post_title,post_name,post_status
```
More detailed sequences live in [`PAGE-CREATION.md`](PAGE-CREATION.md).

## Pattern Essentials
- See [`PATTERN-REQUIREMENTS.md`](PATTERN-REQUIREMENTS.md) for full standards and validation steps.
- Outermost block must include `metadata` with `name`, `categories`, and `patternName` matching the header.
- Use theme presets for spacing/colors; avoid hardcoded px values.
- For full-width sections, keep the outer group `layout.type: "default"` and reset vertical margins; constrain inner groups.
- Prefer grid (`layout.type: "grid"` + `minimumColumnWidth`) over `wp:columns` for responsive cards/grids.
- Validate slugs against your theme’s registered patterns before deploying content.

## Troubleshooting Pointers
- Slug collisions produce `about-2` style names: list and remove conflicts (`wp post list --name=<slug> ...`).
- Content not updating: `wp cache flush --path=web/wp`; verify content with `wp post get <ID> --field=post_content`.
- Pattern not rendering: confirm the slug exists and matches exactly; see validation steps in [`PATTERN-REQUIREMENTS.md`](PATTERN-REQUIREMENTS.md).
