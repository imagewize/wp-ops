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
	if len(c.Entries) != 66 {
		t.Errorf("len(Entries) = %d, want 66 (see docs/m3-go-skeleton.md acceptance criteria)", len(c.Entries))
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
