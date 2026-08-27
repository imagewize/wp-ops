package assets

import (
	"io/fs"
	"strings"
	"testing"
)

// TestEmbedExcludesBuildArtifacts guards the file-by-file mcp-server/ embed
// list in assets.go. Reverting that list to a bare `//go:embed mcp-server`
// still compiles and still passes every other test in the repo — it just
// quietly starts baking node_modules/ (~61MB), dist/, and the operator's real
// config/sites.json into the binary on any machine where they exist. Nothing
// else in the build fails on that, so this test is the only thing standing
// between a stray one-line simplification and a 55MB binary carrying someone's
// SSH hosts around.
func TestEmbedExcludesBuildArtifacts(t *testing.T) {
	excluded := []string{
		"mcp-server/node_modules/",
		"mcp-server/dist/",
	}

	err := fs.WalkDir(FS, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		for _, prefix := range excluded {
			if strings.HasPrefix(path, prefix) {
				t.Errorf("embedded build artifact %s (matched %q)", path, prefix)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking embedded FS: %v", err)
	}

	// Checked by name rather than by prefix: sites.example.json is the tracked
	// template and must stay embedded, so a prefix on config/ would be wrong.
	if _, err := fs.ReadFile(FS, "mcp-server/config/sites.json"); err == nil {
		t.Error("embedded mcp-server/config/sites.json — that is the operator's " +
			"real site registry (SSH hosts, remote paths), not the example template")
	}
}

// TestEmbedIncludesTrackedFiles is the other half of the guard above: the
// exclusions are enforced by enumerating mcp-server/ by hand, and a hand-kept
// list is exactly the kind that loses an entry in a rename. go:embed fails the
// build on a path that disappears, but says nothing about one that was never
// added, so the files the extracted tree actually needs are asserted here.
func TestEmbedIncludesTrackedFiles(t *testing.T) {
	// The three mcp-server catalog commands plus what they need at runtime:
	// run.sh npm-installs and rebuilds from src/ on first launch, which is
	// precisely the state a freshly extracted brew install starts in.
	want := []string{
		"mcp-server/dev.sh",
		"mcp-server/run.sh",
		"mcp-server/start.sh",
		"mcp-server/package.json",
		"mcp-server/package-lock.json",
		"mcp-server/tsconfig.json",
		"mcp-server/src/server.ts",
		"mcp-server/config/sites.example.json",
		"CHANGELOG.md",
	}
	for _, path := range want {
		if _, err := fs.ReadFile(FS, path); err != nil {
			t.Errorf("missing from embedded FS: %s (%v)", path, err)
		}
	}
}
