#!/bin/bash

# Sync theme files from Trellis project to standalone theme repository
#
# This script uses rsync to synchronize theme files from your Trellis site
# to a separate theme repository, useful for theme development workflow.
#
# How it works:
# - rsync -av: Archive mode (preserves permissions, timestamps) with verbose output
# - --delete: Removes files in destination that don't exist in source
# - --exclude: Skips syncing specific directories (dependencies, git files)
#
# Customize the paths below for your setup:
# - Source: Your theme location within the Trellis project
# - Destination: Your standalone theme repository
#
# Example theme name used: 'nynaeve' - replace with your actual theme name

rsync -av --delete \
  --exclude create-pr.sh \
  --exclude .distignore \
  --exclude 'node_modules/' \
  --exclude 'vendor/' \
  --exclude '.git/' \
  --exclude '.github/' \
  ~/code/example.com/demo/web/app/themes/elayne/ \
  ~/code/elayne/
  