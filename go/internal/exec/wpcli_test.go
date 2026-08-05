package exec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

func TestRegisteredWPCommand_WPCLICommandClass(t *testing.T) {
	path := filepath.Join(t.TempDir(), "wp-cli-pattern-validate.php")
	writeFile(t, path, `<?php
class Pattern_Validate_Command extends WP_CLI_Command {
	public function validate( $args, $assoc_args ) {}
}
WP_CLI::add_command( 'pattern validate', array( $_cmd, 'validate' ) );
`)

	if got := RegisteredWPCommand(path); got != "pattern validate" {
		t.Errorf("RegisteredWPCommand = %q, want %q", got, "pattern validate")
	}
}

func TestRegisteredWPCommand_PlainScript(t *testing.T) {
	path := filepath.Join(t.TempDir(), "scanner-targeted.php")
	writeFile(t, path, `<?php
// A plain top-to-bottom script, no WP_CLI_Command subclass.
echo "scanning...";
`)

	if got := RegisteredWPCommand(path); got != "" {
		t.Errorf("RegisteredWPCommand = %q, want empty", got)
	}
}

func TestRegisteredWPCommand_MissingFile(t *testing.T) {
	if got := RegisteredWPCommand(filepath.Join(t.TempDir(), "does-not-exist.php")); got != "" {
		t.Errorf("RegisteredWPCommand = %q, want empty", got)
	}
}

func writeFile(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatalf("writing fixture: %v", err)
	}
}

func TestFormatWPCLIHelp_EvalFile(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("wp-cli/security/scanner-targeted")
	if !ok {
		t.Fatal("wp-cli/security/scanner-targeted not found in catalog")
	}

	help := FormatWPCLIHelp(e, "/srv/www/example.com/current", "")

	for _, want := range []string{
		"Usage: wp-ops wp-cli/security/scanner-targeted [args...]",
		e.Description,
		"Arguments:",
		"Requires: wp",
		"Runs via WP-CLI against the site at $WP_SITE_DIR (currently: /srv/www/example.com/current)",
		"Runs as: wp eval-file scanner-targeted.php [args...]",
	} {
		if !strings.Contains(help, want) {
			t.Errorf("FormatWPCLIHelp output missing %q:\n%s", want, help)
		}
	}
}

func TestFormatWPCLIHelp_RequireCommand(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("wp-cli/content-creation/wp-cli-pattern-validate")
	if !ok {
		t.Fatal("wp-cli/content-creation/wp-cli-pattern-validate not found in catalog")
	}

	help := FormatWPCLIHelp(e, "/srv/www/example.com/current", "pattern validate")

	if !strings.Contains(help, "Runs as: wp --require=wp-cli-pattern-validate.php pattern validate [args...]") {
		t.Errorf("FormatWPCLIHelp missing --require line:\n%s", help)
	}
}

func TestFormatWPCLIHelp_SiteDirNotSet(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, _ := c.Lookup("wp-cli/security/scanner-targeted")

	help := FormatWPCLIHelp(e, "", "")
	if !strings.Contains(help, "(currently: not set)") {
		t.Errorf("FormatWPCLIHelp with empty wpSiteDir missing 'not set':\n%s", help)
	}
}
