# MCP Server: Usage Recommendations and Roadmap

Recommendations for getting more out of the wp-ops MCP server (`mcp-server/`) across
all sites — example.com, other WordPress installs (Bedrock/Trellis or plain), and
non-WordPress sites — with a focus on saving time and tokens.

## Current state (as of the `add/mcp-server` branch)

The server exposes five tools — `security_scan`, `db_backup`, `wp_cli`,
`redirect_audit`, `schema_audit` — backed by a Zod-validated site registry
(`config/sites.json`).

Observed setup gaps:

- The server is registered **only project-scoped** in `example.com/.mcp.json`.
  It is not registered user-scoped (`~/.claude.json` has no `mcpServers`), and not
  even in the wp-ops project itself.
- `config/sites.json` contains **only example.com**, even though the registry and
  every tool are designed to be multi-site.
- Other candidate projects exist in `~/code`: `client` (plain vanilla
  WordPress, not Bedrock), `client.nl`, plus static/Jekyll sites
  (`wpvillain.github.io`, `school-practice`, `site.github.io`) where the
  two curl-based audit tools already work as-is.

## Quick wins — no code changes

1. **Register the server user-scoped.**
   `claude mcp add --scope user wp-ops ...` or add the `mcpServers` block to
   `~/.claude.json`. The registry is central, so the tools shouldn't only exist
   inside the example.com project. Any session — including in wp-ops itself —
   can then run audits or WP-CLI against any registered site.

2. **Add more sites to `sites.json`.**
   Plain WordPress installs (e.g. `client`) work today via `localPath` —
   nothing in `wpCli.ts` assumes Bedrock; `--path` is arbitrary. Remote non-Trellis
   hosts work too as long as `wp` is on the remote PATH.

3. **Mention the MCP tools in each site's CLAUDE.md.**
   Without that, Claude keeps reaching for raw `wp` / `trellis vm shell` bash
   commands — more permission prompts, more trial-and-error tokens. One line like
   "prefer the `wp-ops` MCP tools (`wp_cli`, `security_scan`, …) with site key
   `example.com`" changes the default behavior.

4. **Pre-approve the read-only tools** in `~/.claude/settings.json` permissions:
   `mcp__wp-ops__redirect_audit`, `mcp__wp-ops__schema_audit`,
   `mcp__wp-ops__security_scan`, `mcp__wp-ops__wp_cli`. The write-guard already
   lives server-side (`confirm: true`), so prompting again client-side for reads is
   pure friction.

## Server improvements for non-Bedrock / non-WordPress sites

5. **Per-entry `wpBin`/`phpBin` override in the registry schema.**
   The security docs (`wp-cli/security/README.md`) call out cPanel/Plesk hosts
   where the binary is `/opt/plesk/php/8.2/bin/php` and WP-CLI may be
   `~/wp-cli.phar`. Right now `runRemote` hardcodes `wp`, so shared-hosting sites
   can't be registered. This is the single change that opens the MCP up to every
   non-Trellis client site.

6. **Add a `url` field per site/env; let audits accept `site`/`env`.**
   `redirect_audit` and `schema_audit` are platform-agnostic (pure curl), making
   them the entry point for Jekyll and static sites — but today full URLs must be
   retyped. With `"url": "https://client.nl"` in the registry, "run a
   redirect audit on client production" becomes one unambiguous call. Static
   sites would register with *only* a `url` (the schema's refine currently requires
   a path/host — relax it for URL-only entries).

## Token and time savings

7. **Put the site keys in the tool schema.**
   `site`/`env` are free-form `z.string()`, so a wrong guess costs a failed round
   trip (the error lists known sites, but that's a full extra tool call). Since
   `loadRegistry()` is cheap, build the schema at server start with
   `z.enum(Object.keys(registry))` — valid keys land in the tool definition the
   model sees, and mistakes drop to near zero. Trade-off: registry edits need a
   server restart, which is already true in practice for stdio.

8. **Expand the read-only allowlist — every miss costs two tool calls.**
   `isReadOnlyWpCommand` only checks `args[1]`, so genuinely read-only commands
   like `wp cron event list` (`args[1] === "event"`), `wp config get`,
   `wp db size`, `wp db tables`, `wp core verify-checksums`, `wp option pluck`
   all fail, get re-sent with `confirm: true`, and burn a round trip plus a user
   approval each time. Either check the verb at position 1 *or* 2, or allowlist
   known read-only `command + subcommand` pairs.

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

1. Items 1–4: config-only, doable immediately.
2. Items 5–6: opens up all non-Trellis and static sites.
3. Items 7–8: biggest recurring token savers.
4. Items 9–11: output compaction and new tools.
