package exec

import (
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

func helpTestEntry() catalog.Entry {
	return catalog.Entry{
		Key:         "scripts/monitoring/404-checker",
		ScriptPath:  "scripts/monitoring/404-checker.sh",
		Description: "Check a site's internal links for broken responses",
		Annotated:   true,
		Platform:    "any",
		Requires:    []string{"curl"},
		Args: []manifest.Param{
			{Name: "site-url", RequiredRaw: "required", Required: true, Default: "https://example.com", Description: "Site to check"},
			{Name: "depth", RequiredRaw: "optional", Description: "How deep to crawl"},
		},
		Flags: []manifest.Param{
			{Name: "--mode", RequiredRaw: "optional", Choices: []string{"global", "spider"}, Description: "Crawl mode"},
		},
	}
}

// TestUsageLine_RequiredAndOptional pins the trellis-shaped usage line:
// required arguments in angle brackets, optional in square, and a single
// "[options]" standing in for the flag list rather than spelling it out.
func TestUsageLine_RequiredAndOptional(t *testing.T) {
	got := UsageLine(helpTestEntry(), "404-checker")
	want := "Usage: wp-ops 404-checker <site-url> [depth] [options]"
	if got != want {
		t.Errorf("UsageLine() = %q, want %q", got, want)
	}
}

// TestUsageLine_UsesGivenName is the whole reason name is a parameter: the
// picker shows the basename a user can type, not the internal catalog key.
func TestUsageLine_UsesGivenName(t *testing.T) {
	e := helpTestEntry()
	if got := UsageLine(e, e.Key); !strings.Contains(got, "wp-ops scripts/monitoring/404-checker ") {
		t.Errorf("UsageLine() with full key = %q, want it to use the key verbatim", got)
	}
}

// TestUsageLine_NoDeclaredParams covers un-annotated commands and annotated
// ones taking nothing: both still forward a free-text argv, so the usage
// line has to say so rather than implying the command accepts no arguments.
func TestUsageLine_NoDeclaredParams(t *testing.T) {
	got := UsageLine(catalog.Entry{Key: "mcp-server/dev"}, "dev")
	want := "Usage: wp-ops dev [args...]"
	if got != want {
		t.Errorf("UsageLine() = %q, want %q", got, want)
	}
}

// TestDetailBody_SectionOrder pins the ordering the picker depends on. The
// detail viewport is roughly 14 rows and a real command runs past it, so what
// sits above the fold matters: requirements ("needs curl", "runs on the
// server") decide whether to run the command at all, and a worked example is
// the most actionable thing for someone about to type an argument. The
// exhaustive per-parameter tables are what can afford to scroll — the reverse
// of --help's ordering, and the same shape trellis-cli's help uses.
func TestDetailBody_SectionOrder(t *testing.T) {
	e := helpTestEntry()
	e.Examples = []string{"wp-ops 404-checker https://example.com"}
	body := DetailBody(e, "404-checker")

	requires := strings.Index(body, "Requires: curl")
	examples := strings.Index(body, "Examples:")
	args := strings.Index(body, "Arguments:")
	opts := strings.Index(body, "Options:")

	if requires < 0 || examples < 0 || args < 0 || opts < 0 {
		t.Fatalf("DetailBody() missing a section:\n%s", body)
	}
	if !(requires < examples && examples < args && args < opts) {
		t.Errorf("DetailBody() sections out of order (requires=%d examples=%d args=%d options=%d):\n%s",
			requires, examples, args, opts, body)
	}
}

// TestDetailBody_MetaLineCarriesRowTags covers the facts that moved here
// when the browse list dropped its per-row "[platform]" and "(server)"
// tags — they overflowed the row and broke the column alignment, so this
// block is now the only place they are stated.
func TestDetailBody_MetaLineCarriesRowTags(t *testing.T) {
	e := helpTestEntry()
	e.Platform = "trellis"
	e.RunsOn = "server"

	body := DetailBody(e, "404-checker")
	for _, want := range []string{"Requires: curl", "Platform: trellis", "Runs on the server"} {
		if !strings.Contains(body, want) {
			t.Errorf("DetailBody() missing %q:\n%s", want, body)
		}
	}
}

// TestDetailBody_OmitsScriptPath — the script's location on disk is an
// implementation detail at the moment someone is about to type "site-url:",
// and the block competes for a bounded number of rows.
func TestDetailBody_OmitsScriptPath(t *testing.T) {
	if body := DetailBody(helpTestEntry(), "404-checker"); strings.Contains(body, "404-checker.sh") {
		t.Errorf("DetailBody() leaked the script path:\n%s", body)
	}
}
