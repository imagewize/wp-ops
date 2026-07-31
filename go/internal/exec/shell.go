// Package exec runs the scripts a catalog entry points at: direct exec for
// .sh/.js/.py commands (shell.go) and ansible-playbook for .yml commands
// (ansible.go). See docs/m3-go-skeleton.md, tasks 5-6.
package exec

import (
	"os"
	osexec "os/exec"
)

// Run executes scriptPath directly — relying on its shebang line, exactly
// like bash's `"$script_path" "$@"` (wp-ops:1484) — passing args through
// unmodified. The script owns its own flag parsing; wp-ops does none of it.
// Port of the generic (.sh/.js/.py) branch of execute_command().
func Run(scriptPath string, args []string) (exitCode int, err error) {
	if err := ensureExecutable(scriptPath); err != nil {
		return 1, err
	}

	cmd := osexec.Command(scriptPath, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*osexec.ExitError); ok {
			return exitErr.ExitCode(), nil
		}
		return 1, err
	}
	return 0, nil
}

// ensureExecutable chmods scriptPath +x if it isn't already, matching
// bash's `[[ ! -x "$script_path" ]] && chmod +x "$script_path"`.
func ensureExecutable(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.Mode()&0o111 == 0 {
		return os.Chmod(path, info.Mode()|0o111)
	}
	return nil
}
