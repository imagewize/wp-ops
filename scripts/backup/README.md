# Backup scripts

Shell backup scripts, split by the stack they need rather than by what they
do. The Ansible equivalents live in [`trellis/backup/`](../../trellis/backup/README.md)
and are Trellis-only by construction.

| Script | Platform | What it needs |
| --- | --- | --- |
| [`wp-db-backup.sh`](wp-db-backup.sh) | `wordpress` | WP-CLI and a reachable database. Nothing else. |
| [`db-backup.sh`](db-backup.sh) | `trellis` | SSH as `web@`, site under `/srv/www/<site>/current` |
| [`db-pull.sh`](db-pull.sh) | `trellis` | A Trellis project — runs `trellis vm shell` |
| [`site-backup.sh`](site-backup.sh) | `trellis` | Runs *on* the server; reads `/srv/www`, writes `/srv/backups` |

`wp-ops list --platform wordpress` and the `[trellis]` badge on
`wp-ops search backup` report the same split from the CLI.

## Which one do I want?

If the site is a Trellis site, the three Trellis-shaped scripts know its
conventions and are less to type. For anything else — Valet, Herd, cPanel,
plain `public_html`, a Bedrock checkout that isn't Trellis-managed — use
`wp-db-backup.sh`, which discovers what the others assume.

```bash
# Local site, any layout
wp-ops wp-db-backup --path ~/code/example

# Remote host over SSH — no /srv/www assumption, so say where the site is
wp-ops wp-db-backup --host user@example.com --site-path /home/user/public_html

# Shared hosting with its own PHP and a wp-cli.phar
wp-ops wp-db-backup --host user@example.com --site-path ~/public_html \
    --wp-bin ~/wp-cli.phar --php-bin /opt/plesk/php/8.2/bin/php
```

Output is `database_backup/<site>_<YYYY_MM_DD>_<HH_MM_SS>.sql.gz`, named from
`wp option get siteurl` — there is no `wordpress_sites.yml` to read outside
Trellis. Override with `--name`, change the directory with `--dest`.

### What it detects

- **Layout.** Looks for `wp-load.php` at the path you gave, then `web/wp`
  (Bedrock), then `wordpress/` (a common shared-hosting default). `--path`
  points at the *site*, not at WordPress core.
- **Site URL.** Read from the database, which is also what the file is named
  after.

The dump is streamed — `wp db export -` on one end, `gzip` into a local file
on the other. Nothing is written on the server, so no writable backup
directory has to exist there and there is nothing to clean up afterwards.

## Restoring

```bash
gzip -dc database_backup/example_com_2026_08_05_10_43_33.sql.gz \
  | wp db import - --path=/path/to/wordpress
```

The script prints this line with the real paths filled in when it finishes.

## If the backup is rejected

`wp-db-backup.sh` refuses to keep a dump whose first line isn't SQL, because
**anything a host prints to stdout lands ahead of the dump and gzips into a
file that looks perfectly healthy while failing on import.** A trailing
`Dump completed` marker does not catch this — the marker is still there.

The usual cause is PHP notices on a host whose `display_errors` goes to
stdout. WP-CLI's shebang wrapper gives no way to pass `-d`, so route them to
stderr by invoking PHP yourself:

```bash
wp-ops wp-db-backup --path ~/code/example \
    --php-bin php --wp-bin "$(command -v wp)"
```

This is also why the script runs WP-CLI *from the site directory*: WP-CLI
finds `wp-cli.yml` by walking up from the working directory, not from
`--path`, so a site whose config quiets its own deprecations only gets that
config when you're standing in it.

## Not yet written

`docs/category-organization.md` (step 6) anticipates two siblings, neither of
which exists yet — `wp-site-backup.sh` (database + `wp-content`/`web/app` +
config) and `wp-db-pull.sh` (remote to local with `search-replace`, plain
`wp` rather than `trellis vm shell`). Keep any additions on distinct
basenames: `wp-ops db-backup` becomes ambiguous the moment two scripts share
one.
