package catalog

import (
	"strings"
	"testing"
)

func TestLoad(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(c.Entries) != 75 {
		t.Errorf("len(Entries) = %d, want 75 (66 per docs/m3-go-skeleton.md acceptance criteria, +1 for mcp-server/run added in 3.25.0, +1 for scripts/backup/db-pull added in 3.26.0, +4 for ttfb-test/remote-ttfb-ua/import-page-draft/check-deny-ips added in 3.27.0, +4 for svg-to-jpg/svg-to-png/traffic-by-country/orphan-links-audit added in 4.1.0, -5 for wordpress-utilities' reference files demoted to docs in 5.0.0, +2 for admin-user-create/noindex-expired-posts replacing two of them, +1 for wp-db-backup added in 5.0.0, +1 for updraft-to-valet added in 5.9.0)", len(c.Entries))
	}
}

// TestMutatesFailsSafe pins the direction the @mutates default leans. The MCP
// server runs anything read-only without asking (isReadOnlyCommand in
// mcp-server/src/tools/catalog.ts), so a command that ends up marked read-only
// by accident is the failure that matters — a mutating one merely costs an
// extra confirmation. Both halves are asserted against real entries so this
// catches a generator change as well as a manifest edit.
func TestMutatesFailsSafe(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	for _, tc := range []struct {
		key         string
		wantMutates bool
	}{
		// Declares @mutates false: an audit that only reads and writes a report.
		{"wp-cli/seo/redirect-audit", false},
		// Writes a dump to disk and prunes older ones.
		{"scripts/backup/db-backup", true},
		// Imports a database over the top of an existing one.
		{"trellis/backup/database-push", true},
		// Creates a WordPress user.
		{"wp-cli/security/admin-user-create", true},
	} {
		e, ok := c.Lookup(tc.key)
		if !ok {
			t.Errorf("Lookup(%s) not found", tc.key)
			continue
		}
		if e.Mutates != tc.wantMutates {
			t.Errorf("%s Mutates = %v, want %v", tc.key, e.Mutates, tc.wantMutates)
		}
	}

	// A command with no manifest at all has nobody's judgement behind it, so
	// it must never come out read-only.
	for _, e := range c.Entries {
		if !e.Annotated && !e.Mutates {
			t.Errorf("%s is unannotated but marked read-only", e.Key)
		}
	}
}

func TestLookup(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	e, ok := c.Lookup("scripts/backup/db-backup")
	if !ok {
		t.Fatal("Lookup(scripts/backup/db-backup) not found")
	}
	if e.RunsOn != "local" {
		t.Errorf("RunsOn = %q, want local", e.RunsOn)
	}

	if _, ok := c.Lookup("does/not/exist"); ok {
		t.Error("Lookup(does/not/exist) found, want not found")
	}
}

// TestFilesPullExposesDeleteFlag guards catalog.json staying in step with
// trellis/backup/files-pull.yml's manifest: the entry is what turns
// `--delete yes` into `-e delete=yes` (exec.BuildPlaybookArgs) and what
// --help prints, so a manifest edit landing without a `go generate
// ./internal/catalog` leaves the flag silently undocumented and untranslated.
func TestFilesPullExposesDeleteFlag(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	e, ok := c.Lookup("trellis/backup/files-pull")
	if !ok {
		t.Fatal("Lookup(trellis/backup/files-pull) not found")
	}
	for _, f := range e.Flags {
		if f.Name == "delete" {
			if f.Required {
				t.Error("delete flag is required, want optional (a pull is additive by default)")
			}
			return
		}
	}
	t.Errorf("files-pull flags = %v, want one named delete (run `go generate ./internal/catalog`)", e.Flags)
}

func TestFindByBasename(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	matches := c.FindByBasename("db-backup")
	if len(matches) != 1 || matches[0].Key != "scripts/backup/db-backup" {
		t.Errorf("FindByBasename(db-backup) = %v, want exactly [scripts/backup/db-backup]", matches)
	}
}

