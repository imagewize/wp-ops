// One-time environment setup — currently just shell completions. Named to
// match trellis-cli's `trellis init` (trellis's health check is `trellis
// check`; wp-ops's equivalent is the pre-existing `doctor` command, so
// `init` here is reserved for one-time setup rather than diagnostics).
package cmd

import (
	"bytes"
	"fmt"
	"os"
	osexec "os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
)

var initShellFlag string

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Install shell completions for wp-ops",
	Long: `init installs the wp-ops completion script for your shell, so
"wp-ops <TAB>" completes commands, categories, and command names.

Detects your shell from $SHELL. Pass --shell to override.`,
	RunE: func(cc *cobra.Command, args []string) error {
		os.Exit(runInit(initShellFlag))
		return nil
	},
}

func init() {
	initCmd.Flags().StringVar(&initShellFlag, "shell", "", "shell to install completions for (zsh, bash, fish) — default: detect from $SHELL")
	rootCmd.AddCommand(initCmd)
}

func runInit(shell string) int {
	if shell == "" {
		shell = filepath.Base(os.Getenv("SHELL"))
	}

	switch shell {
	case "zsh":
		return installCompletion("zsh", "_wp-ops", zshCandidateDirs(), genZshCompletion)
	case "bash":
		return installCompletion("bash", "wp-ops", bashCandidateDirs(), genBashCompletion)
	case "fish":
		return installCompletion("fish", "wp-ops.fish", fishCandidateDirs(), genFishCompletion)
	default:
		fmt.Fprintf(os.Stderr, "wp-ops init: unrecognized shell %q — pass --shell zsh|bash|fish\n", shell)
		return 1
	}
}

func genZshCompletion(buf *bytes.Buffer) error  { return rootCmd.GenZshCompletion(buf) }
func genBashCompletion(buf *bytes.Buffer) error { return rootCmd.GenBashCompletionV2(buf, true) }
func genFishCompletion(buf *bytes.Buffer) error { return rootCmd.GenFishCompletion(buf, true) }

// completionDir is one candidate install location. needsWiring is true for
// per-user fallback directories that aren't on the shell's completion
// search path by default (unlike a Homebrew-managed or system completions
// dir, which is), so installCompletion knows when to print setup guidance.
type completionDir struct {
	path        string
	needsWiring bool
}

// installCompletion generates the completion script and writes it to the
// first candidate directory that accepts the write, falling back down the
// list — e.g. a Homebrew-managed completions dir first, a per-user
// directory last. Reports which directory it landed on and, if that
// directory isn't on the shell's completion search path by default, what
// the user still needs to do to make it load.
func installCompletion(shell, filename string, candidates []completionDir, gen func(*bytes.Buffer) error) int {
	var buf bytes.Buffer
	if err := gen(&buf); err != nil {
		fmt.Fprintf(os.Stderr, "wp-ops init: generating %s completion: %v\n", shell, err)
		return 1
	}

	var lastErr error
	for _, c := range candidates {
		if err := os.MkdirAll(c.path, 0755); err != nil {
			lastErr = err
			continue
		}
		path := filepath.Join(c.path, filename)
		if err := os.WriteFile(path, buf.Bytes(), 0644); err != nil {
			lastErr = err
			continue
		}

		fmt.Printf("Installed %s completion: %s\n", shell, path)
		if c.needsWiring {
			fmt.Println(fallbackNote(shell, c.path))
		}
		fmt.Println("Restart your shell (or open a new terminal) to pick it up.")
		return 0
	}

	fmt.Fprintf(os.Stderr, "wp-ops init: couldn't write completion to any candidate directory: %v\n", lastErr)
	return 1
}

func fallbackNote(shell, dir string) string {
	switch shell {
	case "zsh":
		return fmt.Sprintf("Not on your fpath by default — add this to ~/.zshrc before compinit runs:\n  fpath=(%s $fpath)", dir)
	case "bash":
		return fmt.Sprintf("Not auto-sourced by default — add this to ~/.bashrc:\n  source %s/wp-ops", dir)
	default:
		return ""
	}
}

// brewPrefix shells out to `brew --prefix`; returns ok=false if brew isn't
// on PATH or the lookup fails, so callers fall through to non-Homebrew
// candidates.
func brewPrefix() (string, bool) {
	out, err := osexec.Command("brew", "--prefix").Output()
	if err != nil {
		return "", false
	}
	prefix := string(bytes.TrimSpace(out))
	if prefix == "" {
		return "", false
	}
	return prefix, true
}

func zshCandidateDirs() []completionDir {
	var dirs []completionDir
	if prefix, ok := brewPrefix(); ok {
		dirs = append(dirs, completionDir{filepath.Join(prefix, "share", "zsh", "site-functions"), false})
	}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, completionDir{filepath.Join(home, ".zsh", "completions"), true})
	}
	return dirs
}

func bashCandidateDirs() []completionDir {
	var dirs []completionDir
	if prefix, ok := brewPrefix(); ok {
		// bash-completion@2 (share/bash-completion/completions) is what
		// modern Homebrew installs; etc/bash_completion.d is the older
		// bash-completion v1 layout. Prefer whichever already exists.
		v2 := filepath.Join(prefix, "share", "bash-completion", "completions")
		if info, err := os.Stat(v2); err == nil && info.IsDir() {
			dirs = append(dirs, completionDir{v2, false})
		} else {
			dirs = append(dirs, completionDir{filepath.Join(prefix, "etc", "bash_completion.d"), false})
		}
	}
	for _, d := range []string{"/usr/share/bash-completion/completions", "/etc/bash_completion.d"} {
		if info, err := os.Stat(d); err == nil && info.IsDir() {
			dirs = append(dirs, completionDir{d, false})
		}
	}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, completionDir{filepath.Join(home, ".local", "share", "bash-completion", "completions"), true})
	}
	return dirs
}

func fishCandidateDirs() []completionDir {
	if home, err := os.UserHomeDir(); err == nil {
		// Fish auto-loads everything under its own completions dir, so this
		// never needs manual wiring — unlike the zsh/bash per-user fallbacks.
		return []completionDir{{filepath.Join(home, ".config", "fish", "completions"), false}}
	}
	return nil
}
