# wp-ops MCP server

Exposes wp-ops operations as [MCP](https://modelcontextprotocol.io) tools, so Claude
(and other MCP-compatible clients) can call them directly instead of you running the
underlying scripts by hand.

## Status

Scaffold — seven tools implemented so far:

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
- **`monitor`** — runs `scripts/monitoring/monitor.sh` (combined traffic, security,
  AI-crawler, and error-log analysis) against a registered site's Nginx logs and returns
  the generated markdown summary. Requires an `sshHost` entry — logs only exist on a
  deployed server, not local dev or a Trellis VM. Bundles all five monitoring scripts
  (base64, over the same SSH-stdin approach as `security_scan`) into a throwaway remote
  temp dir for the run, so it works even on sites `setup-monitoring.yml` hasn't
  provisioned yet.

More tools (PR creation, releases, image optimization, git/gh helpers) will follow the
same pattern. See the parent repo's `CLAUDE.md` and the relevant README in each
directory for the operations these will eventually wrap.

Two transports are implemented, both verified end-to-end (real MCP `initialize` +
`tools/call` round trip against the real scanner):

- **stdio** (default) — the client spawns the process/container directly and talks over
  stdin/stdout, killing it when it disconnects. This is a core MCP transport, not a
  Claude-specific one, so it works with any client that can spawn a local process —
  confirmed (2026-08-06, against each vendor's own docs) for:
  - **Claude Code/Desktop** — via `run.sh`, see "Register with Claude Code" below.
  - **Mistral Vibe CLI** — `config.toml`'s `[[mcp_servers]]`, `transport = "stdio"`,
    see "Register with Mistral Vibe" below.
  - **OpenAI Codex CLI** — `~/.codex/config.toml`'s `[mcp_servers.<name>]`, see
    "Register with OpenAI Codex CLI" below. (Note: this is the Codex *CLI* — OpenAI's
    server-side Responses API is remote-MCP-only and cannot spawn local processes at
    all, so stdio doesn't apply there.)

  Prefer stdio for any client running on the same machine — no token, no port, no
  process to remember to stop.
- **Streamable HTTP** — the server runs as a standing network service other MCP clients
  can connect to over a URL. Only needed when the client genuinely can't spawn a local
  process — a remote/cloud-hosted client, or multiple clients sharing one long-running
  server instance — set `MCP_TRANSPORT=http`. Not needed for a local Mistral Vibe CLI on
  the same machine; use stdio instead (see above).

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

## Quick check: `wp-ops mcp-register`

Before doing any of this by hand, run `wp-ops mcp-register`. It checks
`~/.claude.json`, `~/.vibe/config.toml`, and `~/.codex/config.toml` for an
existing wp-ops entry and, for whichever ones are missing it, prints the exact
block to paste — with the real path to `run.sh` on this machine already filled
in, so there's no `/absolute/path/to/wp-ops/...` placeholder to get wrong.
Read-only: it never writes to a config file itself.

`mcp-register` shipped in wp-ops 5.2.0. If the command isn't found, update the
CLI first:

```bash
brew upgrade --cask wp-ops   # Homebrew install
wp-ops --version             # confirm 5.2.0 or later
```

(Built from source instead? `git pull && go build -o wp-ops ./go`.)

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

## Register with Mistral Vibe

Vibe's CLI reads `[[mcp_servers]]` entries from a `config.toml` at two layers:

- **Project-level:** `./.vibe/config.toml` in the current working directory — only
  loaded when that directory is marked trusted.
- **User-level (global):** `~/.vibe/config.toml`.

**Register user-scoped (`~/.vibe/config.toml`) only — do not also add a copy to any
project's `.vibe/config.toml`:**

```toml
[[mcp_servers]]
name = "wp_ops"
transport = "stdio"
command = "/absolute/path/to/wp-ops/mcp-server/run.sh"
args = []
```

Tools show up prefixed with the `name` you chose, e.g. `wp_ops_wp_cli`,
`wp_ops_security_scan`, `wp_ops_schema_audit`. No `WP_OPS_MCP_TOKEN` or port needed —
stdio mode has no network listener, so there's nothing to secure at that layer.

**Requires Vibe ≥ 2.24.0.** Below that version, a trusted project-level `config.toml`
*replaces* the global config for `mcp_servers` instead of composing with it —
[mistralai/mistral-vibe#840](https://github.com/mistralai/mistral-vibe/issues/840) — so
the global entry above silently disappears (shows as "0 MCP servers" in Vibe's banner)
in any directory that has its own `.vibe/config.toml`, even if that file never mentions
`mcp_servers` at all. Run `vibe --version`; if it's older, `vibe --check-upgrade` before
registering anything.

Don't work around this on an old version by duplicating the block into a project's
`.vibe/config.toml` — that file is typically git-tracked, and doing so commits your
machine's absolute path into the repo (verified against a real case: an earlier
`imagewize.com/.vibe/config.toml` entry pointing at a since-nonexistent
`/Users/j/...` path, dead for everyone who isn't that original machine). Upgrade Vibe
instead; the global entry alone is then sufficient everywhere.

Verified against Mistral's own docs (2026-08-06) for schema/transport-name accuracy;
not yet verified end-to-end against a live Vibe install connecting to this server —
confirm the tool list appears and a read-only call (e.g. `wp option get siteurl`
through `wp_ops_wp_cli`) succeeds before relying on it.

## Register with OpenAI Codex CLI

Codex reads MCP servers from a `config.toml`, in this order (first match wins):

- **Project-level:** `.codex/config.toml` in the current working directory — only
  loaded when that directory is trusted.
- **User-level (global):** `~/.codex/config.toml`.

**Recommended: register user-scoped (`~/.codex/config.toml`)**, same reasoning as
Claude Code and Mistral Vibe above.

Codex's table syntax differs slightly from Mistral's (a keyed table per server, not an
array of tables), and it calls the environment-passthrough option `env_vars`:

```toml
[mcp_servers.wp_ops]
command = "/absolute/path/to/wp-ops/mcp-server/run.sh"
args = []
```

Tools show up prefixed with the server name, e.g. `wp_ops_wp_cli`. As with Mistral,
stdio mode needs no `WP_OPS_MCP_TOKEN` or port.

Verified against Codex's own docs (2026-08-06) for config schema; **this is the Codex
CLI specifically** — OpenAI's server-side Responses API only speaks remote MCP
(Streamable HTTP/SSE) and cannot spawn a local process at all, so none of the stdio
guidance here applies to it. Not yet verified end-to-end against a live Codex CLI
connecting to this server.

## Permissions (pre-approve read-only tools)

The read-only tools (`redirect_audit`, `schema_audit`, `security_scan`, `url_audit`,
`monitor`, and read-only `wp_cli` commands) are safe to run without confirmation —
`url_audit` only ever queries counts and, at most, a `--dry-run` search-replace preview
unless `confirm: true` is explicitly set. Pre-approve them in `~/.claude/settings.json`
to avoid repeated permission prompts:

```json
{
  "mcp": {
    "permissions": {
      "mcp__wp-ops__redirect_audit": { "allowed": true },
      "mcp__wp-ops__schema_audit": { "allowed": true },
      "mcp__wp-ops__security_scan": { "allowed": true },
      "mcp__wp-ops__url_audit": { "allowed": true },
      "mcp__wp-ops__monitor": { "allowed": true },
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

Skip this unless you have a client that genuinely can't spawn a local process — a
remote/cloud-hosted client, or multiple clients meant to share one long-running server
instance. A local Claude Code/Desktop, Mistral Vibe CLI, or OpenAI Codex CLI should use
stdio instead — see the "Register with ..." sections above.

For clients that connect over a URL instead of spawning a local process:

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
current docs for the exact syntax; this changes fast. (Mistral Vibe's schema for this
is `transport = "http"` or `"streamable-http"`, `url`, `headers = { Authorization =
"Bearer <token>" }` — verified against its docs 2026-08-06, but again, prefer stdio for
a local Vibe CLI; this section is for genuinely remote setups.) Not verified against a
specific Ollama-fronting framework's config format.

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
