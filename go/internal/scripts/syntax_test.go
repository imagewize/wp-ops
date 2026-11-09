package scripts

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestShellScriptsParseWithSystemBash runs `/bin/bash -n` over every shipped
// .sh file. wp-ops executes scripts with /bin/bash, which on macOS is bash
// 3.2, and 3.2 rejects some constructs bash 5 accepts. 5.45.1 shipped a
// db-pull.sh that put a `case ... ;;` inside a heredoc inside $( ). It parsed
// under Homebrew's bash 5 and failed for every macOS user with "syntax error
// near unexpected token `;;'". On Linux CI /bin/bash is bash 5, so this only
// catches 3.2-only breakage when `go test` runs on a Mac.
func TestShellScriptsParseWithSystemBash(t *testing.T) {
	if _, err := os.Stat("/bin/bash"); err != nil {
		t.Skip("/bin/bash not present")
	}
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}

	var scripts []string
	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "node_modules", "dist":
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(path, ".sh") {
			scripts = append(scripts, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(scripts) == 0 {
		t.Fatalf("no .sh files found under %s", root)
	}

	for _, script := range scripts {
		rel, _ := filepath.Rel(root, script)
		t.Run(rel, func(t *testing.T) {
			out, err := exec.Command("/bin/bash", "-n", script).CombinedOutput()
			if err != nil {
				t.Errorf("/bin/bash -n %s failed: %v\n%s", rel, err, out)
			}
		})
	}
}
