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

// TestViewBrowse_NoPlatformTag pins the deliberate removal: platform was the
// quietest signal on the screen and the one most responsible for overflowing
// the row. DetailBody states it a keystroke later, before anything runs.
func TestViewBrowse_NoPlatformTag(t *testing.T) {
	out := browseModel(140, longRowEntries()).viewBrowse()
	for _, tag := range []string{"[trellis]", "[any]", "[wordpress]"} {
		if strings.Contains(out, tag) {
			t.Errorf("viewBrowse() still renders the %s row tag:\n%s", tag, out)
		}
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
	if got := detailHeight(long, maxInlineRows); got != maxInlineRows-6 {
		t.Errorf("detailHeight(40-line body) = %d, want the %d budget", got, maxInlineRows-6)
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
