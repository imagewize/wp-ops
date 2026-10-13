# wp-ops as a trellis-cli plugin

The Homebrew cask installs the same binary under a second name, `trellis-ops`,
which [trellis-cli](https://github.com/roots/trellis-cli) picks up as a plugin —
it scans `$PATH` for `trellis-*` executables and turns each into a subcommand. So
everything in the wp-ops catalog is also reachable from inside the tool you already
have open:

```bash
trellis ops                              # Trellis-relevant categories
trellis ops backup database-pull         # same as: wp-ops backup database-pull
trellis ops search backup
```

`trellis ops` scopes its **listing** to the commands tagged `@platform trellis`;
run plain `wp-ops` for the full catalog. Running a command is never scoped — name
any command and it works. `wp-ops list --platform trellis` (equivalently,
`trellis ops`) is the always-current, grouped-and-counted listing; a hand-copied
table would just be one more place for the catalog to drift out of sync.

Unlike core `trellis` subcommands, a plugin doesn't need you to be inside a Trellis
project — trellis-cli registers plugins from `$PATH` before it resolves a project at
all, so `trellis ops doctor` runs from anywhere while `trellis info` refuses. The
Ansible commands do still need a project, but they always did: wp-ops locates it
itself by walking up from your current directory, exactly as under bare `wp-ops`.

Requires trellis-cli new enough to have plugin support (v1.19.0 or later) and the
default `load_plugins: true`. If you built from source instead of installing the
cask, make the alias yourself:

```bash
ln -s "$(command -v wp-ops)" /usr/local/bin/trellis-ops
```

## Project directories

Two categories resolve their project directory from an environment variable — but you
don't need to export it by hand if you're standing inside the project: wp-ops detects
it by walking up from your current directory and asks before using what it finds.
Setting the variable explicitly is only required when you're running from elsewhere
(e.g. from this repo's own directory) or non-interactively (CI, cron), where there's
no prompt to confirm a detected guess:

```bash
# Ansible playbooks (wp-ops trellis <playbook>) need a Trellis project's ansible.cfg/inventory/group_vars
export TRELLIS_DIR=/path/to/your/trellis
wp-ops trellis database-backup -e site=example.com -e env=production
trellis ops trellis database-backup -e site=example.com -e env=production   # identical

# WP-CLI scripts (wp-ops wp-cli <script>) need a real WordPress/Bedrock install
export WP_SITE_DIR=/path/to/your/bedrock-site
wp-ops wp-cli scanner-wrapper
wp-ops wp-cli-pattern-validate web/app/themes/your-theme/patterns/ --fix
```

Detection deliberately only matches a project you're actually standing inside, so an
unrelated Trellis checkout sitting next to your current repo won't be picked up.
