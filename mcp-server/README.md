# wp-ops MCP server

Exposes wp-ops operations as [MCP](https://modelcontextprotocol.io) tools, so Claude
(and other MCP-compatible clients) can call them directly instead of you running the
underlying scripts by hand.

## Status

Scaffold — one tool implemented so far:

- **`security_scan`** — runs `wp-cli/security/scanner-targeted.php` / `scanner-general.php`
  against a registered site/environment. For remote environments it streams the scanner
  source over SSH stdin (`php - <path>`), so nothing is ever written to disk on the
  remote host — no `scp` + forget-to-delete step.

More tools (backups, PR creation, releases, image optimization) will follow the same
pattern. See the parent repo's `CLAUDE.md` and the relevant README in each directory
for the operations these will eventually wrap.

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

Add to your `.mcp.json` (project-scoped) or `~/.claude.json` (user-scoped):

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

Run it, mounting your site registry and SSH identity (needed for staging/production scans):

```bash
docker run -i --rm \
  -v ~/code/wp-ops/mcp-server/config/sites.json:/config/sites.json:ro \
  -v ~/.ssh:/root/.ssh:ro \
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
        "wp-ops-mcp-server"
      ]
    }
  }
}
```

This transport is still stdio (`-i` keeps stdin open, the client pipes JSON-RPC through
it) — it just runs inside a container instead of directly on your host, so you get a
fixed Node/PHP/openssh toolchain regardless of what's installed locally. Not yet
build-tested with a real `docker build` in this session (no Docker CLI available here) —
verify the build once you have Docker locally before relying on it.

To run the container in HTTP mode instead, publish the port and pass the transport env vars:

```bash
docker run --rm \
  -p 127.0.0.1:3000:3000 \
  -e MCP_TRANSPORT=http \
  -e WP_OPS_MCP_TOKEN="$(openssl rand -hex 32)" \
  -v ~/code/wp-ops/mcp-server/config/sites.json:/config/sites.json:ro \
  -v ~/.ssh:/root/.ssh:ro \
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
