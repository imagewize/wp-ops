// Package assets embeds the command-carrying directories of the wp-ops repo
// (everything catalog.Categories walks, plus docs/ and the root-level guide
// files) so a binary built without a live checkout — e.g. one installed via
// `brew install imagewize/tap/wp-ops` — can extract them to a cache
// directory and run exactly as it would from a git clone. See
// docs/m4-go-cli-completion.md, task 6, "Script distribution: embed vs.
// locate."
//
// This file lives at the repo root, not under go/, because go:embed
// patterns may not ascend directories (no ".." component) and must stay
// within the module containing the source file — go/go.mod would make go/
// its own module boundary, putting scripts/, trellis/, etc. out of reach.
// go.mod was moved to the repo root for exactly this reason, so this
// package's import path is the bare module path: github.com/imagewize/wp-ops.
//
// Deliberately not using the "all:" embed prefix: that would also pull in
// dotfile/underscore-prefixed entries (stray .DS_Store files, .env.example,
// editor swap files) that happen to sit on the filesystem at build time.
// Plain go:embed already skips anything named with a leading "." or "_",
// which is exactly the cruft we don't want baked into a release binary.
//
// mcp-server/ is enumerated file by file rather than embedded as a whole
// directory, because the leading-dot rule above does NOT cover the three
// build artifacts gitignored under it — node_modules/, dist/, and
// config/sites.json. Embedding the directory wholesale picks all three up
// whenever they happen to exist on the filesystem at build time, which is
// always for anyone who has run the server locally:
//
//   - node_modules/ is ~61MB, and dominated the binary (55MB, of which 48MB
//     was embedded JS) on any local build. A release binary built by
//     goreleaser from a clean checkout never had them, so the same commit
//     produced wildly different binaries depending on who built it.
//   - config/sites.json is the operator's real site registry — SSH hosts and
//     remote paths for every configured environment. It has no business
//     inside a binary that might be handed to anyone. sites.example.json is
//     the tracked template and is embedded in its place.
//
// Nothing is lost by excluding the two build artifacts: mcp-server/run.sh
// (the registered stdio launcher) already runs `npm install` when
// node_modules/ is absent and rebuilds when dist/ is stale, which is exactly
// the state a freshly extracted brew install is in.
//
// Keep this list in sync with the tracked contents of mcp-server/ — go:embed
// fails the build on a missing path, so a deleted file surfaces immediately,
// but a newly added one silently will not ship until it is listed here.
package assets

import "embed"

//go:embed scripts trellis wp-cli docs README.md CLAUDE.md CHANGELOG.md LICENSE.md
//go:embed mcp-server/src mcp-server/config/sites.example.json
//go:embed mcp-server/dev.sh mcp-server/run.sh mcp-server/start.sh
//go:embed mcp-server/Dockerfile mcp-server/README.md mcp-server/tsconfig.json
//go:embed mcp-server/package.json mcp-server/package-lock.json
var FS embed.FS
