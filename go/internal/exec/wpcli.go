package exec

import (
	"fmt"
	"os"
	osexec "os/exec"
	"path"
	"regexp"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// WPAvailable reports whether wp (WP-CLI) is on PATH — port of
// execute_php_command()'s `command -v wp` check (wp-ops:1189).
func WPAvailable() bool {
	_, err := osexec.LookPath("wp")
	return err == nil
}

var addCommandRe = regexp.MustCompile(`add_command\(\s*['"]([^'"]+)['"]`)

// RegisteredWPCommand extracts the name a WP-CLI command file registers via
// WP_CLI::add_command(), e.g. "pattern validate" from
// wp-cli-pattern-validate.php. Returns "" if the file doesn't register one
// (either it's not a WP_CLI_Command subclass, or grep found nothing). Port
// of get_registered_wp_command() (wp-ops:1140).
func RegisteredWPCommand(scriptPath string) string {
	data, err := os.ReadFile(scriptPath)
	if err != nil {
		return ""
	}
	if !strings.Contains(string(data), "extends WP_CLI_Command") {
		return ""
	}
	m := addCommandRe.FindStringSubmatch(string(data))
	if m == nil {
		return ""
	}
	return m[1]
}

// RunWPCLI runs a wp-cli/*.php or bedrock/*.php command against wpSiteDir,
// with stdio inherited. When wpCommand is set (the script registers a
// WP_CLI_Command), it runs as `wp --require=<scriptPath> <wpCommand>
// <args...>`; otherwise as `wp eval-file <scriptPath> <args...>`. Port of
// execute_php_command()'s execution path (wp-ops:1194-1203).
func RunWPCLI(wpSiteDir, scriptPath, wpCommand string, args []string) (exitCode int, err error) {
	var cmdArgs []string
	if wpCommand != "" {
		// wpCommand intentionally split on spaces and appended as separate
		// argv entries: a registered name like "pattern validate" is two
		// CLI words, not one argument — same as bash's unquoted expansion.
		cmdArgs = append([]string{"--require=" + scriptPath}, strings.Fields(wpCommand)...)
	} else {
		cmdArgs = []string{"eval-file", scriptPath}
	}
	cmdArgs = append(cmdArgs, args...)

	cmd := osexec.Command("wp", cmdArgs...)
	cmd.Dir = wpSiteDir
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

// FormatWPCLIHelp renders --help for a wp-cli/bedrock .php command from its
// catalog entry — manifest-first by construction, same as FormatHelp
// (ansible.go). Port of print_manifest_help plus execute_php_command()'s
// --help branch (wp-ops:1160-1186).
func FormatWPCLIHelp(e catalog.Entry, wpSiteDir, wpCommand string) string {
	current := wpSiteDir
	if current == "" {
		current = "not set"
	}

	runsLine := fmt.Sprintf("Runs via WP-CLI against the site at $WP_SITE_DIR (currently: %s)", current)
	var runsAs string
	if wpCommand != "" {
		runsAs = fmt.Sprintf("Runs as: wp --require=%s %s [args...]", path.Base(e.ScriptPath), wpCommand)
	} else {
		runsAs = fmt.Sprintf("Runs as: wp eval-file %s [args...]", path.Base(e.ScriptPath))
	}

	if !e.Annotated {
		var b strings.Builder
		fmt.Fprintf(&b, "Description: %s\n\n", e.Description)
		fmt.Fprintf(&b, "Script: %s\n", e.ScriptPath)
		fmt.Fprintln(&b, runsLine)
		fmt.Fprintln(&b)
		fmt.Fprintln(&b, runsAs)
		return b.String()
	}

	var b strings.Builder
	writeManifestHelpBody(&b, e)
	fmt.Fprintln(&b)
	fmt.Fprintln(&b, runsLine)
	fmt.Fprintln(&b, runsAs)
	return b.String()
}
