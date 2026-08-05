# wp-ops CLI vs trellis-cli: entry point and command surface

Why `trellis` with no arguments stays in your terminal and looks organized,
what `wp-ops` does instead, and which of those differences are actually worth
closing.

Compared against `trellis-cli` at `/Users/jasperfrumau/code/trellis-cli`
(module `github.com/roots/trellis-cli`, go 1.25) and this repo's Go CLI under
`go/` (module `github.com/imagewize/wp-ops`, go 1.26.4).

> A second comparison document, [`cli-comparison.md`](cli-comparison.md),
> was written by Mistral. Section 8 below reviews it — the short version is
> that its architecture summary is sound but its central recommendation
> proposes a feature the CLI already ships.

## 1. The one difference that produced the screenshots

`trellis` with no arguments prints help to stdout and exits. `wp-ops` with no
arguments takes over the screen.

```go
// go/cmd/root.go:65-74
if len(args) == 0 {
    if detect.IsTerminal(os.Stdin) && detect.IsTerminal(os.Stdout) {
        os.Exit(runInteractive(c))   // Bubble Tea picker
    }
    printCategorizedList(c)          // plain text, piped/redirected only
}
```

```go
// go/internal/ui/picker.go:18
p := tea.NewProgram(m, tea.WithAltScreen())
```

`tea.WithAltScreen()` switches the terminal to its alternate screen buffer.
That is the entire reason the picker "feels like a separate prompt": the
alternate buffer has no scrollback of its own, and everything drawn in it is
discarded when the program exits. Nothing about Bubble Tea requires this —
without the option the same picker renders inline, in the primary buffer,
like `fzf --height` or `git rebase -i`'s status output.

trellis-cli has no equivalent, because it has no TUI at all. `main.go:247`
calls `c.Run()`; with no arguments `hashicorp/cli` falls through to its
`HelpFunc` (`cli.BasicHelpFunc("trellis")`, wrapped in
`deprecatedCommandHelpFunc` at `main.go:230`) and writes the command table to
the UI writer, which is plain `os.Stdout` (`main.go:30-37`).

**Worth being precise about:** the alternate screen is the only reason bare
`wp-ops` behaves differently. `wp-ops --help` already prints exactly the
trellis-style inline listing (`root.go:86`), and so does any non-TTY
invocation.

## 2. Verified side-by-side

| | wp-ops | trellis-cli |
|---|---|---|
| CLI framework | `spf13/cobra` v1.10.2 | `hashicorp/cli` v1.1.7 |
| Bare invocation (TTY) | Full-screen Bubble Tea picker | Command table, inline |
| Bare invocation (piped) | Category summary text | Same command table |
| `--help` | Category summary text | Same command table |
| Command count | 74 entries (`go/internal/catalog/catalog.json`) | 46 registered factories — 23 top-level, 23 namespaced subcommands |
| Grouping | 12 display categories, drilled into via `wp-ops <category>` | Noun namespaces (`db`, `vm`, `vault`, `server`, `key`, `galaxy`, `valet`, `xdebug-tunnel`) |
| Command source | Generated at build time (`go:generate` → `catalog.json`, `//go:embed`) | Hand-written `map[string]cli.CommandFactory` in `main.go:61-227` |
| Per-command help | Rendered from manifest metadata (`go/internal/exec/help.go`) | Hand-written `Help()` string per command (e.g. `cmd/deploy.go:129`) |
| Flag parsing | None — `DisableFlagParsing`, argv passes through to the script | Stdlib `flag.FlagSet` per command (`cmd/deploy.go:30-34`) |
| Completions | Cobra + custom `ValidArgsFunction` (`go/cmd/dispatch.go`) | `posener/complete` via `AutocompleteArgs()`/`AutocompleteFlags()` |
| Interactive prompts | Bubble Tea field prompts inside the picker (`go/internal/ui/fields.go`) | `manifoldco/promptui`, inline, in 9 commands (`vault edit`, `key generate`, `server create`, `new`, …) |
| Styling | `charmbracelet/lipgloss` | `fatih/color` + `theckman/yacspin` spinner (`cmd/spinner.go`) |
| Extensibility | None | `trellis-*` executables on `PATH` auto-register as commands (`plugin/`, kubectl-style) |
| Update check | None | Background goroutine, message printed after the command runs (`main.go:47-57`, `252-263`) |

Two rows deserve emphasis because they cut against the usual framing:

- **trellis-cli is not "non-interactive".** Nine of its commands prompt.
  The difference is that every prompt is a line in the normal buffer, not a
  screen.
