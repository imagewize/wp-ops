package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

// dbPull is the entry Phase G item G3 was written against: two positional
// arguments, the second with declared choices, which is the shape most of
// the catalog's argument lists take.
func dbPull() catalog.Entry {
	return catalog.Entry{
		Key:      "trellis/backup/database-pull",
		Platform: "trellis",
		Args: []manifest.Param{
			{Name: "site", Required: true, Default: "example.com", Description: "Site name as in wordpress_sites.yml"},
			{Name: "env", Required: true, Choices: []string{"production", "staging"}, Description: "Remote environment to pull from"},
		},
		Flags: []manifest.Param{
			{Name: "--delete", Description: "Remove files not present on the source"},
		},
	}
}

func hasCompletion(comps []cobra.Completion, value string) bool {
	for _, c := range comps {
		if c == value || strings.HasPrefix(c, value+"\t") {
			return true
		}
	}
	return false
}

func activeHelp(comps []cobra.Completion) []string {
	var out []string
	for _, c := range comps {
		if strings.HasPrefix(c, "_activeHelp_ ") {
			out = append(out, strings.TrimPrefix(c, "_activeHelp_ "))
		}
	}
	return out
}

// TestEntryArgCompletionsChoices is the headline case: `wp-ops db-pull
// example.com <TAB>` offers production and staging, straight off the
// @arg line's {production|staging}.
func TestEntryArgCompletionsChoices(t *testing.T) {
	comps, directive := entryArgCompletions(dbPull(), []string{"example.com"}, "")
	if directive != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("directive = %v, want ShellCompDirectiveNoFileComp", directive)
	}
	for _, want := range []string{"production", "staging"} {
		if !hasCompletion(comps, want) {
			t.Errorf("want %q among completions, got %v", want, comps)
		}
	}
	if len(activeHelp(comps)) != 0 {
		t.Errorf("real completions must not carry an ActiveHelp hint too, got %v", comps)
	}
}

// TestEntryArgCompletionsHintsWhenNoValues pins the other half: a slot with
// nothing concrete to offer still says what it wants, as ActiveHelp. The
// manifest's bracketed value is a placeholder ({example.com}), so it must
// appear as an example inside the hint and never as an insertable
// completion.
func TestEntryArgCompletionsHintsWhenNoValues(t *testing.T) {
	// No TRELLIS_DIR and a working directory outside any Trellis project,
	// so the site slot has no real values to offer.
	t.Setenv("TRELLIS_DIR", "")
	t.Chdir(t.TempDir())

	comps, directive := entryArgCompletions(dbPull(), nil, "")
	if directive != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("directive = %v, want ShellCompDirectiveNoFileComp", directive)
	}
	if hasCompletion(comps, "example.com") {
		t.Errorf("the {example.com} placeholder must not be offered as a value: %v", comps)
	}

	hints := activeHelp(comps)
	if len(hints) != 1 {
		t.Fatalf("want exactly one ActiveHelp hint, got %v", comps)
	}
	for _, want := range []string{"site", "(required)", "wordpress_sites.yml", "e.g. example.com"} {
		if !strings.Contains(hints[0], want) {
			t.Errorf("hint %q missing %q", hints[0], want)
		}
	}
}

// TestEntryArgCompletionsSiteNames covers the one slot whose real values
// live in the project rather than in the manifest.
func TestEntryArgCompletionsSiteNames(t *testing.T) {
	dir := t.TempDir()
	writeFakeTrellis(t, dir)
	t.Setenv("TRELLIS_DIR", dir)

	comps, _ := entryArgCompletions(dbPull(), nil, "")
	for _, want := range []string{"example.com", "shop.example.org"} {
		if !hasCompletion(comps, want) {
			t.Errorf("want site %q among completions, got %v", want, comps)
		}
	}
	if len(activeHelp(comps)) != 0 {
		t.Errorf("with real site names there should be no hint, got %v", comps)
	}
}

func TestEntryArgCompletionsFlags(t *testing.T) {
	comps, directive := entryArgCompletions(dbPull(), nil, "--")
	if directive != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("directive = %v, want ShellCompDirectiveNoFileComp", directive)
	}
	// The entry's own @flag, plus the two executeEntry handles for every
	// command regardless of executor.
	for _, want := range []string{"--delete", "--help", "--where"} {
		if !hasCompletion(comps, want) {
			t.Errorf("want %q among flag completions, got %v", want, comps)
		}
	}
}

// TestEntryArgCompletionsExhausted: past the declared arguments there is
// nothing to say, and file completion stays off rather than dumping the
// working directory into a slot the manifest never described.
func TestEntryArgCompletionsExhausted(t *testing.T) {
	comps, directive := entryArgCompletions(dbPull(), []string{"example.com", "production"}, "")
	if len(comps) != 0 {
		t.Errorf("want no completions past the last declared arg, got %v", comps)
	}
	if directive != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("directive = %v, want ShellCompDirectiveNoFileComp", directive)
	}

	noArgs := catalog.Entry{Key: "scripts/git/create-pr"}
	comps, directive = entryArgCompletions(noArgs, nil, "")
	if len(comps) != 0 || directive != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("an entry with no @arg lines: got %v / %v", comps, directive)
	}
}

