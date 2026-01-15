---
layout: default
title: WP OPS Book
permalink: /
---

# WP OPS BOOK

This book is a curated reading path for the wp-ops repository. Use it as your front door, then jump into the chapter you need.

## How to Use This Book
- Start with the Foundations if you are new to the stack.
- Use the reading paths to move quickly through a specific objective.
- Each chapter begins with a short "Chapter Purpose" section.

## Reading Paths
- **New operator**: Foundations -> Provisioning -> Backups -> Monitoring -> Troubleshooting
- **Migration**: Foundations -> Migration -> Backups -> Redirects -> Diagnostics
- **Performance**: Foundations -> Browser Caching -> Image Optimization -> Speed Optimization
- **Security**: Foundations -> Trellis Security -> WP-CLI Security -> Monitoring

## Table of Contents

### Front Matter
- Title + how to use this book: `README.md`
- Repository rules for operators: `AGENTS.md`
- Edition history: `CHANGELOG.md`

### Part I: Foundations
- Chapter 1: Operating principles and safety basics — `README.md` (scope, safety rules, and starting points)
- Chapter 2: Command helpers and doc conventions — `CLAUDE.md`, `CREATE-PR.md` (workflow norms and PR creation)

### Part II: Trellis Operations
- Chapter 3: Provisioning environments — `trellis/provision/README.md` (setup guides and core provisioning commands)
- Chapter 4: Backups and restores — `trellis/backup/README.md`, `scripts/backup/` (backup cadence and restore drills)
- Chapter 5: Monitoring and alerting — `trellis/monitoring/README.md`, `scripts/monitoring/` (traffic analysis and alerts)
- Chapter 6: Security hardening — `trellis/security/README.md` (layered controls and safe defaults)
- Chapter 7: Updating Trellis — `trellis/updater/README.md` (upgrade workflow and preserved configs)

### Part III: WP-CLI Workflows
- Chapter 8: Content creation — `wp-cli/content-creation/README.md` (repeatable page and pattern workflows)
- Chapter 9: Diagnostics — `wp-cli/diagnostics/README.md` (triage scripts and safe inspection)
- Chapter 10: Migration — `wp-cli/migration/README.md` (end-to-end migration paths)
- Chapter 11: Security checks — `wp-cli/security/README.md` (scanner usage and audit cadence)

### Part IV: Nginx Patterns
- Chapter 12: Browser caching — `nginx/browser-caching/README.md` (cache headers and validation steps)
- Chapter 13: Image optimization — `nginx/image-optimization/README.md` (modern formats and automation)
- Chapter 14: Redirects — `nginx/redirects/README.md` (safe include placement and rules)

### Part V: WordPress Utilities
- Chapter 15: Age verification — `wordpress-utilities/age-verification/README.md` (flow overview and integration steps)
- Chapter 16: Analytics — `wordpress-utilities/analytics/README.md` (implementation options and detection)
- Chapter 17: Speed optimization — `wordpress-utilities/speed-optimization/README.md` (TTFB checks and tooling)

### Part VI: Scripts and Automation
- Chapter 18: Utility scripts overview — `scripts/README.md` (inventory and usage notes)
- Chapter 19: Release and theme sync scripts — `scripts/release-theme.sh`, `scripts/rsync-theme.sh` (deploy helpers and sync flows)
- Chapter 20: PR helper script — `scripts/create-pr.sh` (generate consistent PR text)

### Appendices
- Appendix A: Troubleshooting index — `troubleshooting/README.md` (symptom-based entry points)
- Appendix B: Mail issues — `troubleshooting/MAIL.md` (SMTP and delivery failures)
- Appendix C: MariaDB issues — `troubleshooting/MariaDB.md` (DB outages and recovery)
- Appendix D: OOM issues — `troubleshooting/OOM.md` (memory exhaustion triage)
- Appendix E: PHP-FPM issues — `troubleshooting/PHP-FPM.md` (worker health and tuning)
- Appendix F: License — `LICENSE.md` (legal and reuse terms)

## Chapter Template
- Title and purpose
- Prerequisites
- Safety checklist
- Step-by-step workflow (with dry run first)
- Verification steps
- Cleanup / rollback
- Troubleshooting notes
- References / related chapters
