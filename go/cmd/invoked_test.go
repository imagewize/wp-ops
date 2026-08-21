package cmd

import (
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// withInvokedAs runs fn with argv[0]'s basename swapped, restoring it after.
func withInvokedAs(t *testing.T, name string, fn func()) {
	t.Helper()
	prev := invokedAs
	invokedAs = name
	defer func() { invokedAs = prev }()
	fn()
}

func TestCmdNameAndPlatformFollowArgv0(t *testing.T) {
	cases := []struct {
		argv0    string
		wantName string
		wantPlat string
	}{
		{"wp-ops", "wp-ops", ""},
		{"trellis-ops", "trellis ops", "trellis"},
		// Only the exact plugin name flips behavior — a user who renames
		// the binary to something else still gets plain wp-ops.
		{"trellis-wpops", "wp-ops", ""},
		{"wp-ops-dev", "wp-ops", ""},
	}
	for _, tc := range cases {
		withInvokedAs(t, tc.argv0, func() {
			if got := cmdName(); got != tc.wantName {
				t.Errorf("argv0 %q: cmdName() = %q, want %q", tc.argv0, got, tc.wantName)
			}
			if got := defaultPlatform(); got != tc.wantPlat {
				t.Errorf("argv0 %q: defaultPlatform() = %q, want %q", tc.argv0, got, tc.wantPlat)
			}
		})
	}
}

// The whole point of the argv[0] plumbing: a `trellis ops` user must never
// be told to run a command they didn't type.
func TestRootLongUsesInvokedName(t *testing.T) {
	long := rootLong("trellis ops")
	if strings.Contains(long, "wp-ops") {
		t.Errorf("rootLong(\"trellis ops\") still mentions wp-ops:\n%s", long)
	}
	for _, want := range []string{"trellis ops list", "trellis ops doctor", "trellis ops --version"} {
		if !strings.Contains(long, want) {
			t.Errorf("rootLong missing %q:\n%s", want, long)
		}
	}
}

// Under bare wp-ops the help must be exactly what it was before the
// template — this is the regression guard on the rewrite.
func TestRootLongUnderWpOpsIsUnchanged(t *testing.T) {
	long := rootLong("wp-ops")
	for _, want := range []string{
		"wp-ops <category>/<command> [args...]   Run a command by its full key",
		"wp-ops <command> --where                Print the path to a command's script",
		"wp-ops list                             List every command by category",
		"wp-ops --version                        Show version",
	} {
		if !strings.Contains(long, want) {
			t.Errorf("rootLong(\"wp-ops\") missing exact line %q:\n%s", want, long)
		}
	}
	if strings.Contains(long, "trellis ops") {
		t.Error("rootLong(\"wp-ops\") leaked the plugin name")
	}
}

func TestFilterEntriesByPlatform(t *testing.T) {
	entries := []catalog.Entry{
		{Key: "trellis/backup/database-pull", Platform: "trellis"},
		{Key: "scripts/images/jpg-to-webp", Platform: "any"},
		{Key: "wp-cli/security/scanner", Platform: "wordpress"},
	}

	if got := filterEntriesByPlatform(entries, ""); len(got) != 3 {
		t.Errorf("empty platform must not filter: got %d, want 3", len(got))
	}

	got := filterEntriesByPlatform(entries, "trellis")
	if len(got) != 1 || got[0].Key != "trellis/backup/database-pull" {
		t.Errorf("platform trellis: got %v, want just the trellis entry", got)
	}
}
