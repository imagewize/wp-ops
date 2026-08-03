# MCP Server: Usage Recommendations and Roadmap

Recommendations for getting more out of the wp-ops MCP server (`mcp-server/`) across
all sites — example.com, other WordPress installs (Bedrock/Trellis or plain), and
non-WordPress sites — with a focus on saving time and tokens. Also covers the
longer-term question of tighter coupling with the Go CLI binary.

> **Status:** Up to date as of v3.24.0 (2026-08-03) — items 1-8 done. Verified
> 2026-08-03: item 1's "not registered user-scoped" observation was stale — it
> already was, see below.

## Current state

The server exposes five tools — `security_scan`, `db_backup`, `wp_cli`,
`redirect_audit`, `schema_audit` — backed by a Zod-validated site registry
(`config/sites.json`).

It's launched via the Go CLI (`wp-ops mcp-server dev` / `wp-ops mcp-server start` /
`wp-ops mcp-server run`, all discoverable in the Go binary's 67-command catalog),
but the Go CLI's role
stops at **launching the process** — the MCP server itself **bypasses the Go CLI**
and invokes scripts directly via Node.js `child_process.spawn`. This gives it
low-level control the Go CLI doesn't currently expose:

- **SSH streaming** — PHP scanner scripts are piped over SSH stdin, nothing is written to disk remotely
- **Trellis VM support** — commands targeting dev VMs use `trellis vm shell`
- **Custom binary paths** — non-standard PHP/WP-CLI paths for shared hosting (cPanel/Plesk)
- **Its own site registry** (`config/sites.json`), separate from the Go CLI's catalog

Observed setup gaps:

- ~~The server is registered only project-scoped...~~ **Stale as of 2026-08-03.**
  Re-checked directly: `~/.claude.json` has a top-level `mcpServers.wp-ops` entry
  (not nested under any of its 90 tracked `projects` entries), so it's already
  true user/global scope and available in every session, including seo-strategy
  and imagewize.com. No project anywhere has a `.mcp.json` that would shadow it.
  Unclear when this changed — item 1 below was probably actioned but the
  "Current state" section here never got updated to match.
- `config/sites.json` contains `aseonomics.com`, `imagewize.com`, and
  `demo.imagewize.com` (each with dev-via-Trellis-VM and prod-via-SSH entries) —
  ahead of where this doc's "only example.com" note said it was.
- Other candidate projects exist in `~/code`: `client` (plain vanilla
  WordPress, not Bedrock), `client.nl`, plus static/Jekyll sites
  (`wpvillain.github.io`, `school-practice`, `site.github.io`) where the
  two curl-based audit tools already work as-is.
- **New failure mode found 2026-08-03:** the registered `command` points at
  `mcp-server/dist/index.js`, a committed-but-gitignored build artifact. Editing
  `src/*.ts` does not update the running server — `npm run build` has to be run
  by hand, and nothing flags a stale build. Found this time because `src/server.ts`
  and `src/tools/wpCli.ts` were newer than `dist/index.js`, meaning the live
  registered server was missing the item 7-8 fixes (enum schemas, expanded
  read-only allowlist) despite this doc marking them ✅ done. Rebuilt via
  `npm run build` in `mcp-server/`. Any *already-running* Claude Code session
  still talks to the old in-memory process; only new sessions/reconnects pick up
  a rebuild.

  **Fixed same day (v3.25.0):** `mcp-server/package.json` gained a `prestart`
  script (`tsc`), and a new `mcp-server/run.sh` is now the registered launcher
  in `~/.claude.json` instead of a bare `node dist/index.js` — it rebuilds only
  when `src/` is newer than `dist/index.js`, sends build output to stderr, and
  `exec`s into `node dist/index.js` so stdout stays clean for the JSON-RPC
  stream. `npm start` alone was deliberately *not* used as the registered
  command: npm's own log lines can land on stdout ahead of the server's first
  message and corrupt stdio framing.

## Quick wins — no code changes

1. **Register the server user-scoped.** ✅ *Done and verified*
   `claude mcp add --scope user wp-ops ...` or add the `mcpServers` block to
   `~/.claude.json`. The registry is central, so the tools shouldn't only exist
   inside the example.com project. Any session — including in wp-ops itself —
   can then run audits or WP-CLI against any registered site.

   *Updated `mcp-server/README.md` to recommend user-scoped as the default.
   Re-verified 2026-08-03: `~/.claude.json`'s top-level `mcpServers.wp-ops` is
   live and unshadowed by any project-scoped `.mcp.json`. Rebuilt `dist/`
   (`npm run build`) since it was stale relative to `src/` — see the "New
   failure mode" note above.*

