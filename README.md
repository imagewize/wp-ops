<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo.svg" alt="wp-ops wind rose logo" width="128" height="128">
  </picture>
  <h1>WP OPS</h1>
</div>
<div align="center">

[![Homebrew Downloads](https://img.shields.io/github/downloads/imagewize/wp-ops/total.svg?label=brew%20downloads)](https://github.com/imagewize/wp-ops/releases)
[![Latest Release](https://img.shields.io/github/v/release/imagewize/wp-ops.svg?label=version)](https://github.com/imagewize/wp-ops/releases)
[![License](https://img.shields.io/github/license/imagewize/wp-ops.svg)](LICENSE.md)

</div>

<div align="center">
<strong>The day-to-day ops layer for <a href="https://roots.io/trellis/">Trellis</a> sites.</strong><br>
Sync production into development, see who is hitting your server, and publish content —
from the terminal, as <code>trellis ops</code>, or through Claude and other MCP clients.
</div>

## What it solves

[trellis-cli](https://github.com/roots/trellis-cli) provisions and deploys. The work
that happens *between* deploys — getting a fresh copy of production, checking traffic
after a launch, pushing a post live — is left to you, usually as a string of `ssh`,
`wp db export`, `rsync` and `wp search-replace` commands. wp-ops turns each of those
into one command.

### 1. Get production into development in one step

```bash
wp-ops database-pull example.com production   # export, download, import, search-replace
wp-ops files-pull example.com production      # rsync the uploads directory
```

The database is exported on the server, imported into development, and every
production URL is rewritten to your `.test` domain. Your current development database
is backed up to `database_backup/` first, so a pull is never a one-way trip.
`database-push` and `files-push` go the other way — and back up the remote first.

<p align="center">
  <img src="assets/screenshots/database-pull.gif" alt="wp-ops database-pull running the Ansible playbook from production to development, ending with the development home URL on the .test domain" width="800">
</p>

### 2. See who is hitting your server

```bash
wp-ops quick-status example.com production     # status codes, errors, services at a glance
wp-ops traffic-report example.com production   # real visitors vs. bots, landing pages, referrals
wp-ops security-scan example.com production    # wp-login/xmlrpc abuse, high-volume IPs
```

Reads the site's Nginx logs on the server — no analytics plugin, no third-party
service. Pair it with the [fail2ban setup](trellis/security/README.md) to block what
the scan finds.

### 3. Publish and verify content without opening wp-admin

```bash
wp-ops publish-post draft.html example.com production --image featured.jpg
wp-ops verify-post my-post-slug example.com production
```

Publishes an HTML draft with block markup (create or `--update`), uploads the featured
image, then checks that the blocks, JSON-LD and links survived the write and render on
the live page.

### 4. Hand all of it to Claude

The same operations are exposed as [MCP](https://modelcontextprotocol.io) tools —
`db_pull`, `files_pull`, `monitor`, `publish_post`, `verify_post`, `security_scan` and
more — so you can ask *"pull production into dev and tell me if anything looks off in
yesterday's traffic"* and let the assistant run it. Setup and the full tool list:
[mcp-server/README.md](mcp-server/README.md).

## Install

```bash
brew install imagewize/tap/wp-ops
wp-ops init      # shell completions (one-time)
wp-ops doctor    # check Ansible, WP-CLI, ssh and friends
```

Point it at your Trellis project with `TRELLIS_DIR` (or run it from inside one).
Homebrew also installs `trellis-ops`, so every command is available as
`trellis ops <...>` from trellis-cli:

```bash
trellis ops database-pull example.com production
```

<details>
<summary>Build from source instead (Go 1.26+)</summary>

```bash
git clone https://github.com/imagewize/wp-ops.git && cd wp-ops
go build -o wp-ops ./go
sudo mv wp-ops /usr/local/bin/   # or anywhere on your PATH
wp-ops init
```

The scripts and playbooks are embedded in the binary — once it's on your PATH
you can delete the clone.

</details>

## Finding your way around

Running `wp-ops` with no arguments opens an interactive picker of every command:

<p align="center">
  <img src="assets/screenshots/picker.png" alt="The wp-ops interactive picker: categories with command counts, descriptions and a trellis/wp/any platform breakdown" width="800">
</p>

```bash
wp-ops search webp                  # find a command by name or description
wp-ops backup --help                # every command in one category
wp-ops list --platform wordpress    # only what works on any WordPress site, Trellis or not
```

More in [Using the CLI](docs/cli/usage.md) and the
[trellis-cli plugin guide](docs/cli/trellis-cli-plugin.md).

## Also in the box

Beyond the core workflows above, the catalog carries the rest of the toolkit these
sites are run with:

| Area | What's there | Docs |
|------|--------------|------|
| **Trellis** | Safe Trellis updates (`trellis-updater`) | [guide](https://wpvilla.in/update-trellis-without-losing-customisations-rsync-excludes/) |
| **Backups** | Timestamped database and uploads backups from any environment | [→](trellis/backup/README.md) |
| **Monitoring** | AI-crawler traffic, error surfacing, traffic by country, cron-scheduled reports | [→](trellis/monitoring/README.md) |
| **Security** | Malware scanners with checksum verification, fail2ban, manual IP blocking, AbuseIPDB lookup | [scanners](wp-cli/security/README.md) · [server](trellis/security/README.md) |
| **Content & SEO** | Page creation, block pattern validation, redirect/schema/orphan-page audits | [SEO](wp-cli/seo/README.md) |
| **Nginx** | WebP/AVIF serving, browser caching and redirect templates for Trellis `nginx-includes/` | [images](docs/nginx/image-optimization/README.md) · [caching](docs/nginx/browser-caching/README.md) · [redirects](docs/nginx/redirects/README.md) |
| **Bedrock** | Testing unreleased packages via Composer `path` repos, standard `wp-cli.yml` | [packages](docs/bedrock/local-package-development/README.md) · [wp-cli.yml](docs/bedrock/wp-cli-config/README.md) |
| **Troubleshooting** | PHP-FPM, MariaDB, OOM and mail diagnostics | [→](docs/troubleshooting/README.md) |
| **Scripts & guides** | Theme sync, PR helpers, WP-CLI snippets for Bedrock | [scripts](scripts/README.md) · [snippets](docs/wordpress-utilities/snippets/README.md) |

## Requirements

- **Core**: Git, Bash, rsync, SSH access to your Trellis servers
- **Most Trellis commands**: Ansible (already present if you use Trellis)
- **Tool-specific**: WP-CLI, ImageMagick, `cwebp`, Node — `wp-ops doctor` tells you what's missing

## Wheel of Time Inspiration

Imagewize's projects take their names from *The Wheel of Time*. wp-ops keeps a plain, descriptive name because it has to be typed, and takes its **mark** — an original wind rose — from the Windfinders, the Sea Folk channelers who find the wind and bring the ship to port. The reasoning and the alternates considered are in [`assets/logos/`](assets/logos/README.md).

## License

MIT License. See [LICENSE.md](LICENSE.md) for details.

---

Copyright © Imagewize