- **wp-ops's help is not thinner than trellis's.** It is generated rather
  than hand-written, but `wp-ops db-backup --help` produces usage,
  arguments, flags, requirements, examples, docs link, and script path — more
  structured than most of trellis's prose help blocks.

## 3. What actually makes trellis look organized

Three properties, none of which is "it avoids a TUI":

1. **Two-level noun namespaces.** `db`, `key`, `server`, `vault`, `vm`,
   `galaxy`, `valet`, `xdebug-tunnel` are `NamespaceCommand` values whose
   `Run()` returns `cli.RunResultHelp` (`cmd/namespace.go:12`) — they exist
   only to hold subcommands and to keep the top-level list at 23 lines.
   46 commands present as 23.
2. **One screen, aligned, alphabetical.** `cli.BasicHelpFunc` pads every name
   to a fixed column and prints one `Synopsis()` per line. Deprecated
   commands are segregated into their own block at the bottom
   (`help.go:12-47`), so `droplet` is visible without polluting the main list.
3. **The output persists.** It scrolls into your buffer, so you can read the
   list while typing the command it told you about. A full-screen picker has
   to be re-entered to be re-read.

`wp-ops --help` already does (2) and (3), and does (1) via display categories.
Compare — this is the current output, 12 lines of commands for 74 commands:

```
wp-ops — WordPress Operations Tools

  Monitoring             (17)  Log monitoring, uptime checks, and traffic analysis
  Backup                 (10)  Database and file backups — Ansible and shell
  ...
Run 'wp-ops <category>' to see a category's commands (e.g. 'wp-ops backup')
```

That is denser than trellis's own landing page. The problem is not the text
view; it is that the text view is not what a bare `wp-ops` shows.

## 4. Where wp-ops is genuinely different by design

These are real divergences, not gaps to close blindly:

- **Generated vs hand-registered catalog.** wp-ops discovers commands by
  walking the repo at build time (`go/internal/catalog/gen/main.go`) and
  embeds the result. Adding a script with a manifest header gets you a
  command for free; trellis-cli requires editing `main.go`. This is the
  right trade for a repo whose commands *are* the scripts.
- **Pass-through argv.** Every wp-ops command sets `DisableFlagParsing`
  because the underlying shell/Ansible/PHP script owns its own flag grammar
  (`go/cmd/dispatch.go:36`, `51`). trellis-cli owns its flags, so it can
  validate them and offer flag completion. Neither is wrong; wp-ops is a
  dispatcher, trellis-cli is an application.
- **Categories are domains, not namespaces.** `wp-ops backup` is a view onto
  commands scattered across `scripts/backup/`, `trellis/backup/`. trellis's
  `db` is a real prefix of the command name. This is why wp-ops also supports
  a bare basename with ambiguity resolution (`root.go:97-108`), which trellis
  has no need for.

## 5. Two small rough edges found while comparing

Both are cheap to fix and both show up next to trellis's equivalents:

1. **Help echoes the internal key, not what you typed.**
   `wp-ops db-backup --help` prints `Usage: wp-ops scripts/backup/db-backup
   [args...]`. trellis prints `Usage: trellis deploy [options] ENVIRONMENT
   [SITE]`. Two issues: the full key is shown where the user typed a
   basename, and `[args...]` is a placeholder where the manifest already
   knows the real positional names (they are listed three lines below).
   Rendering `Usage: wp-ops db-backup [site-name] [environment] [flags]` from
   the same manifest data would close the gap entirely
   (`go/internal/exec/help.go:48`).
2. **No deprecation channel.** trellis segregates deprecated commands in help
   rather than deleting them. wp-ops has hidden directory aliases
   (`wp-ops trellis <playbook>`, `dispatch.go:71-82`) that are invisible
   rather than labelled — a `@deprecated` manifest directive plus a footer
   block would make the migration path visible.

## 6. Options for the entry point

Ordered by how much they change.

### Option 1 — Drop the alternate screen (recommended)

Delete `tea.WithAltScreen()` from `picker.go:18`. The picker then renders
inline: it draws in the primary buffer, scrollback is preserved, and the
final frame stays visible after selection. You keep filtering, the preview
pane, and guided argument prompts; you lose the screen takeover.

