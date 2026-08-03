package exec

import (
	"reflect"
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

func TestFormatHelp_AnnotatedPlaybook(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("trellis/backup/database-backup")
	if !ok {
		t.Fatal("trellis/backup/database-backup not found in catalog")
	}

	help := FormatHelp(e, "/srv/trellis-project")

	for _, want := range []string{
		"Usage: wp-ops trellis/backup/database-backup [args...]",
		e.Description,
		"Arguments:",
		"site",
		"env",
		"production|staging|development",
		"Requires: ansible-playbook",
		"Docs: trellis/backup/README.md",
		"Script: trellis/backup/database-backup.yml",
		"Runs via ansible-playbook against the Trellis project at $TRELLIS_DIR",
		"(currently: /srv/trellis-project)",
	} {
		if !strings.Contains(help, want) {
			t.Errorf("FormatHelp output missing %q:\n%s", want, help)
		}
	}
}

func TestFormatHelp_TrellisDirNotSet(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, _ := c.Lookup("trellis/backup/database-backup")

	help := FormatHelp(e, "")
	if !strings.Contains(help, "(currently: not set)") {
		t.Errorf("FormatHelp with empty trellisDir missing 'not set':\n%s", help)
	}
}

func testEntry() catalog.Entry {
	return catalog.Entry{
		Key:       "trellis/monitoring/security-scan",
		Annotated: true,
		Args: []manifest.Param{
			{Name: "site", Required: true, Description: "Site name as in wordpress_sites.yml"},
			{Name: "env", Required: true, Description: "Target environment"},
		},
		Flags: []manifest.Param{
			{Name: "hours", Description: "How many hours of log history to scan"},
			{Name: "threshold", Description: "Requests-per-IP alert threshold"},
		},
	}
}

func TestBuildPlaybookArgs_Positional(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), []string{"example.com", "production"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"-e", "site=example.com", "-e", "env=production"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestBuildPlaybookArgs_PositionalWithFlags(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), []string{
		"example.com", "production", "--hours", "48", "--threshold=50",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{
		"-e", "site=example.com",
		"-e", "env=production",
		"-e", "hours=48",
		"-e", "threshold=50",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestBuildPlaybookArgs_TrailingRawExtraVar(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), []string{
		"example.com", "production", "-e", "retention_days=10",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{
		"-e", "site=example.com",
		"-e", "env=production",
		"-e", "retention_days=10",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestBuildPlaybookArgs_LegacyRawPassthrough(t *testing.T) {
	raw := []string{"-e", "site=example.com", "-e", "env=production"}
	got, err := BuildPlaybookArgs(testEntry(), raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(got, raw) {
		t.Errorf("got %v, want unchanged %v", got, raw)
	}
}

func TestBuildPlaybookArgs_MissingRequiredArg(t *testing.T) {
	_, err := BuildPlaybookArgs(testEntry(), []string{"example.com"})
	if err == nil {
		t.Fatal("expected an error for a missing required argument, got nil")
	}
	if !strings.Contains(err.Error(), "<env>") {
		t.Errorf("error should name the missing argument <env>: %v", err)
	}
}

func TestBuildPlaybookArgs_MissingFlagValue(t *testing.T) {
	_, err := BuildPlaybookArgs(testEntry(), []string{"example.com", "production", "--hours"})
	if err == nil {
		t.Fatal("expected an error for a flag with no value, got nil")
	}
}

func TestBuildPlaybookArgs_EmptyArgs(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("got %v, want empty", got)
	}
}

func TestBuildPlaybookArgs_NoManifestArgsPassesThrough(t *testing.T) {
	e := catalog.Entry{Key: "trellis/backup/database-pull", Annotated: false}
	raw := []string{"example.com", "production"}
	got, err := BuildPlaybookArgs(e, raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(got, raw) {
		t.Errorf("got %v, want unchanged %v", got, raw)
	}
}

func TestBuildPlaybookArgs_RealCatalogEntry(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("trellis/backup/database-backup")
	if !ok {
		t.Fatal("trellis/backup/database-backup not found in catalog")
	}

	got, err := BuildPlaybookArgs(e, []string{"example.com", "production"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"-e", "site=example.com", "-e", "env=production"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}