func TestSearch(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	matches := c.Search("database")
	if len(matches) == 0 {
		t.Fatal("Search(database) returned no results")
	}
	for _, m := range matches {
		key, desc := strings.ToLower(m.Key), strings.ToLower(m.Description)
		if !strings.Contains(key, "database") && !strings.Contains(desc, "database") {
			t.Errorf("Search(database) matched %q, but neither key nor description contains it", m.Key)
		}
	}
}

func TestCategoriesSkipsEmpty(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	cats := c.Categories()
	// Option D moved these three under docs/ and dropped them from
	// Categories outright — nginx and troubleshooting never carried a
	// command, and bedrock became documentation once its one command moved
	// to wp-cli/. Still asserted so re-adding one without commands is caught.
	for _, want := range []string{"nginx", "troubleshooting", "bedrock", "wordpress-utilities"} {
		for _, got := range cats {
			if got == want {
				t.Errorf("Categories() included docs-only category %q, want excluded (no runnable commands)", want)
			}
		}
	}
}

// TestDisplayCategoriesAreDomains covers Option C1
// (docs/category-organization.md): DisplayCategories() reports @category
// domains, not directories, subject to the same emptiness rule as
// Categories(). The directory names must not appear — they'd render as
// empty groups now that every command's domain tag wins.
func TestDisplayCategoriesAreDomains(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	cats := c.DisplayCategories()
	for _, want := range []string{"monitoring", "backup", "content", "images", "seo", "security"} {
		found := false
		for _, got := range cats {
			if got == want {
				found = true
			}
		}
		if !found {
			t.Errorf("DisplayCategories() = %v, want it to include domain category %q", cats, want)
		}
	}
	// "mcp-server" is deliberately absent from this list: it's the one name
	// that is both a directory and a domain, so it legitimately appears.
	for _, want := range []string{"scripts", "trellis", "wp-cli", "bedrock", "wordpress-utilities", "nginx", "troubleshooting"} {
		for _, got := range cats {
			if got == want {
				t.Errorf("DisplayCategories() included directory category %q, want excluded (domains only)", want)
			}
		}
	}
}

// TestCommandsInDisplayPreservesCategoryForJSON is the stability guarantee
// behind the DisplayCategory split: --json (printJSON) reads Categories()/
// CommandsIn() directly and must keep reporting the directory-based
// grouping external tooling depends on, so splitting "scripts" for
// human-facing views must never touch the underlying Category field or the
// byCategory grouping it drives.
func TestCommandsInDisplayPreservesCategoryForJSON(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	scriptsRaw := c.CommandsIn("scripts")
	if len(scriptsRaw) != 43 {
		t.Errorf("CommandsIn(scripts) = %d entries, want 43 (directory-based grouping must be unaffected by the display split; +2 for ttfb-test/remote-ttfb-ua added in 3.27.0, +3 for svg-to-jpg/svg-to-png/traffic-by-country added in 4.1.0, +1 for wp-db-backup added in 5.0.0, +1 for updraft-to-valet added in 5.9.0)", len(scriptsRaw))
	}
	for _, e := range scriptsRaw {
		if e.Category != "scripts" {
			t.Errorf("CommandsIn(scripts) returned %q with Category = %q, want scripts", e.Key, e.Category)
		}
	}

	// Post-Option-C1 the directory name is no longer a display category at
	// all: every scripts/** command groups under its own @category domain.
	if got := c.CommandsInDisplay("scripts"); len(got) != 0 {
		t.Errorf("CommandsInDisplay(scripts) = %d entries, want 0 (directories are no longer display categories)", len(got))
	}

	// The invariant the whole DisplayCategory split exists to protect, now
	// stated directly rather than via a category that happened to be
	// single-directory: Category is always the key's leading path segment,
	// whatever DisplayCategory the entry was grouped under.
	for _, e := range c.Entries {
		wantCategory, _, ok := strings.Cut(e.Key, "/")
		if !ok {
			t.Errorf("entry %q has no directory segment in its key", e.Key)
			continue
		}
		if e.Category != wantCategory {
			t.Errorf("entry %q has Category = %q, want %q (DisplayCategory %q must not leak into Category)",
				e.Key, e.Category, wantCategory, e.DisplayCategory)
		}
	}

	// Option C1's headline case: "backup" draws from two directories at
	// once, which is exactly what the old scripts-only rule prevented.
	backup := c.CommandsInDisplay("backup")
	if len(backup) != 10 {
		t.Errorf("CommandsInDisplay(backup) = %d entries, want 10 (4 under scripts/, 6 under trellis/)", len(backup))
	}
	dirs := make(map[string]int)
	for _, e := range backup {
		dirs[e.Category]++
	}
	if dirs["scripts"] != 4 || dirs["trellis"] != 6 {
		t.Errorf("backup display group spans %v, want 4 scripts + 6 trellis", dirs)
	}

	// Step 6 of docs/category-organization.md: the backup group is no longer
	// uniformly Trellis-shaped. Guards the coverage hole staying closed —
	// before wp-db-backup, `--platform wordpress` returned zero of these.
	wpBackups := 0
	for _, e := range backup {
		if e.Platform == "wordpress" {
			wpBackups++
		}
	}
	if wpBackups < 1 {
		t.Error("no @platform wordpress backup command — a non-Trellis site has no backup path")
	}
}

