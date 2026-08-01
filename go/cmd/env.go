package cmd

import (
	"bufio"
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	assets "github.com/imagewize/wp-ops"
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

// repoRoot locates the directory every script path is resolved relative to.
// Three sources, in priority order — see "Script distribution: embed vs.
// locate" in docs/m4-go-cli-completion.md (M4 task 6):
//
//  1. WP_OPS_ROOT — a development override, pointing at a live checkout.
//  2. A live checkout, found by walking up from the running binary's own
//     (symlink-resolved) location, then from the working directory, looking
//     for the repo's marker files (the bash "wp-ops" script alongside a
//     root "go.mod").
//  3. The embedded asset tree (github.com/imagewize/wp-ops's assets.FS),
//     extracted to a per-version cache directory on first run. This is the
//     only source available to a binary installed via `brew install
//     imagewize/tap/wp-ops`, which has no checkout on disk at all.
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

	root, err := extractedAssetsRoot()
	if err != nil {
		return "", fmt.Errorf("could not locate the wp-ops repo root; set WP_OPS_ROOT=/path/to/wp-ops (%w)", err)
	}
	return root, nil
}

// extractedAssetsRoot returns a directory on disk holding the embedded
// asset tree, extracting it there first if this is the first run of this
// binary's version. Version-stamping the target directory means an
// upgraded binary extracts fresh instead of running against a stale
// extraction left by a previous install.
func extractedAssetsRoot() (string, error) {
	base, err := os.UserCacheDir()
	if err != nil {
		return "", fmt.Errorf("no cache directory available to extract embedded scripts into: %w", err)
	}
	parent := filepath.Join(base, "wp-ops")
	dir := filepath.Join(parent, "assets-"+embeddedVersion())

	if info, err := os.Stat(dir); err == nil && info.IsDir() {
		return dir, nil
	}

	if err := os.MkdirAll(parent, 0o755); err != nil {
		return "", fmt.Errorf("could not create %s: %w", parent, err)
	}

	tmp, err := os.MkdirTemp(parent, ".extract-*")
	if err != nil {
		return "", fmt.Errorf("could not create a temp extraction dir: %w", err)
	}
	defer os.RemoveAll(tmp)

	if err := extractAssetsTo(tmp); err != nil {
		return "", fmt.Errorf("could not extract embedded scripts: %w", err)
	}

	if err := os.Rename(tmp, dir); err != nil {
		// A concurrent wp-ops invocation may have already won this race
		// and finished extracting to dir — that's success, not a failure.
		if info, statErr := os.Stat(dir); statErr == nil && info.IsDir() {
			return dir, nil
		}
		return "", fmt.Errorf("could not finalize extraction at %s: %w", dir, err)
	}
	return dir, nil
}

// extractAssetsTo writes every file in the embedded asset tree under dir,
// preserving its relative path. Files under the direct-exec categories
// (.sh/.py/.js — see the parent plan's "Current inventory" table) are
// written executable, since internal/exec/shell.go execs them directly
// rather than invoking an interpreter; everything else (.php, .yml, docs)
// is read as an argument by its own executor and doesn't need the bit.
func extractAssetsTo(dir string) error {
	return fs.WalkDir(assets.FS, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		target := filepath.Join(dir, path)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := fs.ReadFile(assets.FS, path)
		if err != nil {
			return err
		}
		perm := os.FileMode(0o644)
		switch filepath.Ext(path) {
		case ".sh", ".py", ".js":
			perm = 0o755
		}
		return os.WriteFile(target, data, perm)
	})
}

// embeddedVersion reads the current version straight out of the embedded
// CHANGELOG.md — repoRoot() isn't resolved yet at this point, so this can't
// go through getVersion(), which calls repoRoot() itself.
func embeddedVersion() string {
	data, err := fs.ReadFile(assets.FS, "CHANGELOG.md")
	if err != nil {
		return "unknown"
	}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		if m := versionRe.FindStringSubmatch(scanner.Text()); m != nil {
			return m[1]
		}
	}
	return "unknown"
}

func findRepoRootFrom(dir string) (string, bool) {
	for i := 0; i < 8 && dir != "" && dir != string(filepath.Separator); i++ {
		if info, err := os.Stat(filepath.Join(dir, "wp-ops")); err == nil && !info.IsDir() {
			if info, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil && !info.IsDir() {
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
