package exec

import (
	"fmt"
	"os"
	osexec "os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// AnsiblePlaybookAvailable reports whether ansible-playbook is on PATH —
// port of execute_playbook()'s `command -v ansible-playbook` check.
func AnsiblePlaybookAvailable() bool {
	_, err := osexec.LookPath("ansible-playbook")
	return err == nil
}

// stagedPlaybookPrefix marks the temp copies stagePlaybookInProjectDir
// leaves inside a Trellis project directory. Named distinctively enough
// that sweeping matches on startup can never touch a real project file.
const stagedPlaybookPrefix = ".wp-ops-run-"

// importPlaybookRe matches an `import_playbook: <file>` list-item line
// (Ansible's syntax for pulling in a sibling playbook file), capturing the
// leading key text and the referenced filename separately so the filename
// can be swapped for its staged copy.
var importPlaybookRe = regexp.MustCompile(`(?m)^(\s*-\s*import_playbook:\s*)(\S+)\s*$`)

// stagePlaybookInProjectDir copies playbookPath — and, recursively, any
// same-directory file it references via `import_playbook:` — into
// trellisDir itself, under randomized temp names, rewriting those
// references to match. Returns the staged entry playbook's path and a
// cleanup func that removes every file it staged; cleanup is always safe
// to call, even after a staging error.
//
// This exists because Ansible resolves group_vars/host_vars relative to
// the directory containing the playbook file being *executed* — not the
// current working directory, and not the inventory's directory. wp-ops
// ships/caches its own copies of the trellis/backup and trellis/monitoring
// playbooks outside the Trellis project (see catalog/assets caching), so
// running them straight from the cache leaves the project's group_vars
// (web_user, php_version, etc.) completely unresolved — every var they
// define comes back undefined, breaking anything the playbook needs from
// them (e.g. remote_user). Staging a copy inside trellisDir, sibling to
// its group_vars/, fixes that without the project needing to know
// anything about wp-ops at all.
func stagePlaybookInProjectDir(trellisDir, playbookPath string) (entryPath string, cleanup func(), err error) {
	sweepStalePlaybookStaging(trellisDir)

	srcDir := filepath.Dir(playbookPath)
	runID := strconv.FormatInt(time.Now().UnixNano(), 36)

	staged := map[string]string{} // source basename -> staged path
	var stagedPaths []string

	cleanup = func() {
		for _, p := range stagedPaths {
			os.Remove(p)
		}
	}

	var stageOne func(path string) (string, error)
	stageOne = func(path string) (string, error) {
		base := filepath.Base(path)
		if existing, ok := staged[base]; ok {
			return existing, nil
		}

		content, readErr := os.ReadFile(path)
		if readErr != nil {
			return "", readErr
		}

		tempPath := filepath.Join(trellisDir, stagedPlaybookPrefix+runID+"-"+base)
		staged[base] = tempPath

		rewritten := importPlaybookRe.ReplaceAllFunc(content, func(line []byte) []byte {
			m := importPlaybookRe.FindSubmatch(line)
			refBase := string(m[2])
			refPath := filepath.Join(srcDir, refBase)
			if _, statErr := os.Stat(refPath); statErr != nil {
				// Not a sibling file on disk (e.g. an absolute path or a
				// reference into roles/) — leave the line untouched.
				return line
			}
			refStaged, stageErr := stageOne(refPath)
			if stageErr != nil {
				return line
			}
			return append(append([]byte{}, m[1]...), []byte(filepath.Base(refStaged))...)
		})

		if writeErr := os.WriteFile(tempPath, rewritten, 0644); writeErr != nil {
			return "", writeErr
		}
		stagedPaths = append(stagedPaths, tempPath)
		return tempPath, nil
	}

	entryPath, err = stageOne(playbookPath)
	if err != nil {
		cleanup()
		return "", func() {}, err
	}
	return entryPath, cleanup, nil
}

// sweepStalePlaybookStaging removes any leftover staged-playbook temp
// files from a prior run that never got to clean up after itself (killed
// mid-run, crashed, etc.). Best-effort: errors are ignored since this is
// housekeeping, not the operation the caller actually asked for.
func sweepStalePlaybookStaging(trellisDir string) {
	matches, _ := filepath.Glob(filepath.Join(trellisDir, stagedPlaybookPrefix+"*"))
	for _, m := range matches {
		os.Remove(m)
	}
}

// RunPlaybook runs `ansible-playbook <playbookPath> <args...>` from
// trellisDir, with stdio inherited. Port of execute_playbook()'s execution
// path (wp-ops:1084-1103). Argument building (-e site=..., -e env=...) and
// TRELLIS_DIR resolution/confirmation are the caller's job — see
// internal/detect — since they need the manifest and interactive prompting
// this package intentionally stays free of.
//
// playbookPath is staged into trellisDir first (see
// stagePlaybookInProjectDir) so the playbook's group_vars/host_vars
// resolve against the project, not wherever playbookPath actually lives.
func RunPlaybook(trellisDir, playbookPath string, args []string) (exitCode int, err error) {
	stagedPath, cleanup, stageErr := stagePlaybookInProjectDir(trellisDir, playbookPath)
	if stageErr != nil {
		return 1, fmt.Errorf("staging playbook into %s: %w", trellisDir, stageErr)
	}
	defer cleanup()

	cmd := osexec.Command("ansible-playbook", append([]string{stagedPath}, args...)...)
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
