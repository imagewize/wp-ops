package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// stubProbes swaps the two environment probes for the duration of a test.
func stubProbes(t *testing.T, onHost, gnuDate bool) {
	t.Helper()
	origHost, origDate := onTrellisHost, hasGNUDate
	onTrellisHost = func() bool { return onHost }
	hasGNUDate = func() bool { return gnuDate }
	t.Cleanup(func() {
		onTrellisHost, hasGNUDate = origHost, origDate
	})
}

func serverEntry(key string) catalog.Entry {
	return catalog.Entry{
		Key:        key,
		Category:   "scripts",
		RunsOn:     "server",
		ScriptPath: key + ".sh",
	}
}

// realLogFile writes a throwaway file and returns its path.
func realLogFile(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "access.log")
	if err := os.WriteFile(path, []byte("log line\n"), 0o644); err != nil {
		t.Fatalf("writing temp log: %v", err)
	}
	return path
}

// TestServerSideGuard ports the decision table in execute_command()
// (wp-ops:1405-1429).
func TestServerSideGuard(t *testing.T) {
	logFile := realLogFile(t)

	tests := []struct {
		name        string
		entry       catalog.Entry
		args        []string
		onHost      bool
		gnuDate     bool
		wantProceed bool
		wantCode    int
		wantOutput  string // substring expected in the printed guidance
	}{
		{
			name:        "local command is never guarded",
			entry:       catalog.Entry{Key: "scripts/git/git-log-oneline", RunsOn: "local"},
			onHost:      false,
			wantProceed: true,
		},
		{
			name:        "server command runs when /srv/www is present",
			entry:       serverEntry("scripts/monitoring/traffic-monitor"),
			onHost:      true,
			wantProceed: true,
		},
		{
			name:        "server command off-host is blocked",
			entry:       serverEntry("scripts/monitoring/traffic-monitor"),
			onHost:      false,
			wantProceed: false,
			wantCode:    1,
			wantOutput:  "runs on the server, not here",
		},
		{
			// The nuance the guard exists for: an explicit readable log file
			// is an intentional "I have the log here".
			name:        "access-log command with a real file and GNU date proceeds",
			entry:       serverEntry("scripts/monitoring/traffic-monitor"),
			args:        []string{logFile, "24"},
			onHost:      false,
			gnuDate:     true,
			wantProceed: true,
		},
		{
			name:        "access-log command with a real file but BSD date is blocked",
			entry:       serverEntry("scripts/monitoring/security-monitor"),
			args:        []string{logFile},
			onHost:      false,
			gnuDate:     false,
			wantProceed: false,
			wantCode:    1,
			wantOutput:  "needs GNU date",
		},
		{
			name:        "access-log command with a nonexistent file is blocked",
			entry:       serverEntry("scripts/monitoring/ai-bot-monitor"),
			args:        []string{"/no/such/access.log"},
			onHost:      false,
			gnuDate:     true,
			wantProceed: false,
			wantCode:    1,
			wantOutput:  "runs on the server, not here",
		},
		{
			// error-monitor's first argument is a domain and
			// monitor's is an hour count, so a file argument must not
			// be mistaken for a log they can read locally.
			name:        "non-access-log command ignores a real file argument",
			entry:       serverEntry("scripts/monitoring/error-monitor"),
			args:        []string{logFile},
			onHost:      false,
			gnuDate:     true,
			wantProceed: false,
			wantCode:    1,
			wantOutput:  "runs on the server, not here",
		},
		{
			name:        "backup command ignores a real file argument",
			entry:       serverEntry("scripts/backup/site-backup"),
			args:        []string{logFile},
			onHost:      false,
			gnuDate:     true,
			wantProceed: false,
			wantCode:    1,
			wantOutput:  "/srv/backups/<site>",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stubProbes(t, tt.onHost, tt.gnuDate)

			var buf bytes.Buffer
			proceed, code := serverSideGuard(&buf, tt.entry, tt.args)

			if proceed != tt.wantProceed {
				t.Errorf("proceed = %v, want %v", proceed, tt.wantProceed)
			}
			if code != tt.wantCode {
				t.Errorf("exit code = %d, want %d", code, tt.wantCode)
			}
			if tt.wantProceed && buf.Len() != 0 {
				t.Errorf("printed guidance while allowing the run:\n%s", buf.String())
			}
			if tt.wantOutput != "" && !strings.Contains(buf.String(), tt.wantOutput) {
				t.Errorf("guidance missing %q, got:\n%s", tt.wantOutput, buf.String())
			}
		})
	}
}

// TestServerSideGuardDirectoryArgument covers bash's `[[ -f ]]`: a directory
// is not a log file, so it must not unlock the local run.
func TestServerSideGuardDirectoryArgument(t *testing.T) {
	stubProbes(t, false, true)

	var buf bytes.Buffer
	proceed, code := serverSideGuard(&buf, serverEntry("scripts/monitoring/traffic-monitor"), []string{t.TempDir()})

	if proceed || code != 1 {
		t.Fatalf("proceed = %v, code = %d; want blocked with 1", proceed, code)
	}
	if !strings.Contains(buf.String(), "runs on the server, not here") {
		t.Errorf("want the server-side guidance, got:\n%s", buf.String())
	}
}

