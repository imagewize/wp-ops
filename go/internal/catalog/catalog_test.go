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
	if len(c.Entries) != 76 {
		t.Errorf("len(Entries) = %d, want 76 (66 per docs/m3-go-skeleton.md acceptance criteria, +1 for mcp-server/run added in 3.25.0, +1 for scripts/backup/db-pull added in 3.26.0, +4 for ttfb-test/remote-ttfb-ua/import-page-draft/check-deny-ips added in 3.27.0, +4 for svg-to-jpg/svg-to-png/traffic-by-country/orphan-links-audit added in 4.1.0)", len(c.Entries))
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
	for _, want := range []string{"nginx", "troubleshooting"} {
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
	if len(scriptsRaw) != 41 {
		t.Errorf("CommandsIn(scripts) = %d entries, want 41 (directory-based grouping must be unaffected by the display split; +2 for ttfb-test/remote-ttfb-ua added in 3.27.0, +3 for svg-to-jpg/svg-to-png/traffic-by-country added in 4.1.0)", len(scriptsRaw))
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
	if len(backup) != 9 {
		t.Errorf("CommandsInDisplay(backup) = %d entries, want 9 (3 under scripts/, 6 under trellis/)", len(backup))
	}
	dirs := make(map[string]int)
	for _, e := range backup {
		dirs[e.Category]++
	}
	if dirs["scripts"] != 3 || dirs["trellis"] != 6 {
		t.Errorf("backup display group spans %v, want 3 scripts + 6 trellis", dirs)
	}
}
