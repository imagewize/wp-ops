package cmd

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func fakeGen(content string) func(*bytes.Buffer) error {
	return func(buf *bytes.Buffer) error {
		buf.WriteString(content)
		return nil
	}
}

// captureStdout redirects os.Stdout for the duration of fn and returns what
// was written to it.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe(): %v", err)
	}
	orig := os.Stdout
	os.Stdout = w
	defer func() { os.Stdout = orig }()

	fn()

	w.Close()
	var buf bytes.Buffer
	buf.ReadFrom(r)
	return buf.String()
}

// TestInstallCompletionWritesFirstWritableCandidate covers the fallback
// walk: a candidate whose MkdirAll fails (it's a file, not a dir) must be
// skipped in favor of the next one, and only that second candidate's
// needsWiring note should print.
func TestInstallCompletionWritesFirstWritableCandidate(t *testing.T) {
	tmp := t.TempDir()
	blocked := filepath.Join(tmp, "not-a-dir")
	if err := os.WriteFile(blocked, []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}
	good := filepath.Join(tmp, "good")

	var code int
	out := captureStdout(t, func() {
		code = installCompletion("zsh", "_wp-ops", []completionDir{
			{blocked, false},
			{good, true},
		}, fakeGen("# fake completion\n"))
	})

	if code != 0 {
		t.Fatalf("installCompletion() = %d, want 0", code)
	}

	path := filepath.Join(good, "_wp-ops")
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("expected completion written to %s: %v", path, err)
	}
	if string(content) != "# fake completion\n" {
		t.Errorf("wrote %q, want the generated content", content)
	}
	if !bytes.Contains([]byte(out), []byte("fpath")) {
		t.Errorf("output %q, want a fpath-wiring note since the winning candidate has needsWiring=true", out)
	}
}

// TestInstallCompletionNoWiringNoteWhenNotNeeded is the inverse: landing on
// a needsWiring=false candidate (e.g. Homebrew's site-functions dir) prints
// no follow-up instructions.
func TestInstallCompletionNoWiringNoteWhenNotNeeded(t *testing.T) {
	good := filepath.Join(t.TempDir(), "good")

	out := captureStdout(t, func() {
		installCompletion("zsh", "_wp-ops", []completionDir{{good, false}}, fakeGen("# fake\n"))
	})

	if bytes.Contains([]byte(out), []byte("fpath")) {
		t.Errorf("output %q, want no fpath-wiring note when needsWiring=false", out)
	}
}

func TestInstallCompletionFailsWhenNoCandidateWritable(t *testing.T) {
	tmp := t.TempDir()
	blocked := filepath.Join(tmp, "not-a-dir")
	if err := os.WriteFile(blocked, []byte("x"), 0644); err != nil {
		t.Fatal(err)
	}

	code := installCompletion("zsh", "_wp-ops", []completionDir{{blocked, false}}, fakeGen("# fake\n"))
	if code != 1 {
		t.Fatalf("installCompletion() = %d, want 1 when every candidate is unwritable", code)
	}
}

func TestInstallCompletionPropagatesGenError(t *testing.T) {
	gen := func(buf *bytes.Buffer) error { return errors.New("boom") }
	code := installCompletion("zsh", "_wp-ops", []completionDir{{t.TempDir(), false}}, gen)
	if code != 1 {
		t.Fatalf("installCompletion() = %d, want 1 when the generator errors", code)
	}
}

func TestRunInitUnrecognizedShell(t *testing.T) {
	if code := runInit("powershell"); code != 1 {
		t.Errorf("runInit(%q) = %d, want 1", "powershell", code)
	}
}

func TestFishCandidateDirsNeverNeedsWiring(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	dirs := fishCandidateDirs()
	if len(dirs) != 1 {
		t.Fatalf("fishCandidateDirs() = %d entries, want 1", len(dirs))
	}
	if dirs[0].needsWiring {
		t.Error("fish auto-loads its completions dir — should never need manual wiring")
	}
	want := filepath.Join(home, ".config", "fish", "completions")
	if dirs[0].path != want {
		t.Errorf("fishCandidateDirs()[0].path = %q, want %q", dirs[0].path, want)
	}
}

