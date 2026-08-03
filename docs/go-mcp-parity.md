# ADR: Bash CLI, Go CLI, and MCP Server Coexistence

> **Status:** Accepted — 2026-08-03
> **Supersedes:** an earlier draft of this file that proposed an `@key` manifest
> directive for short command names. That proposal was withdrawn — the problem it
> solved does not exist (see [wp-ops-recommendations.md](wp-ops-recommendations.md),
> "The verbose-path premise is false").

## Context

wp-ops ships three interfaces over the same scripts:

| Interface | Entry point | Consumer |
|-----------|-------------|----------|
| Bash CLI | `./wp-ops` | humans, and the reference implementation |
| Go CLI | `go/wp-ops` | humans wanting a single compiled binary |
| MCP server | `mcp-server/` (Node.js) | AI agents |

The recurring question is whether these should converge — one binary, one command
namespace, one naming convention.

## Decision

**Keep the three interfaces separate. The scripts are the single source of truth.**

Specifically:

1. **wp-ops works fully with or without the MCP server.** Nothing in the CLI path
   depends on the MCP server running. This is a hard constraint, not a preference.

2. **Both CLIs share one command namespace.** A command key is its repo-relative
   path minus extension (`scripts/backup/db-backup`), and both CLIs additionally
   resolve a bare basename across the whole catalog with ambiguity detection —
   bash at `wp-ops:2262-2281` (`find_commands_by_basename`), Go at
   `go/cmd/root.go:95-104` (`catalog.FindByBasename`). `wp-ops db-backup` and
   `wp-ops scripts/backup/db-backup` both work in both CLIs, identically.

3. **The MCP server keeps its own naming and its own registry.** Tools are
   snake_case (`db_backup`, `security_scan`) and resolve sites through
   `mcp-server/config/sites.json`, not the command catalog. These are different
   namespaces for different consumers, and that is fine:

   | Interface | Convention | Example |
   |-----------|------------|---------|
   | Bash CLI | hyphen-case path/basename | `wp-ops db-backup example.com production` |
   | Go CLI | hyphen-case path/basename | `wp-ops db-backup example.com production` |
   | MCP | snake_case tool name | tool `db_backup`, `{site, env}` |

4. **The Go CLI is verified against bash, not assumed equivalent.**
   `go/scripts/parity-check.sh` diffs `--json` field-for-field. Any change to bash
   command discovery must keep that green or land in both CLIs at once.

## Consequences

- A new capability lands as a **script** first. Both CLIs pick it up from the
  catalog automatically; the MCP server gets a tool only if agent access adds
  something (see the MCP design principles in
  [mcp-server-recommendations.md](mcp-server-recommendations.md)).
- Directive parsing is duplicated (bash `load_manifest`, Go
  `internal/manifest`). Go silently skips directives it does not handle
  (`manifest.go:179`), so a bash-only directive **degrades quietly rather than
  failing the build** — which means any new directive must land in both parsers in
  the same change, or the two CLIs diverge with nothing to catch it.
- Three languages to maintain. Accepted: each earns its place — bash needs no
  toolchain, Go ships one binary with completions, Node has the mature MCP SDK.

## What would change this decision

Consolidating the MCP server into the Go binary (`wp-ops mcp serve`) is tracked as
Option B in [mcp-server-recommendations.md](mcp-server-recommendations.md#long-term-tighter-go-cli-integration).
It stays blocked on the Go MCP SDK maturing **and** the Go CLI gaining SSH stdin
streaming and Trellis VM shelling — capabilities the MCP server has today and the
Go CLI does not. Not queued work.

## See Also

- [mcp-server-recommendations.md](mcp-server-recommendations.md) — MCP roadmap and the consolidation options table
- [wp-ops-recommendations.md](wp-ops-recommendations.md) — actual gaps in the toolset
- [cli-ux-plan.md](cli-ux-plan.md) — CLI architecture and resolution grammar
- [m3-go-skeleton.md](m3-go-skeleton.md) — Go CLI implementation
