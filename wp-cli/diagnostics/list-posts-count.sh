#!/bin/bash
# List all published posts and count lines
#
# @desc     Count published posts on example.com via SSH and save the list to /tmp/all_posts.csv
# @category diagnostics
# @platform trellis
# @runs     local
# @mutates  false
# @requires ssh
# @example  wp-ops list-posts-count
# @doc      wp-cli/diagnostics/README.md

ssh web@example.com "cd /srv/www/example.com/current && wp post list --post_type=post --post_status=publish --fields=ID,post_title,post_name,post_date --path=web/wp --format=csv" > /tmp/all_posts.csv 2>&1
wc -l /tmp/all_posts.csv