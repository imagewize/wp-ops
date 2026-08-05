package ui

import (
	"testing"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

func testCatalogEntries() []catalog.Entry {
	return []catalog.Entry{
		{Category: "scripts", DisplayCategory: "scripts", Key: "scripts/backup/db-backup", Description: "Back up a database"},
		{Category: "scripts", DisplayCategory: "monitoring", Key: "scripts/monitoring/traffic-monitor", Description: "Analyze traffic"},
		{Category: "trellis", DisplayCategory: "trellis", Key: "trellis/backup/database-backup", Description: "Ansible db backup"},
	}
}

// newTestCategoryModel builds a Model at stageCategory without going through
// New() (which needs a fully-indexed *catalog.Catalog from catalog.Load() to
// populate DisplayCategories() — see buildCategoryOptions). updateCategory's
// filter path only touches m.all/m.browseCategory/m.filterQuery and
// filterEntries (which works directly off a bare Entries slice, same trick
// filterEntries itself uses), so a hand-built Model exercises the same code
// path without the real embedded catalog.
func newTestCategoryModel() Model {
	return Model{
		all:    testCatalogEntries(),
		stage:  stageCategory,
		detail: viewport.New(fallbackWidth, minPaneHeight),
	}
}

// TestUpdateCategoryTypingJumpsToBrowse covers the type-to-search fix
// (docs/cli-ux-plan.md, Phase F "Also fixed alongside (4)"): Phase F option
// 3 made stageCategory the picker's default screen but left typing a no-op
// there, so a keypress had to go through arrow+Enter on "All categories"
// first before search worked at all. Typing anywhere on this screen must
// now jump straight into stageBrowse, unscoped, filtered to what was typed.
func TestUpdateCategoryTypingJumpsToBrowse(t *testing.T) {
	m := newTestCategoryModel()

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("db-backup")})
	m2 := updated.(Model)

	if m2.stage != stageBrowse {
		t.Errorf("stage = %v, want stageBrowse", m2.stage)
	}
	if m2.browseCategory != "" {
		t.Errorf("browseCategory = %q, want empty (unscoped / All categories)", m2.browseCategory)
	}
	if string(m2.filterQuery) != "db-backup" {
		t.Errorf("filterQuery = %q, want %q", string(m2.filterQuery), "db-backup")
	}
	if len(m2.filtered) != 1 || m2.filtered[0].Key != "scripts/backup/db-backup" {
		t.Errorf("filtered = %v, want exactly [scripts/backup/db-backup]", m2.filtered)
	}
}

// TestUpdateCategorySpaceKeyFilters checks the KeySpace branch specifically,
// since space arrives as its own tea.KeyMsg type rather than tea.KeyRunes.
func TestUpdateCategorySpaceKeyFilters(t *testing.T) {
	m := newTestCategoryModel()

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeySpace})
	m2 := updated.(Model)

	if m2.stage != stageBrowse {
		t.Errorf("stage = %v, want stageBrowse", m2.stage)
	}
	if string(m2.filterQuery) != " " {
		t.Errorf("filterQuery = %q, want a single space", string(m2.filterQuery))
	}
}

// TestUpdateCategoryArrowsStillNavigate is a regression guard: the
// type-to-search fix must not disturb arrow-key category navigation, the
// behavior Phase F option 3 added.
func TestUpdateCategoryArrowsStillNavigate(t *testing.T) {
	m := newTestCategoryModel()
	m.categories = []categoryOption{{label: "All categories"}, {key: "scripts", label: "Scripts"}, {key: "trellis", label: "Trellis"}}

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m2 := updated.(Model)

	if m2.stage != stageCategory {
		t.Errorf("stage after arrow key = %v, want still stageCategory", m2.stage)
	}
	if m2.catCursor != 1 {
		t.Errorf("catCursor = %d, want 1", m2.catCursor)
	}
}

// TestUpdateCategoryEnterEntersScopedBrowse is a regression guard for Phase
// F option 3's category drill-down, which the type-to-search fix sits
// alongside in the same Update switch.
func TestUpdateCategoryEnterEntersScopedBrowse(t *testing.T) {
	m := newTestCategoryModel()
	m.categories = []categoryOption{{label: "All categories"}, {key: "monitoring", label: "Monitoring"}}
	m.catCursor = 1

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m2 := updated.(Model)

	if m2.stage != stageBrowse {
		t.Errorf("stage = %v, want stageBrowse", m2.stage)
	}
	if m2.browseCategory != "monitoring" {
		t.Errorf("browseCategory = %q, want monitoring", m2.browseCategory)
	}
	if len(m2.filtered) != 1 || m2.filtered[0].Key != "scripts/monitoring/traffic-monitor" {
		t.Errorf("filtered = %v, want exactly [scripts/monitoring/traffic-monitor]", m2.filtered)
	}
}
