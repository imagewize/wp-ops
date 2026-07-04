#!/bin/bash
# List all published posts and count lines

ssh web@example.com "cd /srv/www/example.com/current && wp post list --post_type=post --post_status=publish --fields=ID,post_title,post_name,post_date --path=web/wp --format=csv" > /tmp/all_posts.csv 2>&1
wc -l /tmp/all_posts.csv