2. **Add more sites to `sites.json`.** ✅ *Template ready*
   Plain WordPress installs (e.g. `client`) work today via `localPath` —
   nothing in `wpCli.ts` assumes Bedrock; `--path` is arbitrary. Remote non-Trellis
   hosts work too as long as `wp` is on the remote PATH.
   
   *`config/sites.example.json` already includes `client.nl` (shared hosting with
   custom `wpBin`/`phpBin`) and `static-site` (URL-only) examples.*

3. **Mention the MCP tools in each site's CLAUDE.md.** ✅ *Template provided*
   Without that, Claude keeps reaching for raw `wp` / `trellis vm shell` bash
   commands — more permission prompts, more trial-and-error tokens. One line like
   "prefer the `wp-ops` MCP tools (`wp_cli`, `security_scan`, …) with site key
   `example.com`" changes the default behavior.
   
   *Added CLAUDE.md integration template to `mcp-server/README.md` Usage Tips.*

4. **Pre-approve the read-only tools** in `~/.claude/settings.json` permissions: ✅ *Documented*
   `mcp__wp-ops__redirect_audit`, `mcp__wp-ops__schema_audit`,
   `mcp__wp-ops__security_scan`, `mcp__wp-ops__wp_cli`. The write-guard already
   lives server-side (`confirm: true`), so prompting again client-side for reads is
   pure friction.
   
   *Added Permissions section to `mcp-server/README.md` with the exact config.*

## Server improvements for non-Bedrock / non-WordPress sites

5. **Per-entry `wpBin`/`phpBin` override in the registry schema.** ✅ *Already implemented*
   The security docs (`wp-cli/security/README.md`) call out cPanel/Plesk hosts
   where the binary is `/opt/plesk/php/8.2/bin/php` and WP-CLI may be
   `~/wp-cli.phar`.

   *`registry.ts`'s `envEntrySchema` already has `wpBin`/`phpBin`, and
   `resolveWpBin`/`resolvePhpBin` are threaded through `runLocal`/`runRemote`/`runVm`
   in `tools/wpCli.ts` — this landed in `c665424`, before this doc's items 1-4 pass.
   `config/sites.example.json`'s `client.nl` entry demonstrates it.*

6. **Add a `url` field per site/env; let audits accept `site`/`env`.** ✅ *Already implemented*
   `redirect_audit` and `schema_audit` are platform-agnostic (pure curl), making
   them the entry point for Jekyll and static sites.

   *`registry.ts`'s schema already has `url` and its `refine` accepts a URL-only
   entry (also from `c665424`). `server.ts`'s `redirect_audit`/`schema_audit` tools
   already accept `site`+`env` and resolve the URL from the registry entry, falling
   back to the raw `urls`/`siteUrl` params. `config/sites.example.json`'s
   `static-site` entry demonstrates a URL-only registration.*

## Token and time savings

