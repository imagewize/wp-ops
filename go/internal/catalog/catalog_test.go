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
	if len(c.Entries) != 68 {
		t.Errorf("len(Entries) = %d, want 68 (66 per docs/m3-go-skeleton.md acceptance criteria, +1 for mcp-server/run added in 3.25.0, +1 for scripts/backup/db-pull added in 3.26.0)", len(c.Entries))
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
	if e.RunsOn != "server" {
		t.Errorf("RunsOn = %q, want server", e.RunsOn)
	}

	if _, ok := c.Lookup("does/not/exist"); ok {
		t.Error("Lookup(does/not/exist) found, want not found")
	}
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

// TestDisplayCategoriesIncludesScriptsSplit covers Phase F option 4
// (docs/cli-ux-plan.md): the scripts/** subcategories promoted to their own
// DisplayCategory must show up in DisplayCategories(), same emptiness rule
// as Categories().
func TestDisplayCategoriesIncludesScriptsSplit(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	cats := c.DisplayCategories()
	for _, want := range []string{"monitoring", "images", "patterns", "release"} {
		found := false
		for _, got := range cats {
			if got == want {
				found = true
			}
		}
		if !found {
			t.Errorf("DisplayCategories() = %v, want it to include split-out category %q", cats, want)
		}
	}
	for _, want := range []string{"nginx", "troubleshooting"} {
		for _, got := range cats {
			if got == want {
				t.Errorf("DisplayCategories() included docs-only category %q, want excluded", want)
			}
		}
	}
}

// TestCommandsInDisplayPreservesCategoryForJSON is the parity guarantee
// behind the DisplayCategory split: --json (printJSON) reads Categories()/
// CommandsIn() directly and must stay byte-for-byte identical to bash's
// directory-based grouping (go/scripts/parity-check.sh), so splitting
// "scripts" for human-facing views must never touch the underlying
// Category field or the byCategory grouping it drives.
func TestCommandsInDisplayPreservesCategoryForJSON(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	scriptsRaw := c.CommandsIn("scripts")
	if len(scriptsRaw) != 36 {
		t.Errorf("CommandsIn(scripts) = %d entries, want 36 (directory-based grouping must be unaffected by the display split)", len(scriptsRaw))
	}
	for _, e := range scriptsRaw {
		if e.Category != "scripts" {
			t.Errorf("CommandsIn(scripts) returned %q with Category = %q, want scripts", e.Key, e.Category)
		}
	}

	scriptsDisplay := c.CommandsInDisplay("scripts")
	if len(scriptsDisplay) != 12 {
		t.Errorf("CommandsInDisplay(scripts) = %d entries, want 12 (backup, git, misc, sync, woocommerce)", len(scriptsDisplay))
	}

	monitoring := c.CommandsInDisplay("monitoring")
	if len(monitoring) != 10 {
		t.Errorf("CommandsInDisplay(monitoring) = %d entries, want 10", len(monitoring))
	}
	for _, e := range monitoring {
		if e.Category != "scripts" {
			t.Errorf("CommandsInDisplay(monitoring) entry %q has Category = %q, want scripts (DisplayCategory must not leak into Category)", e.Key, e.Category)
		}
	}
}
