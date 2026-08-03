# wp-ops MCP server

Exposes wp-ops operations as [MCP](https://modelcontextprotocol.io) tools, so Claude
(and other MCP-compatible clients) can call them directly instead of you running the
underlying scripts by hand.

## Status

Scaffold — six tools implemented so far:

- **`security_scan`** — runs `wp-cli/security/scanner-targeted.php` / `scanner-general.php`
  against a registered site/environment. For remote environments it streams the scanner
  source over SSH stdin (`php - <path>`), so nothing is ever written to disk on the
  remote host — no `scp` + forget-to-delete step.
- **`db_backup`** — runs `wp db export` against a registered site/environment, gzips the
  result, and saves it locally to `~/wp-ops-backups/<site>/<env>/` (override with
  `WP_OPS_BACKUP_DIR`). For remote environments the export streams over SSH stdout, so
  again nothing is written to disk on the remote host. Requires `wp` (WP-CLI) on the
  machine running the export — locally that's your host; remotely it's already on any
  Trellis server.
- **`wp_cli`** — runs an arbitrary WP-CLI command (`args` as separate tokens, e.g.
  `["post", "list", "--format=json"]`) against a registered site/environment. `--path`
  is added automatically and rejected if passed explicitly. Read-only verbs
  (`list`/`get`/`exists`/`status`/`info`/`version`/`search`/`check-update`/`doctor`/
  `export`) run immediately; anything else — updates, deletes, `search-replace`,
  `eval`, installs, etc. — requires `confirm: true`, meant to be set only after the
  user has explicitly approved that specific command in conversation. For remote sites,
  each argument is shell-quoted before being handed to `ssh`, since `ssh` otherwise
  joins trailing args into one string for the remote shell to (re-)interpret.
- **`redirect_audit`** — runs a comprehensive redirect chain audit for one or more URLs. Tests
  HTTPS pages for 200 status with 0 redirects (optimal for SEO), verifies HTTP→HTTPS 301
  redirects, checks www→non-www canonicalization, and validates security headers (HSTS,
  CSP, X-Frame-Options, X-Content-Type-Options). Uses `curl` for HTTP requests.
- **`schema_audit`** — audits JSON-LD schema markup across key pages of a site. Checks for
  Organization, LocalBusiness, Service, Product, WebSite, BreadcrumbList, Article,
  FAQPage, HowTo, and Person schema types. Returns count of pages with/without schema
  and which schema types are present. Uses `curl` to fetch pages and extract schema.
- **`url_audit`** — audits `wp_posts.post_content` for hardcoded dev URLs (default
  patterns `.test`/`.localhost`) that `get_template_directory_uri()` bakes in during local
  content creation and that survive a database migration unless search-replaced — the
  CRITICAL check documented in the parent repo's `CLAUDE.md`. Reports a hit count per
  pattern. Pass `replace: {from, to}` to also preview a
  `wp search-replace --all-tables --precise --dry-run`; add `confirm: true` (only after
  explicit user approval) to apply it for real.

More tools (PR creation, releases, image optimization, git/gh helpers) will follow the
same pattern. See the parent repo's `CLAUDE.md` and the relevant README in each
directory for the operations these will eventually wrap.

Two transports are implemented, both verified end-to-end (real MCP `initialize` +
`tools/call` round trip against the real scanner):

- **stdio** (default) — the client spawns the process/container directly and talks over
  stdin/stdout. This is what Claude Code/Desktop use.
- **Streamable HTTP** — the server runs as a standing network service other MCP clients
  can connect to over a URL. This is the transport remote/non-Claude clients generally
  expect (e.g. Mistral's MCP connectors, or an agent framework fronting an Ollama-served
  model) — set `MCP_TRANSPORT=http`.

## Setup

```bash
cd mcp-server
npm install
cp config/sites.example.json config/sites.json
# edit config/sites.json with your real site paths / ssh hosts
npm run build
```

## Site registry

`config/sites.json` maps site → environment → where to find it:

- `localPath` — absolute path to a local WordPress install (used for `development`)
- `sshHost` + `remotePath` — an SSH host (an alias from `~/.ssh/config`, or anything
  `trellis` already uses) and the WordPress root on that host (`staging`/`production`)

`config/sites.json` is gitignored since it encodes your local paths/hosts. Set
`WP_OPS_SITES_CONFIG=/path/to/sites.json` to point at a different location.

## Register with Claude Code

**Recommended:** Register the server **user-scoped** in `~/.claude.json` so the tools
are available in every project and session. Project-scoped (`.mcp.json`) works but
limits the tools to only that project directory.

Add to your `~/.claude.json` (user-scoped) or `.mcp.json` (project-scoped):

```json
{
  "mcpServers": {
    "wp-ops": {
      "command": "node",
      "args": ["/absolute/path/to/wp-ops/mcp-server/dist/index.js"]
    }
  }
}
```

Or add the same block under `mcpServers` in Claude Desktop's config file.

> **Why user-scoped?** The site registry is central and multi-site. Registering
> user-scoped lets any session — including in the wp-ops repo itself — run audits
> or WP-CLI against any registered site without project-specific config.

## Permissions (pre-approve read-only tools)

The read-only tools (`redirect_audit`, `schema_audit`, `security_scan`, `url_audit`, and
read-only `wp_cli` commands) are safe to run without confirmation — `url_audit` only
ever queries counts and, at most, a `--dry-run` search-replace preview unless
`confirm: true` is explicitly set. Pre-approve them in `~/.claude/settings.json` to
avoid repeated permission prompts:

```json
{
  "mcp": {
    "permissions": {
      "mcp__wp-ops__redirect_audit": { "allowed": true },
      "mcp__wp-ops__schema_audit": { "allowed": true },
      "mcp__wp-ops__security_scan": { "allowed": true },
      "mcp__wp-ops__url_audit": { "allowed": true },
      "mcp__wp-ops__wp_cli": { "allowed": true }
    }
  }
}
```

Write operations (e.g., `wp_cli` with `search-replace`, `post delete`, `plugin install`,
or `url_audit` with `replace` + `confirm: true`) still require `confirm: true` and will
prompt for approval.

## Usage Tips

- **Multi-site registry:** `config/sites.example.json` shows the full schema.
  Add all your sites (Bedrock, plain WordPress, static sites) — the same tools
  work across all of them. URL-only entries enable `redirect_audit` and
  `schema_audit` for static/Jekyll sites.
- **CLAUDE.md integration:** In each project that uses these tools, add a note
  in `CLAUDE.md` like: "Prefer the wp-ops MCP tools (`wp_cli`, `security_scan`,
  `redirect_audit`, `schema_audit`, `db_backup`, `url_audit`) with the site key from
  `mcp-server/config/sites.json`."

