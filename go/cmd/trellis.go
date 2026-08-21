package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/imagewize/wp-ops/go/internal/detect"
)

// resolveTrellisDir ports require_trellis_dir() (wp-ops:1031): trust
// $TRELLIS_DIR if it's set and looks like a Trellis project; otherwise try
// to detect one from the working directory and confirm interactively before
// using it — these commands back up, overwrite, and push databases, so an
// auto-detected directory is a convenience, not something to act on
// unprompted.
func resolveTrellisDir() (string, bool) {
	if dir := os.Getenv("TRELLIS_DIR"); dir != "" {
		if _, err := os.Stat(filepath.Join(dir, "ansible.cfg")); err != nil {
			fmt.Fprintf(os.Stderr, "TRELLIS_DIR (%s) doesn't look like a Trellis project (no ansible.cfg found).\n", dir)
			return "", false
		}
		return dir, true
	}

	cwd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return "", false
	}
	home, _ := os.UserHomeDir()

	detected, ok := detect.TrellisDir(cwd, home)
	if !ok {
		fmt.Fprintln(os.Stderr, "TRELLIS_DIR is not set.")
		fmt.Fprintln(os.Stderr)
		fmt.Fprintln(os.Stderr, "Ansible playbook commands run against a real Trellis project (they read")
		fmt.Fprintf(os.Stderr, "its ansible.cfg, inventory, and group_vars/), so %s needs to know\n", cmdName())
		fmt.Fprintln(os.Stderr, "where that project lives. Either run this from inside the project, or:")
		fmt.Fprintln(os.Stderr)
		fmt.Fprintln(os.Stderr, "  export TRELLIS_DIR=/path/to/your/trellis")
		return "", false
	}

	interactive := detect.IsTerminal(os.Stdin) && detect.IsTerminal(os.Stdout)
	if !detect.Confirm("TRELLIS_DIR", detected, os.Stdin, os.Stdout, interactive) {
		return "", false
	}
	return detected, true
}
