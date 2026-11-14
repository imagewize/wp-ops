package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// fakeTrellisProject builds <root>/trellis with the files detect.TrellisDir
// looks for, and returns the project root.
func fakeTrellisProject(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	trellis := filepath.Join(root, "trellis")
	if err := os.MkdirAll(filepath.Join(trellis, "group_vars"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(trellis, "ansible.cfg"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestResolveTrellisDir_UsesProjectItIsStandingInWithoutAsking(t *testing.T) {
	root := fakeTrellisProject(t)
	t.Setenv("TRELLIS_DIR", "")
	t.Setenv("HOME", t.TempDir())

	for _, start := range []string{root, filepath.Join(root, "trellis")} {
		t.Chdir(start)
		got, ok := resolveTrellisDir(false)
		if !ok {
			t.Fatalf("from %s: expected the project to be used without a prompt", start)
		}
		if want := filepath.Join(root, "trellis"); !sameDir(t, got, want) {
			t.Errorf("from %s: got %s, want %s", start, got, want)
		}
	}
}

func TestResolveTrellisDir_PushStillNeedsConfirmation(t *testing.T) {
	root := fakeTrellisProject(t)
	t.Setenv("TRELLIS_DIR", "")
	t.Setenv("HOME", t.TempDir())
	t.Chdir(root)

	// go test has no terminal, so a confirmation can only refuse.
	if _, ok := resolveTrellisDir(true); ok {
		t.Fatal("a push must not use a detected directory without confirmation")
	}
}

func sameDir(t *testing.T, a, b string) bool {
	t.Helper()
	ai, err1 := filepath.EvalSymlinks(a)
	bi, err2 := filepath.EvalSymlinks(b)
	return err1 == nil && err2 == nil && ai == bi
}
