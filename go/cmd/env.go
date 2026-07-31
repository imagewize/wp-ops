package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

var cat *catalog.Catalog

// mustCatalog loads the embedded catalog once per process, exiting on the
// (should-never-happen) case that it's corrupt — see catalog.Load.
func mustCatalog() *catalog.Catalog {
	if cat != nil {
		return cat
	}
	c, err := catalog.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	cat = c
	return cat
}

// repoRoot locates the wp-ops checkout a resolved script path is relative
// to. Distribution (bundling the scripts into the binary vs. requiring a
// checkout on disk) is an open decision the parent plan defers to M4 — see
// "Open decision — where do the scripts live?" in docs/cli-ux-plan.md.
// Until that's resolved, this assumes a checkout: WP_OPS_ROOT wins if set,
// otherwise it walks up from the running binary's own (symlink-resolved)
// location, then from the working directory, looking for the repo's marker
// files (the bash "wp-ops" script alongside a "go/go.mod").
func repoRoot() (string, error) {
	if v := os.Getenv("WP_OPS_ROOT"); v != "" {
		return v, nil
	}

	if exe, err := os.Executable(); err == nil {
		if resolved, err := filepath.EvalSymlinks(exe); err == nil {
			if root, ok := findRepoRootFrom(filepath.Dir(resolved)); ok {
				return root, nil
			}
		}
	}

	if cwd, err := os.Getwd(); err == nil {
		if root, ok := findRepoRootFrom(cwd); ok {
			return root, nil
		}
	}

	return "", fmt.Errorf("could not locate the wp-ops repo root; set WP_OPS_ROOT=/path/to/wp-ops")
}

func findRepoRootFrom(dir string) (string, bool) {
	for i := 0; i < 8 && dir != "" && dir != string(filepath.Separator); i++ {
		if info, err := os.Stat(filepath.Join(dir, "wp-ops")); err == nil && !info.IsDir() {
			if info, err := os.Stat(filepath.Join(dir, "go", "go.mod")); err == nil && !info.IsDir() {
				return dir, true
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", false
}
