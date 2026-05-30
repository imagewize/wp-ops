# Bedrock WP-CLI Configuration

Standard `wp-cli.yml` for a [Bedrock](https://roots.io/bedrock/) site plus a custom
`wp pattern validate` command for keeping block pattern files in canonical form.

Place both files in your **Bedrock site root** (the directory that contains `composer.json`).

---

## `wp-cli.yml`

```yaml
path: web/wp
server:
  docroot: web
require:
  - wp-cli-pattern-validate.php
```

| Key | Purpose |
|-----|---------|
| `path` | Tells WP-CLI where WordPress core lives in a Bedrock layout — saves you `--path=web/wp` on every command |
| `server.docroot` | Used by `wp server` (built-in dev server) to serve from Bedrock's public root |
| `require` | Auto-loads `wp-cli-pattern-validate.php` on every `wp` call so the `pattern validate` command is always available without an explicit `--require` flag |

---

## `wp-cli-pattern-validate.php`

A WP-CLI command that round-trips block pattern files through WordPress's own
`parse_blocks()` / `serialize_blocks()` to produce the exact markup WordPress
would write after a Gutenberg save. Ideal for enforcing consistent formatting
across a block theme's `patterns/` directory in CI or as a pre-commit check.

### How it works

1. Reads each `.php` pattern file and extracts the block HTML (supports both the
   `return 'string';` format and the PHP docblock + raw HTML format).
2. Passes the block HTML through `parse_blocks()` then `serialize_blocks()`.
3. Reverses the unicode escapes WordPress adds to `<`, `>`, `&`, and `--` so that
   PHP open/close tags, CSS custom properties (`--wp--…`), and literal `&` survive
   round-tripping unchanged.
4. Compares original vs canonical — reports PASS / FAIL, optionally diffs or fixes.

### Usage

```bash
# Validate all patterns — dry run, shows PASS/FAIL per file
wp pattern validate web/app/themes/your-theme/patterns/

# Show a unified diff for each file that needs changes (no writes)
wp pattern validate web/app/themes/your-theme/patterns/ --diff

# Auto-fix all structural issues in-place
wp pattern validate web/app/themes/your-theme/patterns/ --fix

# Fix and save per-file diff logs + a summary to docs/pattern-logs/<date>/
wp pattern validate web/app/themes/your-theme/patterns/ --fix --log

# Override the log output directory
wp pattern validate web/app/themes/your-theme/patterns/ --fix --log --log-dir=/tmp/pattern-logs

# Validate a single file
wp pattern validate web/app/themes/your-theme/patterns/hero.php --fix

# Validate a subdirectory only
wp pattern validate web/app/themes/your-theme/patterns/woocommerce/ --fix
```

If `wp-cli-pattern-validate.php` is **not** auto-loaded via `wp-cli.yml`, pass it explicitly:

```bash
wp --require=wp-cli-pattern-validate.php pattern validate web/app/themes/your-theme/patterns/
```

### Options

| Flag | Description |
|------|-------------|
| `--fix` | Rewrite each non-canonical file in-place |
| `--diff` | Print a unified diff to stdout (dry-run, no writes) |
| `--log` | Write per-file `.diff` logs and a `summary.md` to `docs/pattern-logs/<date>/` |
| `--log-dir=<path>` | Override the default log directory |
| `--compliance` | Run project-specific compliance checks after structural validation |
| `--compliance-only` | Skip Gutenberg round-trip; run only compliance checks |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | All files pass (or all issues fixed) |
| `1` | One or more files need changes (dry-run) or a write error occurred |

### WooCommerce patterns

Files under a `woocommerce/patterns/` path are automatically skipped — they follow
WooCommerce's own standards rather than your theme's.

### Compliance hook

The `--compliance` and `--compliance-only` flags call `run_compliance_checks()`, which
is a stub in the distributed file. Adapt it to point at your project's own static-analysis
script (e.g. a checker that enforces theme-specific block rules):

```php
// Inside run_compliance_checks():
$checker = dirname( __FILE__ ) . '/scripts/pattern-check/class-compliancechecker.php';
```

Projects that don't need this can leave the stub as-is — the flags will emit a warning
and exit cleanly.

### Log output structure

With `--log`, each run creates:

```
docs/pattern-logs/
└── 2026-05-30/
    ├── hero.php.diff
    ├── card.php.diff
    └── summary.md
```

`summary.md` contains a per-file status table (PASS / FIXED / NEEDS_FIX) and counts.

---

## Requirements

- WP-CLI 2.x
- PHP 7.4+
- `diff` binary available in `$PATH` (standard on macOS and Linux)
- WordPress must be bootstrapped for `parse_blocks()` / `serialize_blocks()` to be
  available — run `wp` from the Bedrock site root as usual