One caveat: an inline Bubble Tea program still redraws its own frame region,
so a picker taller than the window will clip rather than scroll. The picker's
category stage is 14 lines and the browse stage already windows its list
(`model.go`'s `viewBrowse`), so this is a non-issue in practice — but it is
worth capping the browse window height explicitly if this is done.

Effort: one line, plus a manual pass over the three stages.

### Option 2 — Make text the default, picker opt-in

Bare `wp-ops` prints `printCategorizedList` (identical to `--help` and to the
piped path today); the picker moves behind `wp-ops menu` or `wp-ops -i`.

This is the most trellis-faithful outcome and removes the TTY branch in
`rootRunE` entirely. It is a behavior change for anyone who types `wp-ops`
expecting the picker, and it makes the picker's discoverability work only
pay off for people who know to ask for it.

Effort: small. `root.go:65-74` plus a new subcommand and README/completion
updates.

### Option 3 — Both: inline picker, text on `--help`, `--no-picker` escape hatch

Option 1 plus an explicit opt-out flag and/or `WP_OPS_NO_PICKER` env var for
scripts and constrained terminals.

The env var is largely redundant — the TTY check at `root.go:70` already
covers pipes, redirects, and CI — but an explicit flag is useful for
"I want the list, in a terminal, right now" without remembering that `--help`
is the way to get it.

**Recommendation: Option 1, and consider Option 3's flag as a follow-up.**
The user-visible complaint is the screen takeover and the lost scrollback,
not the picker itself. Option 1 fixes exactly that and costs one line. Option
2 throws away the picker's real value — 74 commands is well past what an
alphabetical list serves — to fix a problem that is really about terminal
buffer management. If, after living with an inline picker for a while, the
text view still feels better, Option 2 remains available and is no harder
then than now.

## 7. What not to copy

- **Static command registration.** trellis's `map[string]cli.CommandFactory`
  is 170 lines of boilerplate. The generated catalog is strictly better for
  this repo.
- **Per-command flag parsing.** Would mean re-declaring every script's flags
  in Go and keeping them in sync. The manifest already documents them; the
  script already parses them.
- **`hashicorp/cli`.** Cobra is the more actively maintained choice and the
  completion machinery already depends on it. The framework is not what
  produced the difference in the screenshots.

Worth copying eventually, on the other hand: the plugin discovery model
(`plugin/finder.go` — any `wp-ops-*` executable on `PATH` becomes a command)
if per-project commands ever become a need.

## 8. Notes on `cli-comparison.md` (the Mistral document)

The architectural read is accurate. `tea.WithAltScreen()` is correctly
identified as the mechanism, the framework comparison is right, and the
strengths/weaknesses tables are fair. Specific corrections:

**Its main recommendation already ships.** Section 8's Option A proposes
adding a `--help` that prints simple help instead of the picker, with sample
code adding a `noPickerFlag`. `root.go:85-86` already handles `--help`/`-h`
by calling `printCategorizedList`, and `root.go:70` already falls back to the
same output when stdin or stdout is not a TTY. Its Option C ("detect and
adapt — not a TTY") is likewise already implemented at that same line. Only
Options B and D describe work that does not exist yet.

**Its Option A code would break the CLI.** The snippet calls
`rootCmd.Flags().BoolVar(...)` and then reads `noPickerFlag` in `rootRunE`.
Root sets `DisableFlagParsing: true` (`root.go:53`) precisely so that
unrecognized flags destined for the underlying script are not intercepted, so
a registered flag would never be populated. The comment block at
`root.go:45-52` explains why. This is the kind of detail worth catching
before the suggestion reaches a branch.

**Counts and dependencies are off in places.** "hundreds of commands" and
"70+" appear for wp-ops, where the catalog holds exactly 74; trellis-cli is
described as "~40 top-level commands" where it is 23 top-level and 46 total.
Its dependency list for trellis-cli names only `hashicorp/cli` and
`fatih/color`, omitting `promptui`, `yacspin`, `posener/complete`, and
`go-isatty` — the omission matters, because `promptui` is what disproves the
document's framing of trellis-cli as the non-interactive option.

**"Built at compile time" and "auto-generated at startup" both appear.**
Sections 4 and 9 contradict each other. Compile time is correct:
`//go:generate` writes `catalog.json`, `//go:embed` bakes it into the binary,
and `catalog.go:1-4` states that no filesystem scan happens at runtime.

**It treats the trade-off as picker-vs-text.** The alternate screen and the
picker are separable — that is the whole content of Option 1 above, and it
does not appear anywhere in the document's four options. Framing the choice
as "keep the TUI or match trellis" makes the cheapest fix invisible.

**Missing context.** [`cli-ux-plan.md`](cli-ux-plan.md) Phase F already
analysed this exact question in 2026-08, explicitly benchmarking against
`trellis`'s two-level structure, and shipped three of its four options in
PR #146 — including the category-select stage visible in the screenshot.
A comparison written without that history re-proposes work already done.