7. **Put the site keys in the tool schema.** ✅ *Done*
   `site`/`env` are free-form `z.string()`, so a wrong guess costs a failed round
   trip (the error lists known sites, but that's a full extra tool call).

   *`server.ts`'s new `buildSiteEnvSchemas()` builds `z.enum(...)` for both `site`
   (from the registry's top-level keys) and `env` (the union of env keys across all
   sites) once at server start, and every tool's `site`/`env` params use it. Falls
   back to plain `z.string()` if the registry can't be loaded yet or is empty, so a
   fresh install without `sites.json` still starts. Trade-off: registry edits need a
   server restart, as expected for stdio.*

8. **Expand the read-only allowlist — every miss costs two tool calls.** ✅ *Done*
   `isReadOnlyWpCommand` only checked `args[1]`, so genuinely read-only commands
   like `wp cron event list` (`args[1] === "event"`), `wp db size`, `wp db tables`,
   `wp core verify-checksums`, `wp option pluck` all failed, got re-sent with
   `confirm: true`, and burned a round trip plus a user approval each time.

   *`tools/wpCli.ts`: `SAFE_READ_VERBS` gained `size`/`tables`/`verify-checksums`/`pluck`.
   For the `wp cron event list` shape — where the verb is the *third* token because
   the second names a sub-resource, not an action — a new `NESTED_RESOURCE_VERBS`
   allowlist (currently just `cron: [event, schedule]`) checks the third token
   instead. Deliberately not a blind "check args[1] OR args[2]": args[2] is often an
   arbitrary caller-supplied value (an option name, a post ID) that could
   coincidentally collide with a safe verb — e.g. `wp option update list <value>`
   must stay gated even though its third token is `list`.*

9. **Cap and compact tool output.**
   `wp_cli` returns stdout verbatim — `wp post list` on a big site can dump tens
   of KB straight into context. Truncate at ~10–20 KB with a "use
   `--format=count` / `--fields=` / `--posts_per_page`" hint in the truncation
   notice. Similarly, `schema_audit`'s default page list probes a dozen guessed
   paths and pages that 404 still produce output lines. A `summary`-only mode
   (counts + failures only) for both audits would cut typical results by more than
   half.

10. **Keep tool descriptions tight once user-scoped.**
    With user-scope registration, all five tool descriptions load into *every*
    session in every project. The `wp_cli` description especially is long; trim
    descriptions to 1–2 sentences and move usage detail into error messages
    (which only appear when needed) to save a fixed per-session tax.

## Highest-leverage new tool

11. **A `url_audit` tool for the dev-URL problem CLAUDE.md marks CRITICAL** —
    one call that runs the `%.test%` query against production, reports hits, and
    (with `confirm: true`) runs the `wp search-replace`. Today that workflow is
    two or three hand-composed `wp_cli` calls reconstructed from documentation
    each time; wrapping it makes the most error-prone post-migration step a
    single deterministic call. `db_pull` / `files_pull` wrappers (already planned
    in the mcp-server README) are the natural follow-ups.

## Suggested order of work

1. ✅ Items 1–4: config-only, doable immediately.
2. ✅ Items 5–6: opens up all non-Trellis and static sites (turned out to already be implemented).
3. ✅ Items 7–8: biggest recurring token savers.
4. Items 9–11: output compaction and new tools — remaining.

---

## Long-term: tighter Go CLI integration

The current split (Node.js MCP server + Go CLI) works and is well-tested. The
items above are the near-term priority — they're low/medium effort with clear,
immediate payoff. The options below are architectural and higher-effort; treat
them as background/opportunistic work, not queued backlog.

| Option | Description | Effort | Verdict |
|--------|-------------|--------|---------|
| **A — MCP calls Go CLI** | Shell out to `wp-ops` instead of calling scripts directly | Medium | Blocked until Go CLI supports SSH stdin streaming and Trellis VM shelling |
| **B — Native Go MCP** | Rewrite the MCP server in Go as `wp-ops mcp serve` | High | Architecturally cleanest long-term, but premature until the Go MCP SDK matures |
| **C — Keep current architecture** | Status quo | None | **Recommended for now** — already working, Node.js has mature MCP SDK support |

### Option A: MCP Server Calls Go CLI

```typescript
// Instead of:
spawn(phpBin, [scannerFile, scanPath])

// Use:
spawn("wp-ops", ["wp-cli/security/scanner-targeted", scanPath])
```

**Pros:** single execution path (Go CLI handles manifest, args, paths), less code
duplication, easier to maintain.

**Blockers:** Go CLI doesn't support stdin streaming for SSH (the MCP server's key
optimization) or Trellis VM execution. Would need new Go CLI flags: `--ssh-host`,
`--remote-path`, `--trellis-vm`, etc.

### Option B: Native Go MCP (long-term)

Rewrite the MCP server in Go as a subcommand: `wp-ops mcp serve --transport=stdio`
(or `--transport=http`), eliminating the separate Node.js process entirely.

```
go/mcp/
├── server.go           # MCP server lifecycle, transport setup
├── transport/
│   ├── stdio.go        # Stdio transport (stdin/stdout JSON-RPC)
│   └── http.go         # Streamable HTTP transport (MCP over HTTP)
├── tools/
│   ├── security_scan.go
│   ├── db_backup.go
│   ├── wp_cli.go
│   ├── redirect_audit.go
│   └── schema_audit.go
└── registry.go         # Site registry loading (replaces Node.js version)

cmd/mcp.go              # New command: wp-ops mcp serve
```

**Required Go packages:**