## Running as a network service (Streamable HTTP)

For clients that connect over a URL instead of spawning a local process (remote MCP
connectors, e.g. Mistral's, or an agent framework driving an Ollama model):

```bash
MCP_TRANSPORT=http \
WP_OPS_MCP_TOKEN="$(openssl rand -hex 32)" \
MCP_HTTP_PORT=3000 \
npm start
```

The server **refuses to start in HTTP mode without `WP_OPS_MCP_TOKEN` set** — this
process can SSH into staging/production hosts on your behalf, so an unauthenticated
network listener isn't an acceptable default. Every request must send
`Authorization: Bearer <token>`; requests without it get a 401.

It binds to `127.0.0.1` by default (`MCP_HTTP_HOST` to change). If you expose it beyond
localhost or a private network, put TLS in front of it (reverse proxy) — the bearer
token travels in cleartext otherwise.

Client-side config depends on how that specific client wires up remote MCP servers —
point it at `http://<host>:<port>/mcp` with the bearer token, but check that client's
current docs for the exact syntax; this changes fast and I haven't verified Mistral's or
a specific Ollama-fronting framework's config format against a live account.

## Running in Docker

Build from the **repo root** (the image needs `wp-cli/security/` alongside `mcp-server/`):

```bash
docker build -f mcp-server/Dockerfile -t wp-ops-mcp-server .
```

Run it, mounting your site registry, SSH identity (needed for staging/production
scans/backups), and a backups directory (needed for `db_backup` — without this mount,
backups are written inside the container and lost when it exits with `--rm`):

```bash
docker run -i --rm \
  -v ~/code/wp-ops/mcp-server/config/sites.json:/config/sites.json:ro \
  -v ~/.ssh:/root/.ssh:ro \
  -v ~/wp-ops-backups:/root/wp-ops-backups \
  wp-ops-mcp-server
```

Point Claude Code / Claude Desktop at the container instead of a local `node` binary:

```json
{
  "mcpServers": {
    "wp-ops": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-v", "/Users/you/code/wp-ops/mcp-server/config/sites.json:/config/sites.json:ro",
        "-v", "/Users/you/.ssh:/root/.ssh:ro",
        "-v", "/Users/you/wp-ops-backups:/root/wp-ops-backups",
        "wp-ops-mcp-server"
      ]
    }
  }
}
```

This transport is still stdio (`-i` keeps stdin open, the client pipes JSON-RPC through
it) — it just runs inside a container instead of directly on your host, so you get a
fixed Node/PHP/openssh/wp-cli toolchain regardless of what's installed locally. Not yet
build-tested with a real `docker build` in this session (no Docker CLI available here) —
verify the build once you have Docker locally before relying on it.

**Trellis VM sites don't work in this container.** Sites registered with
`trellisDir`+`vmWorkdir` (a local Trellis dev VM) run their commands via
`trellis vm shell`, which drives a Vagrant/VirtualBox VM on the host machine. The image
doesn't include the `trellis` CLI, and even if it did, a container has no access to the
host's Vagrant state — there's no way to reach that VM from inside Docker. Only sites
using `localPath` or `sshHost`+`remotePath` work when running containerized; for Trellis
VM sites, run the server directly on the host (`npm start` / `npm run dev`) instead.

To run the container in HTTP mode instead, publish the port and pass the transport env vars:

```bash
docker run --rm \
  -p 127.0.0.1:3000:3000 \
  -e MCP_TRANSPORT=http \
  -e WP_OPS_MCP_TOKEN="$(openssl rand -hex 32)" \
  -v ~/code/wp-ops/mcp-server/config/sites.json:/config/sites.json:ro \
  -v ~/.ssh:/root/.ssh:ro \
  -v ~/wp-ops-backups:/root/wp-ops-backups \
  wp-ops-mcp-server
```

## Local dev loop

```bash
npm run dev   # runs src/index.ts directly via tsx, no build step needed
```

## Adding a new tool

1. Add a function under `src/tools/`.
2. Register it with `server.tool(...)` in `src/index.ts`.
3. If it's a write/destructive operation (push, deploy, release), require a
   `confirm: true` argument and document that clients should only set it after
   explicit user approval in conversation.