// TestPrintServerSideGuidanceVariants pins the three intro/tail variants in
// print_server_side_guidance (wp-ops:1293) — a backup command, error-monitor,
// and the default access-log wording.
func TestPrintServerSideGuidanceVariants(t *testing.T) {
	tests := []struct {
		name        string
		key         string
		gnuDate     bool
		wantContain []string
		wantAbsent  []string
	}{
		{
			name:    "site-backup points at both pull playbooks",
			key:     "scripts/backup/site-backup",
			gnuDate: true,
			wantContain: []string{
				"writes the archive to /srv/backups/<site>",
				"ssh web@example.com 'bash -s' < scripts/backup/site-backup.sh",
				"wp-ops trellis/backup/database-pull",
				"wp-ops trellis/backup/files-pull",
				"example.com",
			},
			wantAbsent: []string{"gawk"},
		},
		{
			name:    "error-monitor explains the journal requirement",
			key:     "scripts/monitoring/error-monitor",
			gnuDate: true,
			wantContain: []string{
				"systemd journal directly",
				"example.com 48",
				"journal access, which the web user usually lacks",
			},
			// Not an access-log command, so no "pass a local log" offer.
			wantAbsent: []string{"Already have a log file", "/srv/backups/"},
		},
		{
			name:    "access-log command offers the local-file route when date is GNU",
			key:     "scripts/monitoring/traffic-monitor",
			gnuDate: true,
			wantContain: []string{
				"reads /srv/www/<site>/logs/access.log directly",
				"/srv/www/example.com/logs/access.log 24",
				"apt install gawk",
				"Already have a log file on this machine?",
				"wp-ops scripts/monitoring/traffic-monitor /path/to/access.log",
			},
			wantAbsent: []string{"which this machine lacks"},
		},
		{
			name:    "access-log command explains the BSD-date caveat instead",
			key:     "scripts/monitoring/ai-bot-monitor",
			gnuDate: false,
			wantContain: []string{
				"The SSH route above is unaffected",
				"which this machine lacks",
			},
			wantAbsent: []string{"Already have a log file"},
		},
		{
			name:    "monitor gets the gawk note but no local-file offer",
			key:     "scripts/monitoring/monitor",
			gnuDate: true,
			wantContain: []string{
				"24 example.com",
				"apt install gawk",
			},
			wantAbsent: []string{"Already have a log file", "The SSH route above"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stubProbes(t, false, tt.gnuDate)

			var buf bytes.Buffer
			printServerSideGuidance(&buf, serverEntry(tt.key))
			got := buf.String()

			if !strings.HasPrefix(got, "! "+tt.key+" runs on the server, not here.") {
				t.Errorf("unexpected header line:\n%s", got)
			}
			for _, want := range tt.wantContain {
				if !strings.Contains(got, want) {
					t.Errorf("missing %q in:\n%s", want, got)
				}
			}
			for _, absent := range tt.wantAbsent {
				if strings.Contains(got, absent) {
					t.Errorf("unexpected %q in:\n%s", absent, got)
				}
			}
		})
	}
}

// TestServerSideExampleArgs ports server_side_example_args (wp-ops:167). Each
// script orders its positional arguments differently and a wrong example is
// worse than none, so the mapping is worth pinning outright.
func TestServerSideExampleArgs(t *testing.T) {
	tests := map[string]string{
		"scripts/monitoring/error-monitor":    "example.com 48",
		"scripts/monitoring/monitor":          "24 example.com",
		"scripts/backup/site-backup":          "example.com",
		"scripts/monitoring/traffic-monitor":  "/srv/www/example.com/logs/access.log 24",
		"scripts/monitoring/security-monitor": "/srv/www/example.com/logs/access.log 24",
	}

	for key, want := range tests {
		if got := serverSideExampleArgs(key); got != want {
			t.Errorf("serverSideExampleArgs(%q) = %q, want %q", key, got, want)
		}
	}
}

func TestPrintGNUDateRequired(t *testing.T) {
	var buf bytes.Buffer
	printGNUDateRequired(&buf, serverEntry("scripts/monitoring/traffic-monitor"))
	got := buf.String()

	// bash's CROSS (wp-ops:88); the guidance path uses WARN, which is "!".
	if !strings.HasPrefix(got, "✗ ") {
		t.Errorf("want the ✗ marker bash uses, got:\n%s", got)
	}

	for _, want := range []string{
		"needs GNU date, which isn't the 'date' on this PATH",
		"BSD date, which rejects -d",
		"ssh web@example.com 'bash -s' < scripts/monitoring/traffic-monitor.sh",
		"brew install coreutils",
		"libexec/gnubin:$PATH",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
}

// TestServerSideListsMatchCatalog guards against the hardcoded lists drifting
// away from the catalog: every key in them must still exist and still be a
// server-side command, or the guidance silently stops firing.
func TestServerSideListsMatchCatalog(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("loading catalog: %v", err)
	}

	for _, lists := range []map[string]bool{backupCommands, accessLogCommands} {
		for key := range lists {
			entry, ok := c.Lookup(key)
			if !ok {
				t.Errorf("%s is listed in serverside.go but not in the catalog", key)
				continue
			}
			if entry.RunsOn != "server" {
				t.Errorf("%s is listed in serverside.go but runs_on = %q", key, entry.RunsOn)
			}
		}
	}
}

func TestIsRegularFile(t *testing.T) {
	if isRegularFile("") {
		t.Error("empty path should not be a regular file")
	}
	if isRegularFile(t.TempDir()) {
		t.Error("a directory should not be a regular file")
	}
	if isRegularFile(filepath.Join(t.TempDir(), "missing")) {
		t.Error("a missing path should not be a regular file")
	}
	if !isRegularFile(realLogFile(t)) {
		t.Error("a real file should be a regular file")
	}
}
