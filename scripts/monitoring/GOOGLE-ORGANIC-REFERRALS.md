# Google Organic Referrals — Access Log Quick Reference

Commands for extracting Google organic referral data from Nginx access logs on a Trellis/Bedrock server.

## Full organic landing page breakdown

```bash
ssh web@imagewize.com "grep -i '\"https://www.google.com/' /srv/www/imagewize.com/logs/access.log \
  | awk '{for(i=1;i<=NF;i++) if(\$i ~ /\"https:\/\/www\.google\.com\//){print \$7}}' \
  | sort | uniq -c | sort -rn"
```

Returns each URL with hit count, sorted by most visited first.

## Filter out bots and noise

```bash
ssh web@imagewize.com "grep -i '\"https://www.google.com/' /srv/www/imagewize.com/logs/access.log \
  | grep -vE 'bot|Bot|crawler|spider|Googlebot|bingbot|AhrefsBot|SemrushBot|Slimstat' \
  | awk '{for(i=1;i<=NF;i++) if(\$i ~ /\"https:\/\/www\.google\.com\//){print \$7}}' \
  | sort | uniq -c | sort -rn"
```

## Count distinct organic landing pages (24h window)

```bash
ssh web@imagewize.com "tail -n 50000 /srv/www/imagewize.com/logs/access.log \
  | grep -i '\"https://www.google.com/' \
  | grep -vE 'bot|Bot|crawler|spider' \
  | awk '{for(i=1;i<=NF;i++) if(\$i ~ /\"https:\/\/www\.google\.com\//){print \$7}}' \
  | sort -u | wc -l"
```

## Check organic traffic to a specific page

```bash
ssh web@imagewize.com "grep '/your-post-slug/' /srv/www/imagewize.com/logs/access.log \
  | grep -i 'google.com' | wc -l"
```

## Check if a URL slug has appeared in Laravel category hits (non-bot)

```bash
ssh web@imagewize.com "tail -n 50000 /srv/www/imagewize.com/logs/access.log \
  | grep -i 'laravel' \
  | grep -vE 'bot|Bot|crawler|spider|Googlebot|bingbot|AhrefsBot|SemrushBot|Slimstat' \
  | awk '{print \$7}' | sort | uniq -c | sort -rn | head -20"
```

## Notes

- `tail -n 50000` approximates a 24h window; adjust for busier servers
- Slimstat AJAX hits (`/wp/wp-admin/admin-ajax.php`) can appear with a Google referrer — filter with `grep -v admin-ajax`
- Category pages receiving organic referrals after a noindex change will clear as Google re-crawls (typically 2–4 weeks)
- `/author/jasper/` appearing in organic referrals is a signal to add it to the noindex queue
