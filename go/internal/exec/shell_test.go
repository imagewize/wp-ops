package exec

import (
	"os"
	"path/filepath"
	"testing"
)

func writeScript(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "script.sh")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	return path
}

func TestRun_ExitCodeZero(t *testing.T) {
	path := writeScript(t, "#!/bin/sh\nexit 0\n")
	code, err := Run(path, nil)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if code != 0 {
		t.Errorf("exit code = %d, want 0", code)
	}
}

func TestRun_PropagatesNonZeroExitCode(t *testing.T) {
	path := writeScript(t, "#!/bin/sh\nexit 7\n")
	code, err := Run(path, nil)
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if code != 7 {
		t.Errorf("exit code = %d, want 7", code)
	}
}

func TestRun_PassesArgsThrough(t *testing.T) {
	path := writeScript(t, `#!/bin/sh
[ "$1" = "example.com" ] && [ "$2" = "production" ] || exit 1
`)
	code, err := Run(path, []string{"example.com", "production"})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (args not passed through correctly)", code)
	}
}

func TestRun_ChmodsNonExecutableScript(t *testing.T) {
	path := writeScript(t, "#!/bin/sh\nexit 0\n")
	if err := os.Chmod(path, 0o644); err != nil {
		t.Fatalf("Chmod: %v", err)
	}

	if _, err := Run(path, nil); err != nil {
		t.Fatalf("Run: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if info.Mode()&0o111 == 0 {
		t.Error("script still not executable after Run")
	}
}
