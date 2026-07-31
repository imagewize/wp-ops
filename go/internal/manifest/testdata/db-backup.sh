#!/bin/bash

# Trellis Database Backup Script
# Focused database backup using WP-CLI for WordPress sites on Trellis
#
# Runs on the server: it reads /srv/www/<site-name> and writes to
# /srv/backups/<site-name>/database, so both paths have to be the host's own.
# Stream it over SSH the same way as the monitoring scripts — nothing needs to
# be installed on the server.
#
# Usage:
#   ssh web@example.com 'bash -s' < ./db-backup.sh [site-name] [backup-type]
#   ./db-backup.sh example.com production     # on the server itself
#
# Backup types: production, staging, development
#
# staging and development additionally produce a second dump with the site URL
# rewritten for that environment; production produces the plain dump only.
#
# @desc     Back up a Trellis site database with WP-CLI, gzip it, and prune backups older than 30 days
# @category backup
# @runs     server
# @requires wp
# @arg      site-name    optional  {example.com}  Site directory under /srv/www
# @arg      backup-type  optional  {production|staging|development}  Backup type
# @example  wp-ops scripts/backup/db-backup example.com production
# @doc      trellis/backup/README.md

set -e
