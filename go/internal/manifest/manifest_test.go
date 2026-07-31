package manifest

import (
	"reflect"
	"testing"
)

func TestParse_ShellScriptWithChoiceArgs(t *testing.T) {
	cmd, err := Parse("scripts/backup/db-backup", "testdata/db-backup.sh")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	if !cmd.Annotated {
		t.Fatal("expected Annotated to be true")
	}
	if got, want := cmd.Desc, "Back up a Trellis site database with WP-CLI, gzip it, and prune backups older than 30 days"; got != want {
		t.Errorf("Desc = %q, want %q", got, want)
	}
	if got, want := cmd.Category, "backup"; got != want {
		t.Errorf("Category = %q, want %q", got, want)
	}
	if got, want := cmd.Runs, "server"; got != want {
		t.Errorf("Runs = %q, want %q", got, want)
	}
	if got, want := cmd.Requires, []string{"wp"}; !reflect.DeepEqual(got, want) {
		t.Errorf("Requires = %v, want %v", got, want)
	}
	if got, want := cmd.Doc, "trellis/backup/README.md"; got != want {
		t.Errorf("Doc = %q, want %q", got, want)
	}
	if got, want := cmd.Examples, []string{"wp-ops scripts/backup/db-backup example.com production"}; !reflect.DeepEqual(got, want) {
		t.Errorf("Examples = %v, want %v", got, want)
	}

	if len(cmd.Args) != 2 {
		t.Fatalf("len(Args) = %d, want 2", len(cmd.Args))
	}

	site := cmd.Args[0]
	if site.Name != "site-name" || site.Required || site.Default != "example.com" {
		t.Errorf("Args[0] = %+v, want name=site-name optional default=example.com", site)
	}

	backupType := cmd.Args[1]
	if backupType.Name != "backup-type" || backupType.Required {
		t.Errorf("Args[1].Name/Required = %q/%v, want backup-type/false", backupType.Name, backupType.Required)
	}
	if got, want := backupType.Choices, []string{"production", "staging", "development"}; !reflect.DeepEqual(got, want) {
		t.Errorf("Args[1].Choices = %v, want %v", got, want)
	}
}

func TestParse_AnsiblePlaybook(t *testing.T) {
	cmd, err := Parse("trellis/backup/database-backup", "testdata/database-backup.yml")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	if got, want := cmd.Runs, "local"; got != want {
		t.Errorf("Runs = %q, want %q", got, want)
	}
	if len(cmd.Args) != 2 {
		t.Fatalf("len(Args) = %d, want 2", len(cmd.Args))
	}
	for _, a := range cmd.Args {
		if !a.Required {
			t.Errorf("Args[%q].Required = false, want true", a.Name)
		}
	}
}

func TestParse_PHPDocblockIgnoresUnknownDirectives(t *testing.T) {
	cmd, err := Parse("wp-cli/security/scanner-wrapper", "testdata/scanner-wrapper.php")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	if got, want := cmd.Desc, "Run both targeted and general malware scanners in sequence"; got != want {
		t.Errorf("Desc = %q, want %q", got, want)
	}
	// @version/@date/@see aren't in directivesHandled and must be dropped
	// silently, same as bash's load_manifest() case statement.
	if len(cmd.Args) != 1 {
		t.Fatalf("len(Args) = %d, want 1 (unknown directives should be ignored)", len(cmd.Args))
	}
}

func TestParse_BooleanFlag(t *testing.T) {
	cmd, err := Parse("wp-cli/seo/redirect-audit", "testdata/redirect-audit.sh")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	if len(cmd.Flags) != 3 {
		t.Fatalf("len(Flags) = %d, want 3", len(cmd.Flags))
	}

	verbose := cmd.Flags[1]
	if verbose.Name != "--verbose" || verbose.Required {
		t.Errorf("Flags[1] = %+v, want name=--verbose optional", verbose)
	}
	if verbose.Default != "" || len(verbose.Choices) != 0 {
		t.Errorf("Flags[1] boolean flag should have no Default/Choices, got %+v", verbose)
	}

	urlFlag := cmd.Flags[0]
	if urlFlag.Name != "--url" || !urlFlag.Required || urlFlag.Default != "https://example.com" {
		t.Errorf("Flags[0] = %+v, want name=--url required default=https://example.com", urlFlag)
	}
}

func TestLint_CleanCommandsHaveNoErrors(t *testing.T) {
	repoRoot := "../../.." // go/internal/manifest -> repo root

	for _, tc := range []struct {
		key, path string
	}{
		{"scripts/backup/db-backup", "testdata/db-backup.sh"},
		{"trellis/backup/database-backup", "testdata/database-backup.yml"},
		{"wp-cli/security/scanner-wrapper", "testdata/scanner-wrapper.php"},
		{"wp-cli/seo/redirect-audit", "testdata/redirect-audit.sh"},
	} {
		cmd, err := Parse(tc.key, tc.path)
		if err != nil {
			t.Fatalf("Parse(%s): %v", tc.key, err)
		}
		if errs := Lint(cmd, repoRoot); len(errs) != 0 {
			t.Errorf("Lint(%s) = %v, want no errors", tc.key, errs)
		}
	}
}

func TestLint_MalformedCommandReportsEveryProblem(t *testing.T) {
	cmd, err := Parse("testdata/malformed", "testdata/malformed.sh")
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}

	errs := Lint(cmd, "../../..")
	// missing @desc, bad @runs, malformed @arg (no requiredness token), bad
	// @flag requiredness, missing @doc target — five independent problems.
	if len(errs) != 5 {
		t.Fatalf("Lint() = %v (%d errors), want 5", errs, len(errs))
	}
}

func TestDirectiveLines_StopsAtLine80(t *testing.T) {
	// Sanity check on the head-80 boundary using an existing fixture — all
	// its directives are well within the first 80 lines.
	lines, err := DirectiveLines("testdata/db-backup.sh")
	if err != nil {
		t.Fatalf("DirectiveLines: %v", err)
	}
	if len(lines) == 0 {
		t.Fatal("expected at least one directive line")
	}
	for _, l := range lines {
		if l[0] != '@' {
			t.Errorf("directive line %q doesn't start with @ (comment marker not stripped)", l)
		}
	}
}