// TestLoad_ShortNameUniqueBasenames pins the name every user-facing usage
// line is built from: the basename when it resolves to exactly one command,
// the full key when it does not. A collision has no unambiguous short form —
// dispatch reports those as ambiguous rather than picking one — so printing
// the basename would produce a usage line that errors if pasted back.
func TestLoad_ShortNameUniqueBasenames(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	for _, e := range c.Entries {
		if e.ShortName == "" {
			t.Fatalf("%s: ShortName is empty; Load must populate it", e.Key)
		}

		matches := c.FindByBasename(e.ShortName)
		switch {
		case e.ShortName == e.Key:
			// Fell back to the key, so the basename must genuinely collide.
			base := e.Key[strings.LastIndex(e.Key, "/")+1:]
			if n := len(c.FindByBasename(base)); n < 2 && base != e.Key {
				t.Errorf("%s: fell back to the full key but %q resolves to %d command(s), not several",
					e.Key, base, n)
			}
		case len(matches) != 1:
			t.Errorf("%s: ShortName %q resolves to %d commands, want exactly 1",
				e.Key, e.ShortName, len(matches))
		case matches[0].Key != e.Key:
			t.Errorf("%s: ShortName %q resolves to %s", e.Key, e.ShortName, matches[0].Key)
		}
	}
}

// exampleCommandToken returns the token an @example tells the reader to type:
// the word after "wp-ops", skipping any leading VAR=value environment prefixes
// (screenshot-patterns' example opens with two). Returns "" for an example that
// is not a wp-ops invocation at all, which the caller skips.
func exampleCommandToken(ex string) string {
	fields := strings.Fields(ex)
	for i, f := range fields {
		if f != "wp-ops" {
			// Only an environment assignment may precede the binary.
			if eq := strings.Index(f, "="); eq > 0 && !strings.ContainsAny(f[:eq], "/-.") {
				continue
			}
			return ""
		}
		if i+1 < len(fields) {
			return fields[i+1]
		}
		return ""
	}
	return ""
}

// TestExamplesNameTheCommand pins the other half of what a user reads. The
// usage line is generated from ShortName, so it cannot be wrong; an @example is
// prose copied verbatim out of a shell comment, and prose goes stale at every
// rename. An example whose command token is not this entry's ShortName either
// names an internal key that the usage line three rows above just contradicted,
// or — as wp-cli-pattern-validate's did between 5.0.0 and 5.1.1 — names a
// category that no longer exists at all.
//
// Deliberately not enforced: that an example mentions only its own command.
// check-deny-ips legitimately pipes into check-ips, and banning that would need
// a whitelist. The first-token rule covers the actual bug.
func TestExamplesNameTheCommand(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	for _, e := range c.Entries {
		for _, ex := range e.Examples {
			tok := exampleCommandToken(ex)
			if tok == "" || tok == e.ShortName {
				continue
			}
			t.Errorf("%s: example names %q, but this command is typed as %q\n    %s",
				e.Key, tok, e.ShortName, ex)
		}
	}
}
