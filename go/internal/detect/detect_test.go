package detect

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mkdirAll(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("MkdirAll(%s): %v", path, err)
	}
}

func touch(t *testing.T, path string) {
	t.Helper()
	mkdirAll(t, filepath.Dir(path))
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatalf("WriteFile(%s): %v", path, err)
	}
}

func TestTrellisDir_StandingInTrellisDirItself(t *testing.T) {
	home := t.TempDir()
	trellis := filepath.Join(home, "project", "trellis")
	touch(t, filepath.Join(trellis, "ansible.cfg"))
	mkdirAll(t, filepath.Join(trellis, "group_vars"))

	got, ok := TrellisDir(trellis, home)
	if !ok || got != trellis {
		t.Fatalf("TrellisDir(%s) = (%s, %v), want (%s, true)", trellis, got, ok, trellis)
	}
}

func TestTrellisDir_ParentHoldsTrellisFromProjectRoot(t *testing.T) {
	home := t.TempDir()
	project := filepath.Join(home, "project")
	touch(t, filepath.Join(project, "trellis", "ansible.cfg"))

	got, ok := TrellisDir(project, home)
	want := filepath.Join(project, "trellis")
	if !ok || got != want {
		t.Fatalf("TrellisDir(%s) = (%s, %v), want (%s, true)", project, got, ok, want)
	}
}

func TestTrellisDir_DeeperInBedrockSiteResolves(t *testing.T) {
	home := t.TempDir()
	project := filepath.Join(home, "project")
	touch(t, filepath.Join(project, "trellis", "ansible.cfg"))
	site := filepath.Join(project, "site")
	mkdirAll(t, filepath.Join(site, "web", "wp"))
	deep := filepath.Join(site, "web", "app", "themes", "mytheme")
	mkdirAll(t, deep)

	got, ok := TrellisDir(deep, home)
	want := filepath.Join(project, "trellis")
	if !ok || got != want {
		t.Fatalf("TrellisDir(%s) = (%s, %v), want (%s, true)", deep, got, ok, want)
	}
}

func TestTrellisDir_SiblingCheckoutNotPickedUpFromUnrelatedDir(t *testing.T) {
	// ~/code/trellis sitting next to ~/code/wp-ops must not resolve when
	// standing inside wp-ops — there's no Bedrock web/wp/ between wp-ops and
	// ~/code to make the connection legitimate.
	home := t.TempDir()
	code := filepath.Join(home, "code")
	touch(t, filepath.Join(code, "trellis", "ansible.cfg"))
	wpOps := filepath.Join(code, "wp-ops")
	mkdirAll(t, wpOps)

	_, ok := TrellisDir(wpOps, home)
	if ok {
		t.Fatal("TrellisDir resolved a sibling checkout's trellis/ from an unrelated directory, want not found")
	}
}

func TestTrellisDir_StopsAtHome(t *testing.T) {
	home := t.TempDir()
	// ansible.cfg lives above $HOME — must not be found.
	above := filepath.Dir(home)
	touch(t, filepath.Join(above, "ansible.cfg"))
	mkdirAll(t, filepath.Join(above, "group_vars"))

	start := filepath.Join(home, "somewhere")
	mkdirAll(t, start)

	_, ok := TrellisDir(start, home)
	if ok {
		t.Fatal("TrellisDir walked above $HOME, want stopped")
	}
}

func TestWPSiteDir(t *testing.T) {
	home := t.TempDir()
	site := filepath.Join(home, "project", "site")
	mkdirAll(t, filepath.Join(site, "web", "wp"))
	touch(t, filepath.Join(site, "composer.json"))

	deep := filepath.Join(site, "web", "app", "themes", "mytheme")
	mkdirAll(t, deep)

	got, ok := WPSiteDir(deep, home)
	if !ok || got != site {
		t.Fatalf("WPSiteDir(%s) = (%s, %v), want (%s, true)", deep, got, ok, site)
	}
}

func TestWPSiteDir_NotFound(t *testing.T) {
	home := t.TempDir()
	start := filepath.Join(home, "somewhere", "else")
	mkdirAll(t, start)

	if _, ok := WPSiteDir(start, home); ok {
		t.Fatal("WPSiteDir found a site where none exists")
	}
}

func TestConfirm_NonInteractiveRefusesToGuess(t *testing.T) {
	var out strings.Builder
	used := Confirm("TRELLIS_DIR", "/path/to/trellis", strings.NewReader(""), &out, false)
	if used {
		t.Fatal("Confirm returned true in non-interactive mode")
	}
	if !strings.Contains(out.String(), "export TRELLIS_DIR=/path/to/trellis") {
		t.Errorf("output missing export hint: %s", out.String())
	}
}

func TestConfirm_InteractiveYes(t *testing.T) {
	var out strings.Builder
	used := Confirm("TRELLIS_DIR", "/path/to/trellis", strings.NewReader("y\n"), &out, true)
	if !used {
		t.Fatal("Confirm returned false for 'y' reply")
	}
}

func TestConfirm_InteractiveNo(t *testing.T) {
	var out strings.Builder
	used := Confirm("TRELLIS_DIR", "/path/to/trellis", strings.NewReader("n\n"), &out, true)
	if used {
		t.Fatal("Confirm returned true for 'n' reply")
	}
	if !strings.Contains(out.String(), "Cancelled") {
		t.Errorf("output missing cancellation message: %s", out.String())
	}
}

func TestConfirm_InteractiveBlankDefaultsToNo(t *testing.T) {
	var out strings.Builder
	used := Confirm("TRELLIS_DIR", "/path/to/trellis", strings.NewReader("\n"), &out, true)
	if used {
		t.Fatal("Confirm returned true for a blank reply, want default-to-no")
	}
}
