package cmd

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestEmbeddedVersion guards against assets.FS silently losing CHANGELOG.md
// (e.g. a stale embed pattern after the file moves) — extractedAssetsRoot's
// cache-directory name depends on this parsing correctly.
func TestEmbeddedVersion(t *testing.T) {
	v := embeddedVersion()
	if v == "unknown" || v == "" {
		t.Fatalf("embeddedVersion() = %q, want a real semver parsed from the embedded CHANGELOG.md", v)
	}
	if v[0] < '0' || v[0] > '9' {
		t.Errorf("embeddedVersion() = %q, want it to start with a digit", v)
	}
}

// TestExtractAssetsTo covers the file-mode split extractAssetsTo makes:
// direct-exec script extensions come out executable, everything else
// doesn't, and directories are recreated relative to the target root.
func TestExtractAssetsTo(t *testing.T) {
	dir := t.TempDir()
	if err := extractAssetsTo(dir); err != nil {
		t.Fatalf("extractAssetsTo(): %v", err)
	}

	readme := filepath.Join(dir, "README.md")
	info, err := os.Stat(readme)
	if err != nil {
		t.Fatalf("expected %s to exist: %v", readme, err)
	}
	if info.Mode().Perm()&0o111 != 0 {
		t.Errorf("README.md extracted executable (mode %v), want non-executable", info.Mode())
	}

	sh := filepath.Join(dir, "scripts", "git", "git-log-oneline.sh")
	info, err = os.Stat(sh)
	if err != nil {
		t.Fatalf("expected %s to exist: %v", sh, err)
	}
	if info.Mode().Perm()&0o100 == 0 {
		t.Errorf("git-log-oneline.sh extracted non-executable (mode %v), want the owner-exec bit set", info.Mode())
	}

	if info, err := os.Stat(filepath.Join(dir, "trellis", "backup")); err != nil || !info.IsDir() {
		t.Errorf("expected trellis/backup to be extracted as a directory: %v", err)
	}
}

// TestExtractedAssetsRoot exercises the cache-dir short-circuit: a second
// call against the same UserCacheDir must return the already-extracted
// directory without erroring, rather than re-extracting.
func TestExtractedAssetsRoot(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	// os.UserCacheDir() consults $HOME on macOS/Linux; XDG_CACHE_HOME is
	// only honored on Linux, so overriding HOME is the portable way to
	// sandbox this test's cache directory.
	t.Setenv("XDG_CACHE_HOME", "")

	dir1, err := extractedAssetsRoot()
	if err != nil {
		t.Fatalf("extractedAssetsRoot() first call: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir1, "README.md")); err != nil {
		t.Fatalf("expected README.md under %s: %v", dir1, err)
	}

	dir2, err := extractedAssetsRoot()
	if err != nil {
		t.Fatalf("extractedAssetsRoot() second call: %v", err)
	}
	if dir1 != dir2 {
		t.Errorf("extractedAssetsRoot() = %q, then %q; want the same cache dir both times", dir1, dir2)
	}
}

// mkExtraction creates a cache-parent entry aged to modTime, standing in
// for a per-version extraction directory left behind by an upgrade.
func mkExtraction(t *testing.T, parent, name string, modTime time.Time) string {
	t.Helper()
	dir := filepath.Join(parent, name)
	if err := os.MkdirAll(filepath.Join(dir, "scripts"), 0o755); err != nil {
		t.Fatalf("creating %s: %v", dir, err)
	}
	if err := os.Chtimes(dir, modTime, modTime); err != nil {
		t.Fatalf("aging %s: %v", dir, err)
	}
	return dir
}

func exists(t *testing.T, path string) bool {
	t.Helper()
	_, err := os.Stat(path)
	return err == nil
}

// TestSweepOldAssetExtractions covers what the sweep is and isn't allowed
// to delete: the current version always survives, so do the most recent
// superseded ones and anything too young to be sure no older binary is
// still reading it, and nothing outside the assets-*/.extract-* names is
// ever touched.
func TestSweepOldAssetExtractions(t *testing.T) {
	parent := t.TempDir()
	now := time.Now()
	old := now.Add(-30 * 24 * time.Hour)

	// Ages chosen so the keep-newest ordering is by modTime, not by name:
	// 5.9.0 sorts last alphabetically among these but is the newest.
	current := mkExtraction(t, parent, "assets-5.15.0", old)
	keptNewest := mkExtraction(t, parent, "assets-5.9.0", old.Add(48*time.Hour))
	keptSecond := mkExtraction(t, parent, "assets-5.14.1", old.Add(24*time.Hour))
	removedOlder := mkExtraction(t, parent, "assets-5.14.0", old)
	removedOldest := mkExtraction(t, parent, "assets-3.23.2", old.Add(-24*time.Hour))
	young := mkExtraction(t, parent, "assets-5.13.0", now.Add(-time.Hour))
	staleTemp := mkExtraction(t, parent, ".extract-123", old)
	youngTemp := mkExtraction(t, parent, ".extract-456", now.Add(-time.Minute))
	unrelated := mkExtraction(t, parent, "some-other-cache", old)

	stray := filepath.Join(parent, "assets-notadir")
	if err := os.WriteFile(stray, []byte("x"), 0o644); err != nil {
		t.Fatalf("creating %s: %v", stray, err)
	}
	if err := os.Chtimes(stray, old, old); err != nil {
		t.Fatalf("aging %s: %v", stray, err)
	}

	sweepOldAssetExtractions(parent, "assets-5.15.0", now)

	for _, keep := range []string{current, keptNewest, keptSecond, young, youngTemp, unrelated, stray} {
		if !exists(t, keep) {
			t.Errorf("%s was removed, want kept", filepath.Base(keep))
		}
	}
	for _, gone := range []string{removedOlder, removedOldest, staleTemp} {
		if exists(t, gone) {
			t.Errorf("%s survived, want removed", filepath.Base(gone))
		}
	}
}

// TestSweepOldAssetExtractionsKeepsEverythingBelowThreshold guards the
// common case — a machine that has only ever upgraded a couple of times
// shouldn't lose anything at all.
func TestSweepOldAssetExtractionsKeepsEverythingBelowThreshold(t *testing.T) {
	parent := t.TempDir()
	now := time.Now()
	old := now.Add(-30 * 24 * time.Hour)

	current := mkExtraction(t, parent, "assets-5.15.0", old)
	prev := mkExtraction(t, parent, "assets-5.14.1", old)
	older := mkExtraction(t, parent, "assets-5.14.0", old)

	sweepOldAssetExtractions(parent, "assets-5.15.0", now)

	for _, keep := range []string{current, prev, older} {
		if !exists(t, keep) {
			t.Errorf("%s was removed, want kept — only %d superseded extractions exist", filepath.Base(keep), keptPreviousExtractions)
		}
	}
}

// TestSweepOldAssetExtractionsMissingParent covers the best-effort
// contract: an unreadable cache parent is a no-op, not a panic.
func TestSweepOldAssetExtractionsMissingParent(t *testing.T) {
	sweepOldAssetExtractions(filepath.Join(t.TempDir(), "does-not-exist"), "assets-5.15.0", time.Now())
}
