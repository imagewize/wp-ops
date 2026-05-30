# Local Package Development (Composer path repository)

Test an in-development plugin or theme inside a [Bedrock](https://roots.io/bedrock/)
site **before tagging a release**, by pointing the site's Composer dependency at
your local git working copy / branch instead of Packagist (or a private repo such
as wp-packages.org).

This is purely a local-dev change to the site's `composer.json` — **do not commit
it to the site repository**. Revert it once the package release is tagged.

## TL;DR

```bash
# In the Bedrock site's composer.json:
#  1. add a "path" repository pointing at your local package checkout
#  2. change the package constraint to the branch:  "dev-<branch>"
# Then:
cd /path/to/bedrock-site
composer update vendor/package-name
```

## Setup

### 1. Add a `path` repository

In the site's `composer.json`, add a `path` repository to the **top** of the
`repositories` array (entries are evaluated in order; listing it first lets it win
over Packagist / private repos for this package):

```json
"repositories": [
  {
    "type": "path",
    "url": "../../my-plugin",
    "options": {
      "symlink": false
    }
  },
  {
    "name": "wp-packages",
    "type": "composer",
    "url": "https://repo.wp-packages.org"
  }
],
```

- `url` is the path to your local package checkout, relative to the site's
  `composer.json` (absolute paths also work, but relative is more portable).
- **`symlink: false` is important** — see [Why `symlink: false`](#why-symlink-false-not-true) below.

### 2. Point the constraint at your branch

Change the package's version constraint to Composer's `dev-<branch>` form:

```json
"require": {
  "vendor/my-plugin": "dev-feature-xyz"
}
```

A `path` repository derives the package version from the **currently checked-out
branch** of that local repo, so the constraint must match that branch. Branch
`feature-xyz` → constraint `dev-feature-xyz`. (Slashes are kept: branch
`feat/xyz` → `dev-feat/xyz`.)

Bedrock ships with `"minimum-stability": "dev"` and `"prefer-stable": true`, so a
`dev-` constraint resolves fine. If some *other* package depends on yours with a
semver range (e.g. `^2.0`), add an inline alias so both resolve:

```json
"vendor/my-plugin": "dev-feature-xyz as 2.0.99"
```

### 3. Install

```bash
cd /path/to/bedrock-site
composer update vendor/my-plugin
```

You should see `Mirroring from ../../my-plugin`. The package lands as a **real
copied directory** in `web/app/plugins/` (or `web/app/themes/`), which WordPress
activates normally.

## Why `symlink: false` (not `true`)

Composer's `path` repository defaults to **symlinking** the package into place. For
a Bedrock plugin/theme that breaks activation:

> The plugin `my-plugin/my-plugin.php` has been deactivated due to an error:
> Plugin file does not exist.

WordPress calls `realpath()` on the plugin file, which resolves the symlink to its
target **outside** `web/app/plugins/` (e.g. `/Users/you/code/my-plugin`).
`plugin_basename()` then computes a slug that no longer matches the stored
activation record (`my-plugin/my-plugin.php`), so WordPress decides the file is
missing and deactivates it. Themes hit the analogous problem.

`symlink: false` makes Composer **mirror (copy)** the package instead, giving
WordPress a real directory inside the install. Trade-off: see re-syncing below.

## Re-syncing after local edits

Because the package is **copied**, edits in your local checkout do **not** appear
in the site automatically. Composer also won't re-mirror when the commit hash is
unchanged, so force it:

```bash
cd /path/to/bedrock-site
rm -rf web/app/plugins/my-plugin && composer update vendor/my-plugin
```

Commit (or at least stage) changes in the package repo first — the mirror reflects
the working tree at mirror time.

## Alternative: `vcs` repository (pushed branch)

If you've pushed the branch to GitHub and prefer not to reference a local path
(e.g. so a teammate can reproduce), use a `vcs` repository instead. This installs a
normal git checkout — no symlink, so no activation bug:

```json
"repositories": [
  {
    "type": "vcs",
    "url": "https://github.com/vendor/my-plugin"
  }
]
```

```json
"vendor/my-plugin": "dev-feature-xyz"
```

Trade-off: edits require `git push` + `composer update` to reach the site (no live
local working copy).

## Revert / cleanup

When the package release is tagged, undo the local-dev wiring:

1. Remove the `path` (or `vcs`) repository entry from the site's `composer.json`.
2. Restore the normal constraint (e.g. `^2.0`).
3. `composer update vendor/my-plugin`.

## Gotchas

- **Don't commit the change to the site repo** — the `path` `url` is specific to
  your machine. Keep it on a local-only branch or `git stash` / revert it.
- **`symlink: true` breaks plugin/theme activation** — always use `false` for
  Bedrock. (See above.)
- **Stale mirror** — Composer skips re-mirroring an unchanged commit hash;
  `rm -rf` the installed dir to force a fresh copy.
- **Compiled assets** — if the package ships a build artifact (e.g. a webpack
  bundle in `dist/`), make sure it's built/committed in the package before
  mirroring; the site loads the committed artifact, not your `src/`.
- **`minimum-stability`** — `dev-` constraints need `dev` (or a per-package
  `@dev` flag) allowed. Bedrock defaults to `"minimum-stability": "dev"`.

## Worked example

Testing the `issues-30-05-26` branch of `imagewize/warder-cookie-consent` in a
Bedrock site located at `code/imagewize.com/demo`, with the plugin checked out at
`code/warder-cookie-consent`:

```json
"repositories": [
  {
    "type": "path",
    "url": "../../warder-cookie-consent",
    "options": { "symlink": false }
  }
],
"require": {
  "imagewize/warder-cookie-consent": "dev-issues-30-05-26"
}
```

```bash
cd code/imagewize.com/demo
composer update imagewize/warder-cookie-consent
# - Installing imagewize/warder-cookie-consent (dev-issues-30-05-26 7290d6d):
#   Mirroring from ../../warder-cookie-consent
```
