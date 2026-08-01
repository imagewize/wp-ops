package exec

import (
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
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