// TestEntryArgCompletionsPathArgHandsBackToShell: a slot holding a
// filesystem path is worth less as a suppressed completion than as the
// shell's own file menu.
func TestEntryArgCompletionsPathArgHandsBackToShell(t *testing.T) {
	e := catalog.Entry{
		Key:  "scripts/images/jpg-to-webp",
		Args: []manifest.Param{{Name: "input", Required: true, Default: "input.jpg", Description: "Source JPG file"}},
	}
	comps, directive := entryArgCompletions(e, nil, "")
	if directive != cobra.ShellCompDirectiveDefault {
		t.Errorf("directive = %v, want ShellCompDirectiveDefault so the shell completes filenames", directive)
	}
	if len(activeHelp(comps)) != 1 {
		t.Errorf("want the hint alongside file completion, got %v", comps)
	}
}

func TestIsPathArg(t *testing.T) {
	for _, name := range []string{"path", "input", "output", "files", "draft-file", "output_file", "backup-dir", "source-dir"} {
		if !isPathArg(name) {
			t.Errorf("isPathArg(%q) = false, want true", name)
		}
	}
	for _, name := range []string{"site", "env", "hours", "domain", "url", "version", "pattern-slug"} {
		if isPathArg(name) {
			t.Errorf("isPathArg(%q) = true, want false", name)
		}
	}
}

// TestPositionalIndexSkipsFlags pins the documented approximation: flags
// are skipped, not parsed, because wp-ops re-parses no script's flag
// grammar and so cannot know which tokens are flag values.
func TestPositionalIndexSkipsFlags(t *testing.T) {
	cases := []struct {
		args []string
		want int
	}{
		{nil, 0},
		{[]string{"example.com"}, 1},
		{[]string{"example.com", "production"}, 2},
		{[]string{"--delete"}, 0},
		{[]string{"--delete", "example.com"}, 1},
		{[]string{"--dest=/tmp", "example.com"}, 1},
	}
	for _, tc := range cases {
		if got := positionalIndex(tc.args); got != tc.want {
			t.Errorf("positionalIndex(%v) = %d, want %d", tc.args, got, tc.want)
		}
	}
}

// TestResolveForCompletionAmbiguous: a basename shared by two entries is
// not completed, because the two may declare different arguments — and it
// wouldn't run either (printAmbiguous).
func TestResolveForCompletionAmbiguous(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("loading catalog: %v", err)
	}

	// Find a genuinely ambiguous basename rather than hardcoding one, so
	// this keeps testing the behaviour as the catalog changes.
	counts := map[string][]string{}
	for _, e := range c.Entries {
		b := filepath.Base(e.Key)
		counts[b] = append(counts[b], e.Key)
	}
	var ambiguous string
	for b, keys := range counts {
		if len(keys) > 1 {
			ambiguous = b
			break
		}
	}
	if ambiguous == "" {
		t.Skip("no ambiguous basename in the catalog right now")
	}

	if _, ok := resolveForCompletion(c, ambiguous); ok {
		t.Errorf("resolveForCompletion(%q) resolved, want no match for an ambiguous basename", ambiguous)
	}
	// The full key for the same command still resolves.
	if _, ok := resolveForCompletion(c, counts[ambiguous][0]); !ok {
		t.Errorf("resolveForCompletion(%q) failed on a full key", counts[ambiguous][0])
	}
}

// TestRootCompletionsReachArguments and its category twin are the
// end-to-end checks: these are the functions Cobra actually calls, and they
// are what `wp-ops db-pull <TAB>` and `wp-ops backup database-pull <TAB>`
// resolve through.
func TestRootCompletionsReachArguments(t *testing.T) {
	comps, _ := rootBasenameCompletions(nil, []string{"database-pull", "example.com"}, "")
	for _, want := range []string{"production", "staging"} {
		if !hasCompletion(comps, want) {
			t.Errorf("want %q from `wp-ops database-pull example.com <TAB>`, got %v", want, comps)
		}
	}
}

func TestCategoryCompletionsReachArguments(t *testing.T) {
	fn := categoryBasenameCompletions(displayScope("backup"))
	comps, _ := fn(nil, []string{"database-pull", "example.com"}, "")
	for _, want := range []string{"production", "staging"} {
		if !hasCompletion(comps, want) {
			t.Errorf("want %q from `wp-ops backup database-pull example.com <TAB>`, got %v", want, comps)
		}
	}
}

// TestCompletionSitesPrefersTrellisDirEnv mirrors resolveTrellisDir's own
// precedence, minus the confirmation prompt it must not inherit.
func TestCompletionSitesPrefersTrellisDirEnv(t *testing.T) {
	dir := t.TempDir()
	writeFakeTrellis(t, dir)
	t.Setenv("TRELLIS_DIR", dir)

	got := completionSites()
	if len(got) != 2 || got[0] != "example.com" || got[1] != "shop.example.org" {
		t.Errorf("completionSites() = %v, want the two sites from $TRELLIS_DIR, sorted", got)
	}
}

func writeFakeTrellis(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, "group_vars", "production"), 0o755); err != nil {
		t.Fatal(err)
	}
	sites := "wordpress_sites:\n" +
		"  example.com:\n" +
		"    site_hosts:\n" +
		"      - canonical: example.com\n" +
		"  shop.example.org:\n" +
		"    site_hosts:\n" +
		"      - canonical: shop.example.org\n"
	if err := os.WriteFile(filepath.Join(dir, "group_vars", "production", "wordpress_sites.yml"), []byte(sites), 0o644); err != nil {
		t.Fatal(err)
	}
}
