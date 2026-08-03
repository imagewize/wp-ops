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

// BuildPlaybookArgs translates positional CLI args into ansible-playbook
// "-e name=value" extra-vars using the command's manifest @arg/@flag
// declarations, so e.g. "wp-ops database-backup example.com production"
// becomes ["-e", "site=example.com", "-e", "env=production"] — the same
// ergonomics db-pull.sh/db-backup.sh already have, without a bespoke script
// per playbook (see docs/wp-ops-recommendations.md, Gap 6a).
//
// Required @arg entries are consumed positionally, in manifest order.
// Anything after that is read as "--name value" or "--name=value" against
// the declared @flag names. If the first raw arg already looks like a flag
// (starts with "-"), nothing is translated — the caller is using the raw
// "-e key=value [...]" form directly, which keeps working unchanged, same
// as an entry with no manifest args at all.
func BuildPlaybookArgs(e catalog.Entry, rawArgs []string) ([]string, error) {
	if len(rawArgs) == 0 || strings.HasPrefix(rawArgs[0], "-") {
		return rawArgs, nil
	}
	if !e.Annotated || len(e.Args) == 0 {
		return rawArgs, nil
	}

	built := make([]string, 0, len(rawArgs)*2)

	i := 0
	for _, a := range e.Args {
		if i >= len(rawArgs) || strings.HasPrefix(rawArgs[i], "-") {
			return nil, fmt.Errorf(
				"missing required argument <%s> (%s)\n\nUsage: wp-ops %s %s",
				a.Name, a.Description, e.Key, positionalUsage(e),
			)
		}
		built = append(built, "-e", a.Name+"="+rawArgs[i])
		i++
	}

	for i < len(rawArgs) {
		tok := rawArgs[i]
		if strings.HasPrefix(tok, "--") {
			name := strings.TrimPrefix(tok, "--")
			var value string
			if eq := strings.IndexByte(name, '='); eq >= 0 {
				value = name[eq+1:]
				name = name[:eq]
			} else {
				i++
				if i >= len(rawArgs) {
					return nil, fmt.Errorf("flag --%s needs a value", name)
				}
				value = rawArgs[i]
			}
			built = append(built, "-e", name+"="+value)
			i++
			continue
		}
		// Anything else (a raw "-e" pair, a stray positional) passes through
		// untouched — same escape hatch as the leading-dash check above.
		built = append(built, tok)
		i++
	}

	return built, nil
}

func positionalUsage(e catalog.Entry) string {
	parts := make([]string, len(e.Args))
	for idx, a := range e.Args {
		parts[idx] = "<" + a.Name + ">"
	}
	return strings.Join(parts, " ")
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