| Purpose | Package | Notes |
|---------|---------|-------|
| MCP SDK | [`go-mcp`](https://github.com/modelcontextprotocol/go-mcp) | Official Go SDK from MCP team |
| or | [`mcp-go`](https://github.com/gptme/mcp-go) | Alternative with good examples |
| JSON-RPC | `github.com/ybbus/jsonrpc/v3` | For stdio transport |
| HTTP Server | `net/http` (stdlib) | For Streamable HTTP transport |
| SSH | `golang.org/x/crypto/ssh` | For SSH streaming (replaces Node.js spawn) |
| subprocess | `os/exec` (stdlib) | For local script execution |

**Sketch — tool registration from the existing catalog:**

```go
func NewServer() *mcp.Server {
    s := mcp.NewServer("wp-ops", "0.1.0")
    for _, entry := range catalog.Entries {
        if shouldExposeAsTool(entry) {
            s.AddTool(mcp.Tool{
                Name:        entry.Key,
                Description: entry.Description,
                Handler:     makeToolHandler(entry),
            })
        }
    }
    return s
}

func makeToolHandler(entry catalog.Entry) mcp.ToolHandler {
    return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
        result, err := exec.Execute(entry, req.Arguments) // reuse existing Go CLI executor
        if err != nil {
            return nil, err
        }
        return &mcp.CallToolResult{Content: []mcp.Content{{Type: "text", Text: result.Output}}}, nil
    }
}
```

**SSH streaming equivalent** (replaces `spawn("ssh", ...)` + stdin write) using
`golang.org/x/crypto/ssh`:

```go
func runRemote(scannerSource, sshHost, phpBin, remotePath string) (string, error) {
    key, err := os.ReadFile(os.ExpandEnv("$HOME/.ssh/id_ed25519"))
    if err != nil {
        return "", err
    }
    signer, err := ssh.ParsePrivateKey(key)
    if err != nil {
        return "", err
    }
    config := &ssh.ClientConfig{
        User:            "web",
        Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
        HostKeyCallback: ssh.InsecureIgnoreHostKey(), // Or proper verification
    }
    conn, err := ssh.Dial("tcp", sshHost+":22", config)
    if err != nil {
        return "", err
    }
    defer conn.Close()

    session, err := conn.NewSession()
    if err != nil {
        return "", err
    }
    defer session.Close()

    stdinPipe, err := session.StdinPipe()
    if err != nil {
        return "", err
    }
    var stdoutBuf, stderrBuf bytes.Buffer
    session.Stdout = &stdoutBuf
    session.Stderr = &stderrBuf

    cmd := fmt.Sprintf("%s - %s", phpBin, remotePath)
    if err := session.Start(cmd); err != nil {
        return "", err
    }
    if _, err := io.Copy(stdinPipe, bytes.NewReader([]byte(scannerSource))); err != nil {
        return "", err
    }
    stdinPipe.Close()
    if err := session.Wait(); err != nil {
        return "", err
    }
    return stdoutBuf.String(), nil
}
```

**Migration path (if pursued):**

| Phase | Task | Effort |
|-------|------|--------|
| 1 | Add `go-mcp` dependency, create `go/mcp/` package scaffold | Low |
| 2 | Implement stdio transport with basic tool registration | Medium |
| 3 | Port site registry to Go | Medium |
| 4 | Port one tool (e.g., `redirect_audit`) end-to-end | Medium |
| 5 | Port remaining tools | Medium |
| 6 | Implement HTTP transport | Medium |
| 7 | Add SSH streaming support to Go CLI executors | High |
| 8 | Add Trellis VM support to Go CLI | High |
| 9 | Test all tools end-to-end | Medium |
| 10 | Deprecate Node.js MCP server | Low |

**Comparison:**

| Aspect | Node.js (current) | Go (proposed) |
|--------|-------------------|--------------|
| MCP SDK maturity | Excellent (official SDK) | Good (go-mcp, mcp-go) |
| Dependency | Node.js runtime | None (compiled binary) |
| Docker image | ~200MB (Node) | ~10MB (Go static) |
| Startup time | ~500ms (Node init) | ~10ms (Go) |

**When to pursue:** the Go MCP SDK reaches v1.0 stability, or SSH/VM support is
being added to the Go CLI anyway for other reasons, or the Node.js runtime
dependency itself becomes a distribution blocker. Until then, Option C stands.

## Key Files

| File | Purpose |
|------|---------|
| `mcp-server/dev.sh` | Development launcher (calls `npm run dev`) |
| `mcp-server/start.sh` | Production launcher (calls `npm run build && npm start`) |
| `mcp-server/src/index.ts` | MCP server entry point, transport selection |
| `mcp-server/src/server.ts` | MCP server setup, tool registration |
| `mcp-server/src/registry.ts` | Site registry loading and validation |
| `mcp-server/src/tools/*.ts` | Individual tool implementations |
| `mcp-server/config/sites.json` | Site registry (gitignored) |
| `mcp-server/config/sites.example.json` | Site registry template |

## Verification Checklist

- [x] MCP server commands are in Go CLI catalog: `wp-ops mcp-server --help`
- [ ] Development mode works: `wp-ops mcp-server dev`
- [x] Production build works: `npm run build` in mcp-server/ (verified 2026-08-03)
- [x] `dist/` is not stale relative to `src/` — `find src -newer dist/index.js`
      should print nothing; re-run `npm run build` if it does
- [x] Site registry is properly configured: `config/sites.json` has
      `aseonomics.com`, `imagewize.com`, `demo.imagewize.com` (verified 2026-08-03)
- [x] MCP client can connect and list tools — confirmed via `~/.claude.json`
      top-level `mcpServers.wp-ops` (user scope, verified 2026-08-03)
- [ ] Each of the 5 tools can be invoked successfully

## See Also

- [MCP Server README](../mcp-server/README.md) — Full setup, configuration, and usage
- [CLI UX Plan](./cli-ux-plan.md) — Overall CLI architecture and roadmap
- [m3-go-skeleton.md](./m3-go-skeleton.md) — Go CLI implementation details
- [m4-go-cli-completion.md](./m4-go-cli-completion.md) — Go CLI completion and distribution
