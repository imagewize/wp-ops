# Using the wp-ops CLI

Reference for how the `wp-ops` binary organises, finds and completes commands. For
install and the everyday commands, see the [README](../../README.md#wp-ops-cli).

## Categories and platforms

Categories group by **domain**, not by directory: `wp-ops backup` lists all ten
backup commands whether they're Ansible playbooks under `trellis/` or shell scripts
under `scripts/`. The directory names still work as aliases (`wp-ops trellis
database-backup`), they're just no longer how the catalog presents itself.

Every command also carries a **platform** — `trellis` (needs a Trellis project),
`wordpress` (any WP install: Valet, Herd, cPanel, Bedrock, Trellis), or `any` (no
WordPress involved). `wp-ops search` badges each result with it, and
`wp-ops list --platform <value>` filters to what will actually run against the site
in front of you. `trellis` and `wordpress` both include the `any` commands, since
an image converter or a release script runs fine wherever you are; `--platform any`
is the one that stays exact, for "what needs no WordPress at all".

The scripts, playbooks, and guides are embedded in the binary, so once it's on your
PATH nothing else needs to stay around — you can delete the clone after building.

## Interactive picker

`wp-ops` with no arguments opens an interactive picker: categories first, then a
fuzzy-filterable command list, then the chosen command's full help (usage,
requirements, examples, args) printed above its argument prompts — no `fzf`
dependency. Start typing on the category screen to skip straight to a search across
every command. It renders inline rather than taking over the screen, so earlier output
stays visible above it and the last frame stays in your scrollback after it exits.

## Doctor

Run `wp-ops doctor` first — it reports which of the external tools these scripts rely
on (WP-CLI, Ansible, ImageMagick, `gh`, `cwebp`, Node, …) are actually installed, so
you find out before a command fails partway through.

## Shell completion

`wp-ops init` installs `wp-ops <TAB>` completion for zsh, bash, or fish, auto-detected
from `$SHELL`. Worth running right after install — the Homebrew cask this ships as
doesn't wire up completions on its own the way a Homebrew formula would.

Completion goes past the command name into its arguments, off the same manifest that
renders `--help`: `wp-ops db-pull <TAB>` offers the site names from the Trellis
project you're standing in, `wp-ops db-pull example.com <TAB>` offers
`production staging`, an argument that takes a path falls back to ordinary filename
completion, and anything else prints a one-line hint saying what the argument is.
Typing a dash offers the command's own flags.

## Searching the guides

A good deal of what this repo knows is written down rather than scripted, so
`wp-ops docs` searches the prose the way `wp-ops search` searches the catalog:

```bash
wp-ops docs                  # list every guide
wp-ops docs "search-replace" # show matching lines, grouped by document
wp-ops docs oom -w           # whole words only (so "oom" skips "server room")
wp-ops docs oom -l           # paths only, for piping: wp-ops docs oom -l | xargs $EDITOR
```

When `wp-ops search` finds no command for a term, it checks the documentation and
points you there.

`docs/nginx/`, `docs/troubleshooting/`, and `docs/bedrock/` hold guides and config
templates rather than runnable scripts, so they carry no commands and no CLI
category — reach them through `wp-ops docs`.

Every catalog entry is something that runs. Copy-paste-into-a-theme reference
material — WP-CLI guides and the speed-optimization notes — lives under
`docs/wordpress-utilities/` instead. To pull one into a project, `wp-ops docs -l
<term>` gives you the path:

```bash
cat "$(wp-ops docs -l wp-template | head -1)"
```

## Where commands run

Everything runs on your own machine, including the commands that touch a server —
Ansible playbooks, `server-monitor`, and `db-backup` all reach out over SSH
from here. The exception is the log monitors, which execute on the host; they are
tagged `(server)` in listings and search, and `wp-ops --json` reports the split as a
`runs_on` field. See [Running the monitors on the server](../../trellis/monitoring/README.md#running-the-monitors-from-wp-ops).
