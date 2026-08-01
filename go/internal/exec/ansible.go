package exec

import (
	"fmt"
	"os"
	osexec "os/exec"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// AnsiblePlaybookAvailable reports whether ansible-playbook is on PATH —
// port of execute_playbook()'s `command -v ansible-playbook` check.
func AnsiblePlaybookAvailable() bool {
	_, err := osexec.LookPath("ansible-playbook")
	return err == nil
}

// RunPlaybook runs `ansible-playbook <playbookPath> <args...>` from
// trellisDir, with stdio inherited. Port of execute_playbook()'s execution
// path (wp-ops:1084-1103). Argument building (-e site=..., -e env=...) and
// TRELLIS_DIR resolution/confirmation are the caller's job — see
// internal/detect — since they need the manifest and interactive prompting
// this package intentionally stays free of.
func RunPlaybook(trellisDir, playbookPath string, args []string) (exitCode int, err error) {
	cmd := osexec.Command("ansible-playbook", append([]string{playbookPath}, args...)...)
	cmd.Dir = trellisDir
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

// FormatHelp renders --help for a trellis/*.yml command from its catalog
// entry — manifest-first by construction, so unlike bash's pre-3.11 bug
// (parent plan, Phase A rollout step 2) there's no probe and no
// has_manifest-blind short-circuit to get wrong. Port of print_manifest_help
// (wp-ops:352) plus execute_playbook()'s --help branch (wp-ops:1064-1082).
func FormatHelp(e catalog.Entry, trellisDir string) string {
	current := trellisDir
	if current == "" {
		current = "not set"
	}

	if !e.Annotated {
		var b strings.Builder
		fmt.Fprintf(&b, "Usage: wp-ops %s -e site=<site> -e env=<development|staging|production> [-e key=value ...]\n\n", e.Key)
		fmt.Fprintf(&b, "Description: %s\n\n", e.Description)
		fmt.Fprintf(&b, "Playbook: %s\n", e.ScriptPath)
		fmt.Fprintln(&b, "Runs via ansible-playbook against the Trellis project at $TRELLIS_DIR")
		fmt.Fprintf(&b, "(currently: %s)\n", current)
		return b.String()
	}

	var b strings.Builder
	writeManifestHelpBody(&b, e)
	fmt.Fprintln(&b)
	fmt.Fprintln(&b, "Runs via ansible-playbook against the Trellis project at $TRELLIS_DIR")
	fmt.Fprintf(&b, "(currently: %s)\n", current)

	return b.String()
}
