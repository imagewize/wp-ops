// Package detect locates a Trellis project directory or a Bedrock WordPress
// site directory from the current working directory, and confirms an
// auto-detected candidate before it's used for anything destructive. Port of
// wp-ops's detect_trellis_dir, detect_wp_site_dir, and confirm_detected_dir
// — see docs/m3-go-skeleton.md, task 4.
package detect

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// TrellisDir walks up from startDir looking for a Trellis project, stopping
// below stopAt (pass $HOME; an empty stopAt means "stop at /"). Two shapes
// are recognized:
//
//   - startDir itself is the trellis/ directory (has ansible.cfg and
//     group_vars/ directly inside it).
//   - a parent directory holds a trellis/ansible.cfg — trusted only when
//     startDir *is* that parent, or the directory walked up through on the
//     way there is that parent's own Bedrock site (has web/wp/), so a
//     sibling checkout that merely happens to live near an unrelated
//     trellis/ isn't picked up by accident.
//
// Port of detect_trellis_dir() (wp-ops:942).
func TrellisDir(startDir, stopAt string) (string, bool) {
	dir := startDir
	previous := startDir

	for dir != "" && dir != "/" && dir != stopAt {
		if isFile(filepath.Join(dir, "ansible.cfg")) && isDir(filepath.Join(dir, "group_vars")) {
			return dir, true
		}

		if isFile(filepath.Join(dir, "trellis", "ansible.cfg")) {
			if dir == startDir || isDir(filepath.Join(previous, "web", "wp")) {
				return filepath.Join(dir, "trellis"), true
			}
		}

		previous = dir
		dir = filepath.Dir(dir)
	}

	return "", false
}

// WPSiteDir walks up from startDir looking for a Bedrock site root (a
// directory with both web/wp/ and composer.json), stopping below stopAt.
// Port of detect_wp_site_dir() (wp-ops:976).
func WPSiteDir(startDir, stopAt string) (string, bool) {
	dir := startDir

	for dir != "" && dir != "/" && dir != stopAt {
		if isDir(filepath.Join(dir, "web", "wp")) && isFile(filepath.Join(dir, "composer.json")) {
			return dir, true
		}
		dir = filepath.Dir(dir)
	}

	return "", false
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// IsTerminal reports whether f is attached to a real terminal — the Go
// equivalent of bash's `[[ -t N ]]`.
func IsTerminal(f *os.File) bool {
	info, err := f.Stat()
	if err != nil {
		return false
	}
	return info.Mode()&os.ModeCharDevice != 0
}

// Confirm asks whether a detected directory should be used for varName,
// mirroring confirm_detected_dir(). Detected directories back destructive
// operations (database push, files push), so a non-interactive session
// refuses to guess rather than silently proceeding — interactive is the
// caller-supplied result of IsTerminal(os.Stdin) && IsTerminal(os.Stdout).
func Confirm(varName, value string, in io.Reader, out io.Writer, interactive bool) bool {
	if !interactive {
		fmt.Fprintf(out, "%s is not set.\n\n", varName)
		fmt.Fprintf(out, "Detected a candidate at %s, but wp-ops won't assume it\n", value)
		fmt.Fprintln(out, "non-interactively. Set it explicitly:")
		fmt.Fprintf(out, "\n  export %s=%s\n\n", varName, value)
		return false
	}

	fmt.Fprintf(out, "%s is not set.\n", varName)
	fmt.Fprintf(out, "Detected from the current directory: %s\n\n", value)
	fmt.Fprint(out, "Use it for this command? [y/N] ")

	reply, _ := bufio.NewReader(in).ReadString('\n')
	fmt.Fprintln(out)

	reply = strings.TrimSpace(reply)
	if len(reply) > 0 && (reply[0] == 'y' || reply[0] == 'Y') {
		return true
	}

	fmt.Fprintln(out, "Cancelled. Set it explicitly instead:")
	fmt.Fprintf(out, "\n  export %s=/path/to/your/project\n\n", varName)
	return false
}
