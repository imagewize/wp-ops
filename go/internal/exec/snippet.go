package exec

import (
	"fmt"
	"io"
	"os"
	osexec "os/exec"
	"path/filepath"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// wordpress-utilities files are copy-paste-into-a-theme reference snippets
// (PHP includes, CSS, browser JS) with no meaningful "run" behavior of their
// own, so instead of executing them, wp-ops prints or clipboard-copies them.
// Port of execute_snippet() (wp-ops:1232).

// clipboardCmd resolves the first available clipboard tool, returning its
// argv (command plus any fixed args). Port of find_clipboard_cmd()
// (wp-ops:1220): pbcopy (macOS) -> xclip/xsel (Linux) -> clip.exe
// (WSL/Windows). Returns nil if none are on PATH.
func clipboardCmd(lookPath func(string) (string, error)) []string {
	for _, candidate := range [][]string{
		{"pbcopy"},
		{"xclip", "-selection", "clipboard"},
		{"xsel", "--clipboard", "--input"},
		{"clip.exe"},
	} {
		if _, err := lookPath(candidate[0]); err == nil {
			return candidate
		}
	}
	return nil
}

// CopySnippet copies scriptPath's contents to the clipboard via the first
// available clipboard tool. Returns ok=false with no error when no clipboard
// tool is found on PATH — the caller prints the "try --path instead"
// guidance, matching bash's messaging split (wp-ops:1267-1271).
func CopySnippet(scriptPath string) (ok bool, err error) {
	argv := clipboardCmd(osexec.LookPath)
	if argv == nil {
		return false, nil
	}

	f, err := os.Open(scriptPath)
	if err != nil {
		return false, err
	}
	defer f.Close()

	cmd := osexec.Command(argv[0], argv[1:]...)
	cmd.Stdin = f
	if err := cmd.Run(); err != nil {
		return false, err
	}
	return true, nil
}

// PrintSnippet writes scriptPath's contents to w. When tty is true it adds
// the dimmed-in-bash filename header and trailing reference-snippet notice
// bash prints on a terminal (wp-ops:1280-1285); when false (piped/redirected)
// it writes the raw file content only, so `wp-ops ... > footer.php` still
// works (wp-ops:1286-1288). wp-ops's Go port drops bash's ANSI dimming —
// see printCompletionBanner (dispatch.go) for the same plain-text convention.
func PrintSnippet(w io.Writer, scriptPath string, tty bool) error {
	data, err := os.ReadFile(scriptPath)
	if err != nil {
		return err
	}

	if !tty {
		_, err := w.Write(data)
		return err
	}

	fmt.Fprintf(w, "# %s\n\n", scriptPath)
	w.Write(data)
	fmt.Fprintln(w)
	fmt.Fprintln(w, "Reference snippet — copy it into your project (wp-ops does not run it). Try --copy or --path.")
	return nil
}

// FormatSnippetHelp renders --help for a wordpress-utilities/* snippet from
// its catalog entry, plus the fixed "this is a reference snippet, not run
// directly" explanation and three-line usage block bash prints. Port of
// print_manifest_help plus execute_snippet()'s --help branch
// (wp-ops:1237-1256).
func FormatSnippetHelp(e catalog.Entry) string {
	var b strings.Builder

	if !e.Annotated {
		fmt.Fprintf(&b, "Description: %s\n\n", e.Description)
		fmt.Fprintf(&b, "File: %s\n\n", e.ScriptPath)
	} else {
		writeManifestHelpBody(&b, e)
		fmt.Fprintln(&b)
	}

	fmt.Fprintln(&b, "This is a reference snippet meant to be copied into a WordPress")
	fmt.Fprintln(&b, "theme or plugin, not run directly — wp-ops just prints it.")
	fmt.Fprintln(&b)
	fmt.Fprintf(&b, "Usage: wp-ops %s            Print the snippet\n", e.Key)
	fmt.Fprintf(&b, "       wp-ops %s --copy      Copy it to the clipboard\n", e.Key)
	fmt.Fprintf(&b, "       wp-ops %s --path      Print only the file path\n", e.Key)
	return b.String()
}

// RunSnippet dispatches a wordpress-utilities/* command's non-help args:
// --path prints the resolved file path, --copy copies to the clipboard
// (falling back to a "try --path" error when no clipboard tool is found),
// and anything else prints the snippet (TTY-aware, see PrintSnippet). Port
// of execute_snippet()'s body (wp-ops:1258-1290) minus the --help branch,
// which the caller handles via FormatSnippetHelp same as the other
// executors.
func RunSnippet(w io.Writer, errw io.Writer, e catalog.Entry, scriptPath string, args []string, tty bool) int {
	if len(args) > 0 && args[0] == "--path" {
		fmt.Fprintln(w, scriptPath)
		return 0
	}

	if len(args) > 0 && args[0] == "--copy" {
		ok, err := CopySnippet(scriptPath)
		if err != nil {
			fmt.Fprintln(errw, err)
			return 1
		}
		if !ok {
			fmt.Fprintln(errw, "No clipboard tool found (tried pbcopy, xclip, xsel, clip.exe).")
			fmt.Fprintf(errw, "Use 'wp-ops %s --path' to get the file path instead.\n", e.Key)
			return 1
		}
		if tty {
			fmt.Fprintf(w, "Copied %s to clipboard\n", filepath.Base(scriptPath))
		}
		return 0
	}

	if err := PrintSnippet(w, scriptPath, tty); err != nil {
		fmt.Fprintln(errw, err)
		return 1
	}
	return 0
}