// TestZshCandidateDirsFallBackWithoutBrew and
// TestBashCandidateDirsFallBackWithoutBrew simulate a machine with no
// Homebrew on PATH (same technique as the manual `env -i` check this was
// verified against): the only remaining candidate must be the per-user
// fallback dir, marked needsWiring.
func TestZshCandidateDirsFallBackWithoutBrew(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin")

	dirs := zshCandidateDirs()
	if len(dirs) != 1 {
		t.Fatalf("zshCandidateDirs() without brew = %d entries, want 1 (home fallback only)", len(dirs))
	}
	if !dirs[0].needsWiring {
		t.Error("home-directory zsh completions dir needs manual fpath wiring")
	}
}

func TestBashCandidateDirsEndsWithHomeFallback(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin")

	dirs := bashCandidateDirs()
	if len(dirs) == 0 {
		t.Fatal("bashCandidateDirs() returned no candidates")
	}
	last := dirs[len(dirs)-1]
	want := filepath.Join(home, ".local", "share", "bash-completion", "completions")
	if last.path != want || !last.needsWiring {
		t.Errorf("last candidate = %+v, want {%q, true}", last, want)
	}
	for _, d := range dirs[:len(dirs)-1] {
		if d.needsWiring {
			t.Errorf("candidate %q marked needsWiring=true, want false for system/brew dirs", d.path)
		}
	}
}

func TestBrewPrefixFalseWithoutBrewOnPath(t *testing.T) {
	t.Setenv("PATH", "/usr/bin:/bin")
	if _, ok := brewPrefix(); ok {
		t.Error("brewPrefix() reported ok with brew excluded from PATH")
	}
}

// TestGenCompletionsProduceRealOutput exercises the three Cobra generator
// adapters directly — each must round-trip rootCmd into a non-empty,
// shell-appropriate script.
func TestGenCompletionsProduceRealOutput(t *testing.T) {
	cases := []struct {
		name   string
		gen    func(*bytes.Buffer) error
		marker string
	}{
		{"zsh", genZshCompletion, "#compdef wp-ops"},
		{"bash", genBashCompletion, "bash completion"},
		{"fish", genFishCompletion, "fish completion"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var buf bytes.Buffer
			if err := c.gen(&buf); err != nil {
				t.Fatalf("%s: %v", c.name, err)
			}
			if buf.Len() == 0 {
				t.Fatalf("%s: generated empty completion script", c.name)
			}
			if !bytes.Contains(buf.Bytes(), []byte(c.marker)) {
				t.Errorf("%s: output missing expected marker %q", c.name, c.marker)
			}
		})
	}
}

// TestRunInitEndToEnd exercises runInit's shell-dispatch switch for each
// supported shell against a sandboxed HOME, covering the full path from
// $SHELL detection through file-on-disk — not just installCompletion in
// isolation.
func TestRunInitEndToEnd(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin") // force the no-brew fallback paths

	cases := []struct {
		shell string
		path  string
	}{
		{"zsh", filepath.Join(home, ".zsh", "completions", "_wp-ops")},
		{"bash", filepath.Join(home, ".local", "share", "bash-completion", "completions", "wp-ops")},
		{"fish", filepath.Join(home, ".config", "fish", "completions", "wp-ops.fish")},
	}
	for _, c := range cases {
		t.Run(c.shell, func(t *testing.T) {
			if code := runInit(c.shell); code != 0 {
				t.Fatalf("runInit(%q) = %d, want 0", c.shell, code)
			}
			if _, err := os.Stat(c.path); err != nil {
				t.Errorf("expected completion at %s: %v", c.path, err)
			}
		})
	}
}
