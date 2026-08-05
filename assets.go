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
package assets

import "embed"

//go:embed scripts trellis wp-cli mcp-server docs README.md CLAUDE.md CHANGELOG.md LICENSE.md
var FS embed.FS
