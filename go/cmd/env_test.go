package cmd

import (
	"os"
	"path/filepath"
	"testing"
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
