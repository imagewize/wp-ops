# Bedrock

Tools and workflows for [Bedrock](https://roots.io/bedrock/)-based WordPress sites.

## Contents

### [`local-package-development/`](local-package-development/)

Test an in-development plugin or theme inside a Bedrock site before tagging a release, by pointing the site's Composer dependency at a local git working copy via a `path` repository. Covers setup, the `symlink: false` requirement, re-syncing after edits, and cleanup.

### [`wp-cli-config/`](wp-cli-config/)

Standard `wp-cli.yml` for Bedrock (sets `path: web/wp` so `--path` is never needed) plus a custom `wp pattern validate` command that round-trips block pattern files through WordPress's own parser to enforce canonical formatting.
