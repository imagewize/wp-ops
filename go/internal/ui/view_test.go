package ui

import (
	"strings"
	"testing"

	"github.com/charmbracelet/bubbles/viewport"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

func browseModel(width int, entries []catalog.Entry) Model {
	m := Model{
		all:      entries,
		filtered: entries,
		stage:    stageBrowse,
		width:    width,
		height:   40,
		detail:   viewport.New(width, minPaneHeight),
	}
	return m
}

func longRowEntries() []catalog.Entry {
	return []catalog.Entry{
		{Key: "scripts/monitoring/updown-webhook-handler", DisplayCategory: "monitoring", RunsOn: "server", Platform: "trellis",
			Description: "Analyze Nginx logs on the server when updown.io reports downtime for a site"},
		{Key: "scripts/monitoring/ttfb-test", DisplayCategory: "monitoring", Platform: "any",
			Description: "Measure TTFB for a URL over several requests and write a report"},
	}
}

// TestViewBrowse_RowsFitTerminalWidth is the regression test for the layout
// bug this view was rewritten to fix. Rows used to be built as a 28-column
// name plus "[platform]" plus "(server)" — about 43 columns — and rendered
// into a pane of m.width*2/5, so on any terminal narrower than ~118 columns
// lipgloss wrapped every tagged row and the tags landed in the left margin
// of the following line. No row may exceed the terminal width, at any width.
func TestViewBrowse_RowsFitTerminalWidth(t *testing.T) {
	for _, width := range []int{60, 80, 100, 140} {
		m := browseModel(width, longRowEntries())
		for _, line := range strings.Split(m.viewBrowse(), "\n") {
			if n := len([]rune(stripANSI(line))); n > width {
				t.Errorf("width %d: row of %d cells overflows:\n%q", width, n, line)
			}
		}
	}
}

// TestViewBrowse_ServerTagSurvivesNarrowTerminal — "(server)" is the one row
// tag kept from the old layout, because "this will not run against your
// local site" is worth knowing while still scanning the list. It has to
// still be there at a normal width, and it has to yield to the description
// rather than overflow when the terminal is too narrow for both.
func TestViewBrowse_ServerTagSurvivesNarrowTerminal(t *testing.T) {
	if out := browseModel(100, longRowEntries()).viewBrowse(); !strings.Contains(out, "(server)") {
		t.Errorf("viewBrowse() at 100 cols dropped the (server) tag:\n%s", out)
	}

	m := browseModel(30, longRowEntries())
	for _, line := range strings.Split(m.viewBrowse(), "\n") {
		if n := len([]rune(stripANSI(line))); n > 30 {
			t.Errorf("width 30: row of %d cells overflows:\n%q", n, line)
		}
	}
}

// TestViewBrowse_PlatformBadge reverses an earlier decision, deliberately.
// Platform tags were dropped from this list when rows shared the terminal
// with a bordered preview pane and could not fit; that pane is gone, the
// columns are measured rather than assumed (see the width test above), and
// the list being silent about platform meant "does this need Trellis?" was
// only answerable after committing to a command. Phase G1,
// docs/cli-ux-plan.md.
func TestViewBrowse_PlatformBadge(t *testing.T) {
	out := browseModel(140, longRowEntries()).viewBrowse()
	for _, badge := range []string{"trellis", "any"} {
		if !strings.Contains(stripANSI(out), badge) {
			t.Errorf("viewBrowse() is missing the %q platform badge:\n%s", badge, out)
		}
	}

	wp := []catalog.Entry{{Key: "wp-cli/seo/redirect-audit", DisplayCategory: "seo", Platform: "wordpress",
		Description: "Audit redirects"}}
	if out := stripANSI(browseModel(140, wp).viewBrowse()); !strings.Contains(out, "wp") {
		t.Errorf("viewBrowse() is missing the wordpress badge:\n%s", out)
	}
}

// TestBrowseLayout_TagsYieldToDescription — the columns that overflowed the
// old layout now give way instead. Platform outranks server because every
// row carries a platform; both go before the description drops under
// minDescWidth.
func TestBrowseLayout_TagsYieldToDescription(t *testing.T) {
	entries := longRowEntries()

	wide := browseModel(140, entries).browseLayout(0, len(entries))
	if !wide.showPlatform || !wide.showServer {
		t.Errorf("at 140 cols both tag columns should fit, got %+v", wide)
	}

	narrow := browseModel(60, entries).browseLayout(0, len(entries))
	if !narrow.showPlatform {
		t.Errorf("at 60 cols platform should outlast the server column, got %+v", narrow)
	}
	if narrow.showServer {
		t.Errorf("at 60 cols the server column should have yielded, got %+v", narrow)
	}

	tiny := browseModel(36, entries).browseLayout(0, len(entries))
	if tiny.showPlatform || tiny.showServer {
		t.Errorf("at 36 cols both tag columns should yield, got %+v", tiny)
	}
	if tiny.descW < 1 {
		t.Errorf("descW = %d, want at least 1", tiny.descW)
	}
}

// TestBrowseLayout_ServerColumnOnlyWhenNeeded — 7 of 80 commands are
// @runs server, so reserving the column on every screen would cost every
// description nine cells for a tag almost no row uses.
func TestBrowseLayout_ServerColumnOnlyWhenNeeded(t *testing.T) {
	local := []catalog.Entry{
		{Key: "scripts/images/jpg-to-webp", Platform: "any", Description: "Convert JPG to WebP"},
	}
	if l := browseModel(140, local).browseLayout(0, 1); l.showServer {
		t.Errorf("no visible row runs on the server, but the column was reserved: %+v", l)
	}
}

// TestViewCategory_PlatformMix — the category screen's whole job is to point
// you at a category, and "can I run any of this here?" is part of that
// choice. Phase G2, docs/cli-ux-plan.md.
func TestViewCategory_PlatformMix(t *testing.T) {
	m := Model{
		stage:  stageCategory,
		width:  120,
		height: 40,
		categories: []categoryOption{
			{label: "All categories", count: 3, blurb: "Search or browse the whole catalog",
				mix: platformMix{trellis: 2, wordpress: 1}},
			{key: "backup", label: "Backup", count: 2, blurb: "Database and file backups",
				mix: platformMix{trellis: 2}},
		},
	}

	out := stripANSI(m.viewCategory())
	if !strings.Contains(out, " 2 trellis") {
		t.Errorf("viewCategory() is missing the trellis count:\n%s", out)
	}
	if !strings.Contains(out, " 1 wp") {
		t.Errorf("viewCategory() is missing the wordpress count:\n%s", out)
	}
	// A zero count renders as blanks, not "0 any" — a category with nothing
	// for a platform should read as empty space, not as a row of noise.
	if strings.Contains(out, "0 any") {
		t.Errorf("viewCategory() rendered a zero count:\n%s", out)
	}

	for _, line := range strings.Split(out, "\n") {
		if n := len([]rune(line)); n > 120 {
			t.Errorf("category row of %d cells overflows 120:\n%q", n, line)
		}
	}
}

// TestCategoryLayout_MixYieldsToBlurb — on a terminal too narrow to carry
// both, the blurb keeps the room: the mix is a refinement, the blurb is what
// tells you what the category is.
func TestCategoryLayout_MixYieldsToBlurb(t *testing.T) {
	opts := []categoryOption{{label: "All categories", count: 80, blurb: "Search or browse the whole catalog"}}

	if l := (Model{width: 120, categories: opts}).categoryLayout(); !l.showMix {
		t.Errorf("at 120 cols the mix column should fit, got %+v", l)
	}
	l := (Model{width: 70, categories: opts}).categoryLayout()
	if l.showMix {
		t.Errorf("at 70 cols the mix column should have yielded, got %+v", l)
	}
	if l.blurbW < minBlurbWidth {
		t.Errorf("blurbW = %d, want at least %d once the mix yields", l.blurbW, minBlurbWidth)
	}
}

// TestCategoryLayout_LabelColumnSizesToContent — the label column was a flat
// %-22s, six columns wider than the longest label it ever holds.
func TestCategoryLayout_LabelColumnSizesToContent(t *testing.T) {
	short := []categoryOption{{label: "Backup"}, {label: "SEO"}}
	if got := (Model{width: 120, categories: short}).categoryLayout().labelW; got != minLabelWidth {
		t.Errorf("labelW with short labels = %d, want the %d floor", got, minLabelWidth)
	}

	long := []categoryOption{{label: strings.Repeat("x", 40)}}
	if got := (Model{width: 120, categories: long}).categoryLayout().labelW; got != maxLabelWidth {
		t.Errorf("labelW with a 40-char label = %d, want the %d ceiling", got, maxLabelWidth)
	}
}

// TestViewPrompt_Breadcrumb — this screen is where you decide what to type,
// and before Phase G4 it was the only screen that never named the command
// you were about to run. The category comes from the entry itself, not from
// m.browseCategory, which is empty whenever the command was reached through
// "All categories" or a typed filter.
func TestViewPrompt_Breadcrumb(t *testing.T) {
	m := Model{
		stage:  stageFreeText,
		width:  120,
		height: 40,
		detail: viewport.New(120, minPaneHeight),
		selected: catalog.Entry{Key: "trellis/backup/database-pull", ShortName: "database-pull",
			DisplayCategory: "backup", Platform: "trellis", Description: "Pull a database"},
		browseCategory: "",
	}
	m.input = freshInput("site")

	out := stripANSI(m.viewPrompt())
	if !strings.Contains(out, "wp-ops > Backup > database-pull") {
		t.Errorf("viewPrompt() is missing the breadcrumb:\n%s", out)
	}
}

// TestNameColumnWidth_SizesToVisibleRows keeps a narrow category from
// inheriting the widest category's gutter, while clamping so one long
// outlier can't push every description off the right edge.
func TestNameColumnWidth_SizesToVisibleRows(t *testing.T) {
	short := []catalog.Entry{{Key: "scripts/sync/rsync-theme"}}
	if got := browseModel(100, short).nameColumnWidth(0, 1); got != minNameWidth {
		t.Errorf("nameColumnWidth() with a short name = %d, want the %d floor", got, minNameWidth)
	}

	long := []catalog.Entry{{Key: "scripts/misc/" + strings.Repeat("x", 60)}}
	if got := browseModel(100, long).nameColumnWidth(0, 1); got != maxNameWidth {
		t.Errorf("nameColumnWidth() with a 60-char name = %d, want the %d ceiling", got, maxNameWidth)
	}
}

// TestWrapBlock_HangingIndent — an option whose description runs long must
// stay visibly attached to its "--flag" instead of resuming in column 0,
// where the next option's name belongs.
func TestWrapBlock_HangingIndent(t *testing.T) {
	in := "Options:\n  --mode             optional  " + strings.Repeat("word ", 30)
	lines := strings.Split(wrapBlock(in, 60), "\n")

	if len(lines) < 3 {
		t.Fatalf("wrapBlock() did not wrap: %q", lines)
	}
	for i, line := range lines[2:] {
		if !strings.HasPrefix(line, "    ") {
			t.Errorf("continuation line %d lacks the hanging indent: %q", i+2, line)
		}
	}
}

// TestWrapBlock_NoTruncation is the point of wrapping at all: the viewport
// clips instead, and losing the end of the sentence explaining what an
// option does is the failure the detail block exists to fix.
func TestWrapBlock_NoTruncation(t *testing.T) {
	in := "  --output           optional  Append broken-link results to this file"
	out := wrapBlock(in, 40)
	if strings.Contains(out, "…") {
		t.Errorf("wrapBlock() truncated instead of wrapping: %q", out)
	}
	if !strings.Contains(strings.Join(strings.Fields(out), " "), "results to this file") {
		t.Errorf("wrapBlock() lost the end of the line: %q", out)
	}
}

// TestDetailHeight_ShrinksToContent — a viewport shorter than its fixed
// Height still renders the remaining rows as blanks, so a command declaring
// no arguments used to push the prompt nine empty lines down the screen.
func TestDetailHeight_ShrinksToContent(t *testing.T) {
	short := "one\ntwo\nthree"
	if got := detailHeight(short, maxInlineRows); got != 3 {
		t.Errorf("detailHeight(3-line body) = %d, want 3", got)
	}

	long := strings.Repeat("line\n", 40)
	if got := detailHeight(long, maxInlineRows); got != maxInlineRows-promptChromeRows {
		t.Errorf("detailHeight(40-line body) = %d, want the %d budget", got, maxInlineRows-promptChromeRows)
	}
}

// TestTruncate_RuneAware — descriptions now fill the width the preview pane
// used to occupy, so they get truncated far more often than the old
// 28-column name field ever was, and several contain an em dash that a
// byte-indexed cut would split into a partial rune.
func TestTruncate_RuneAware(t *testing.T) {
	got := truncate("backups — Ansible and shell", 12)
	if !strings.HasSuffix(got, "…") {
		t.Errorf("truncate() = %q, want an ellipsis", got)
	}
	if n := len([]rune(got)); n != 12 {
		t.Errorf("truncate() returned %d runes, want 12: %q", n, got)
	}
	if strings.ContainsRune(got, '�') {
		t.Errorf("truncate() split a multi-byte rune: %q", got)
	}
}

// stripANSI removes lipgloss's color escapes so row widths can be measured
// in the cells a terminal actually paints.
func stripANSI(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		if s[i] == 0x1b {
			for i < len(s) && s[i] != 'm' {
				i++
			}
			i++
			continue
		}
		b.WriteByte(s[i])
		i++
	}
	return b.String()
}
