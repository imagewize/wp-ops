package cmd

import (
	"fmt"
	"io"
	"os"
	"os/exec"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// The server-side guard: the handful of commands that read /srv/www and
// /var/log directly are meaningless on a workstation, where they'd fail on a
// missing path several screens in and read as broken rather than as "wrong
// machine". Port of the guard in execute_command() (wp-ops:1405-1429) plus
// print_server_side_guidance() (wp-ops:1293) and print_gnu_date_required()
// (wp-ops:1361).
//
// Output goes to stderr rather than bash's stdout, matching the other
// diagnostics in this package (printUnknownCommand, printAmbiguous). The
// parity script deliberately doesn't treat these prose paths as a contract —
// only list/search/doctor/--json are field-compared.

// backupCommands ports BACKUP_COMMANDS (wp-ops:112): the server-side subset
// that writes to /srv/backups/. Called out separately because the Ansible
// playbooks under trellis/backup/ do the same job *and* retrieve the archive,
// which is usually what someone reaching for a backup from their workstation
// actually wants.
//
// db-backup isn't in this list: it's @runs local now — it SSHes out and
// streams straight to this machine, the same shape as db-pull. See
// docs/wp-ops-recommendations.md Gap 6.
var backupCommands = map[string]bool{
	"scripts/backup/site-backup": true,
}

// accessLogCommands ports ACCESS_LOG_COMMANDS (wp-ops:149): the subset taking
// an Nginx *access* log path as their first argument, for which "I already
// have a copy of the log here" is a meaningful thing to say. error-monitor's
// first argument is a domain and run-monitoring's is an hour count, so
// neither has a log file you could hand it locally.
var accessLogCommands = map[string]bool{
	"scripts/monitoring/traffic-monitor":  true,
	"scripts/monitoring/security-monitor": true,
	"scripts/monitoring/ai-bot-monitor":   true,
}

// serverSideExampleArgs ports server_side_example_args (wp-ops:167). Each of
// these scripts orders its positional arguments differently, and a wrong
// example is worse than none.
func serverSideExampleArgs(key string) string {
	switch key {
	case "scripts/monitoring/error-monitor":
		return "example.com 48"
	case "scripts/monitoring/run-monitoring":
		return "24 example.com"
	case "scripts/backup/site-backup":
		return "example.com"
	default:
		return "/srv/www/example.com/logs/access.log 24"
	}
}

// onTrellisHost reports whether /srv/www exists — the Trellis web root, present
// when we're actually on the server, absent on a workstation.
//
// A var, not a func, so tests can drive both sides of the guard without
// needing an actual /srv/www (same for hasGNUDate below).
var onTrellisHost = func() bool {
	info, err := os.Stat("/srv/www")
	return err == nil && info.IsDir()
}

// hasGNUDate ports has_gnu_date (wp-ops:180). Those scripts date-filter with
// `date -d "N hours ago"`, which is GNU-only — macOS's BSD date rejects -d
// outright, so the run would die partway through on `date: illegal option`.
var hasGNUDate = func() bool {
	return exec.Command("date", "-d", "1 hour ago", "+%s").Run() == nil
}

// isRegularFile reports whether path is an existing regular file, bash's
// `[[ -f "$1" ]]`.
func isRegularFile(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

// serverSideGuard decides whether a server-side command may run here, printing
// the reason to w when it may not. Returns the exit code to use when blocked.
//
// An explicit readable file argument is an intentional "I have the log here" —
// honoured for the commands that actually take a log path, and only where GNU
// date exists to run it.
func serverSideGuard(w io.Writer, e catalog.Entry, args []string) (proceed bool, exitCode int) {
	if e.RunsOn != "server" || onTrellisHost() {
		return true, 0
	}

	var first string
	if len(args) > 0 {
		first = args[0]
	}

	if !accessLogCommands[e.Key] || !isRegularFile(first) {
		printServerSideGuidance(w, e)
		return false, 1
	}

	if !hasGNUDate() {
		printGNUDateRequired(w, e)
		return false, 1
	}

	return true, 0
}

// printServerSideGuidance ports print_server_side_guidance (wp-ops:1293).
func printServerSideGuidance(w io.Writer, e catalog.Entry) {
	fmt.Fprintf(w, "! %s runs on the server, not here.\n\n", e.Key)

	switch {
	case backupCommands[e.Key]:
		fmt.Fprintln(w, "It reads /srv/www/<site> and writes the archive to /srv/backups/<site>,")
		fmt.Fprintln(w, "so both paths have to be the host's own. Stream it over SSH — nothing")
		fmt.Fprintln(w, "needs to be installed there:")
	case e.Key == "scripts/monitoring/error-monitor":
		fmt.Fprintln(w, "It reads /var/log/nginx/, /var/log/php*-fpm.log, /srv/www/<site>/logs/")
		fmt.Fprintln(w, "and the systemd journal directly, and uses GNU 'date -d', so it has to")
		fmt.Fprintln(w, "execute on the Trellis host. Stream it over SSH — nothing needs to be")
		fmt.Fprintln(w, "installed there:")
	default:
		fmt.Fprintln(w, "It reads /srv/www/<site>/logs/access.log directly and uses GNU 'date -d',")
		fmt.Fprintln(w, "so it has to execute on the Trellis host. Stream it over SSH — nothing")
		fmt.Fprintln(w, "needs to be installed there:")
	}

	fmt.Fprintf(w, "\n  ssh web@example.com 'bash -s' < %s\n\n", e.ScriptPath)
	fmt.Fprintln(w, "Arguments go after the redirect:")
	fmt.Fprintf(w, "\n  ssh web@example.com 'bash -s' < %s \\\n      %s\n\n",
		e.ScriptPath, serverSideExampleArgs(e.Key))

	if backupCommands[e.Key] {
		fmt.Fprintln(w, "That leaves the archive on the server. To back up *and* retrieve a copy")
		fmt.Fprintln(w, "to this machine in one step, use the Ansible playbooks instead:")
		fmt.Fprintln(w)
		fmt.Fprintln(w, "  wp-ops trellis/backup/database-pull -e site=example.com -e env=production")
		fmt.Fprintln(w, "  wp-ops trellis/backup/files-pull    -e site=example.com -e env=production")
		return
	}

	if e.Key == "scripts/monitoring/error-monitor" {
		fmt.Fprintln(w, "The systemd sections (critical errors, PHP segfaults, OOM kills) need")
		fmt.Fprintln(w, "journal access, which the web user usually lacks — connect as root to")
		fmt.Fprintln(w, "include them. They're reported as skipped rather than empty otherwise.")
		return
	}

	fmt.Fprintln(w, "Accurate time filtering needs gawk on the server (Ubuntu ships mawk;")
	fmt.Fprintln(w, "apt install gawk). Without it the script falls back to a line estimate.")
	fmt.Fprintln(w)

	if !accessLogCommands[e.Key] {
		return
	}

	if hasGNUDate() {
		fmt.Fprintln(w, "Already have a log file on this machine? Pass its path and it runs here:")
		fmt.Fprintf(w, "  wp-ops %s /path/to/access.log\n", e.Key)
	} else {
		fmt.Fprintln(w, "The SSH route above is unaffected by what's installed here — date and")
		fmt.Fprintln(w, "gawk both resolve on the server. Only running it against a log copied")
		fmt.Fprintln(w, "to this machine would need GNU date locally, which this machine lacks.")
	}
}

// printGNUDateRequired ports print_gnu_date_required (wp-ops:1361) — reached
// only when someone passed a real local log file to a command that accepts
// one, but this machine's `date` is BSD.
func printGNUDateRequired(w io.Writer, e catalog.Entry) {
	fmt.Fprintf(w, "✗ %s needs GNU date, which isn't the 'date' on this PATH.\n\n", e.Key)
	fmt.Fprintln(w, "It filters log lines by time with `date -d \"N hours ago\"`. macOS ships")
	fmt.Fprintln(w, "BSD date, which rejects -d, so the run would fail partway through.")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "Either run it on the server, where date is GNU already:")
	fmt.Fprintf(w, "\n  ssh web@example.com 'bash -s' < %s\n\n", e.ScriptPath)
	fmt.Fprintln(w, "or put GNU coreutils ahead of the BSD tools on this machine:")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "  brew install coreutils")
	fmt.Fprintln(w, "  export PATH=\"$(brew --prefix coreutils)/libexec/gnubin:$PATH\"")
	fmt.Fprintln(w)
	fmt.Fprintln(w, "gnubin puts GNU versions under their plain names, so 'date' becomes GNU date.")
}
