package cmd

import (
	"bufio"
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

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
//     for a root "go.mod" declaring the wp-ops module.
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

	// Only after an extraction actually happened: on the fast path above
	// (this version is already extracted) there is nothing new to make
	// anything stale, and a run that asks for scripts shouldn't pay for a
	// directory scan it can't benefit from.
	sweepOldAssetExtractions(parent, filepath.Base(dir), time.Now())
	return dir, nil
}

// assetExtractionPrefix names the per-version extraction directories
// sweepOldAssetExtractions is allowed to remove. Matching on it (rather
// than on "every directory here") keeps the sweep from touching anything
// else that shares the cache parent, now or later.
const assetExtractionPrefix = "assets-"

// keptPreviousExtractions is how many superseded extractions survive a
// sweep, alongside the current version's. Keeping a couple is what makes
// the sweep safe against a concurrently running older binary — a just-
// replaced version is exactly the one a still-open shell or a
// mid-playbook run is most likely to be reading files out of, and
// removing it under them would fail the run with a missing script.
const keptPreviousExtractions = 2

// staleExtractionAge is how old an extraction must be before the sweep
// will consider it at all, on the same reasoning as
// stalePlaybookStagingAge in internal/exec: an in-flight run of an older
// version keeps reading its own scripts (playbooks, .sh files) for as
// long as it lasts, and a database or files pull can run for hours.
const staleExtractionAge = 24 * time.Hour

// sweepOldAssetExtractions removes superseded per-version asset
// extractions from the cache parent, which otherwise accumulate one
// directory per upgrade forever (29 of them, back to 3.23.2, on a machine
// that had been upgrading since the Go CLI shipped). The current version
// and the keptPreviousExtractions most recent others are always kept, as
// is anything younger than staleExtractionAge.
//
// Leftover ".extract-*" temp directories are swept on the same age rule:
// extractAssetsTo's own defer removes them, so any that survive are from
// a run that was killed mid-extraction and owns nothing.
//
// Best-effort throughout — this is housekeeping, not the operation the
// caller asked for, so a cache directory that can't be read or removed
// (permissions, a concurrent sweep) is left alone rather than failing the
// command.
func sweepOldAssetExtractions(parent, currentName string, now time.Time) {
	entries, err := os.ReadDir(parent)
	if err != nil {
		return
	}

	type extraction struct {
		path    string
		modTime time.Time
	}
	var superseded []extraction

	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		info, infoErr := e.Info()
		if infoErr != nil || now.Sub(info.ModTime()) < staleExtractionAge {
			continue
		}
		switch {
		case strings.HasPrefix(name, ".extract-"):
			os.RemoveAll(filepath.Join(parent, name))
		case strings.HasPrefix(name, assetExtractionPrefix) && name != currentName:
			superseded = append(superseded, extraction{filepath.Join(parent, name), info.ModTime()})
		}
	}

	// Newest first, so the tail past the keep count is the oldest.
	sort.Slice(superseded, func(i, j int) bool {
		return superseded[i].modTime.After(superseded[j].modTime)
	})
	if len(superseded) <= keptPreviousExtractions {
		return
	}
	for _, e := range superseded[keptPreviousExtractions:] {
		os.RemoveAll(e.path)
	}
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
		if isWpOpsModule(filepath.Join(dir, "go.mod")) {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", false
}

// isWpOpsModule reports whether goModPath is this repo's own go.mod, i.e.
// its module declaration is exactly "module github.com/imagewize/wp-ops" —
// not merely present, so an unrelated Go project's go.mod sitting nearby
// isn't mistaken for it.
func isWpOpsModule(goModPath string) bool {
	data, err := os.ReadFile(goModPath)
	if err != nil {
		return false
	}
	firstLine := strings.SplitN(string(data), "\n", 2)[0]
	return strings.TrimSpace(firstLine) == "module github.com/imagewize/wp-ops"
}
