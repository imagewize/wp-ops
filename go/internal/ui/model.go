package ui

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	wpexec "github.com/imagewize/wp-ops/go/internal/exec"
)

type stage int

const (
	stageCategory stage = iota
	stageBrowse
	stageFields
	stageFreeText
	stageDone
)

// Result is what RunPicker returns: either a command to run with its
// assembled argv, or Quit if the user backed out without selecting
// anything (Ctrl+C from any stage, or Esc from the outermost
// category-select stage — port of fzf_menu returning non-zero on Esc,
// wp-ops:1982).
type Result struct {
	Key  string
	Args []string
	Quit bool
}

// categoryOption is one row in the category-select stage (stageCategory).
// key is "" for the "All categories" pseudo-entry, which scopes browsing to
// nothing (i.e. the full catalog) — the one-Enter-keystroke equivalent of
// the picker's pre-Phase-F behavior, kept as the default cursor position so
// a user who wants to search across everything isn't worse off than before.
type categoryOption struct {
	key   string
	label string
	count int
	blurb string
}

// buildCategoryOptions lists "All categories" followed by every active
// category in catalog.Categories' curated order — the same set and order
// cmd's compact `list` view uses (Phase F, docs/cli-ux-plan.md, option 3).
func buildCategoryOptions(c *catalog.Catalog) []categoryOption {
	opts := []categoryOption{{
		label: "All categories",
		count: len(c.Entries),
		blurb: "Search or browse the whole catalog",
	}}
	for _, cat := range c.DisplayCategories() {
		opts = append(opts, categoryOption{
			key:   cat,
			label: catalog.CategoryDisplayNames[cat],
			count: len(c.CommandsInDisplay(cat)),
			blurb: catalog.CategoryBlurbs[cat],
		})
	}
	return opts
}

var (
	headerStyle         = lipgloss.NewStyle().Bold(true)
	dimStyle            = lipgloss.NewStyle().Faint(true)
	cursorStyle         = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	serverTag           = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	errorStyle          = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	noteStyle           = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	footerStyle         = dimStyle
	categoryHeaderStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("245"))
	minPaneHeight       = 10
	// Name-column bounds for the browse list. The column sizes to the longest
	// visible basename so short categories don't get a gutter of dead space,
	// clamped so a single 40-character outlier can't push every description
	// off the right edge.
	minNameWidth = 16
	maxNameWidth = 30
	// fallbackWidth stands in for the terminal width until the first
	// tea.WindowSizeMsg lands, so the opening frame isn't laid out for a
	// zero-width screen and then reflowed a moment later.
	fallbackWidth = 100
	// maxInlineRows caps how tall the picker draws. RunPicker renders inline
	// (no alt screen), so a picker sized to the full window would shove the
	// whole scrollback off-screen on launch and leave a window-height frame
	// behind on exit — the very thing dropping the alt screen was meant to
	// avoid. 20 rows keeps the list useful while leaving prior output
	// visible above it, same bargain `fzf --height 40%` makes.
	maxInlineRows = 20
)

// Model is the Bubble Tea model backing the interactive picker. It replaces
// both fzf_menu() and interactive_command_menu() (open decision #3 in
// docs/m4-go-cli-completion.md): a category-select stage (Phase F, option 3)
// leading into a filterable list, followed by a full-width help block and
// guided per-field prompting on selection.
type Model struct {
	all      []catalog.Entry
	filtered []catalog.Entry
	cursor   int
	listTop  int // first visible row, for scrolling a long filtered list

	filterQuery []rune

	categories []categoryOption
	catCursor  int
	// browseCategory is the category key stageBrowse is scoped to ("" means
	// unscoped — the "All categories" choice), set when the user selects a
	// row in stageCategory.
	browseCategory string

	detail viewport.Model

	stage    stage
	selected catalog.Entry

	fields    []field
	fieldIdx  int
	collected []string
	input     textinput.Model
	errMsg    string
	note      string

	width, height int
	result        Result
}

// New builds the initial model from a catalog. Entries are grouped by
// category (in catalog.Categories' curated order, same order list.go's
// summary view uses) and alphabetically by key within a category — see
// filterEntries. Phase F, docs/cli-ux-plan.md: grouping (rather than a flat
// alphabetical-by-key list) is what lets viewBrowse print a category header
// above each run of entries instead of an undifferentiated name wall.
func New(c *catalog.Catalog) Model {
	m := Model{
		all:        c.Entries,
		categories: buildCategoryOptions(c),
		stage:      stageCategory,
		detail:     viewport.New(fallbackWidth, minPaneHeight),
		input:      textinput.New(),
	}
	m.input.Prompt = "> "
	m.filtered = filterEntries(m.all, "")
	return m
}

func filterEntries(all []catalog.Entry, query string) []catalog.Entry {
	c := &catalog.Catalog{Entries: all}
	// Search only needs Entries populated — it doesn't touch the lookup
	// indexes built by Load(), so a bare literal here is fine and avoids
	// duplicating catalog's case-insensitive substring-match logic.
	entries := c.Search(query)
	sort.SliceStable(entries, func(i, j int) bool {
		ri, rj := categoryRank(entries[i].DisplayCategory), categoryRank(entries[j].DisplayCategory)
		if ri != rj {
			return ri < rj
		}
		return entries[i].Key < entries[j].Key
	})
	return entries
}

// categoryRank orders by position in catalog.DisplayOrder (the curated,
// most-used-first order), falling back to the end of the list for any
// category that isn't in it — defensive only, every real category is.
func categoryRank(category string) int {
	for i, cat := range catalog.DisplayOrder {
		if cat == category {
			return i
		}
	}
	return len(catalog.DisplayOrder)
}

func (m Model) Init() tea.Cmd {
	return textinput.Blink
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.resizeDetail()
		return m, nil

	case tea.KeyMsg:
		switch m.stage {
		case stageCategory:
			return m.updateCategory(msg)
		case stageBrowse:
			return m.updateBrowse(msg)
		case stageFields, stageFreeText:
			return m.updatePrompt(msg)
		}
	}
	return m, nil
}

// viewportHeight is the number of terminal rows the picker allows itself,
// as opposed to m.height (the rows the terminal has). The two differed not
// at all under the alt screen, which the picker owned outright; inline it
// gets a slice, so every height calculation reads this instead of m.height.
// A zero m.height means no tea.WindowSizeMsg has arrived yet — fall back to
// the cap rather than to zero, so the first frame isn't drawn at minimum
// size and then jumped to full size a moment later.
func (m Model) viewportHeight() int {
	if m.height <= 0 || m.height > maxInlineRows {
		return maxInlineRows
	}
	return m.height
}

// resizeDetail sizes the detail viewport shown on the prompt stages. It gets
// the full terminal width now that nothing renders beside it — the old
// two-pane split gave it m.width*3/5 minus borders, which is what truncated
// flag help mid-word.
func (m *Model) resizeDetail() {
	width := m.width
	if width <= 0 {
		width = fallbackWidth
	}
	m.detail.Width = width
	m.syncDetail()
}

// syncDetail loads the selected command's help block into the detail
// viewport. Unlike the live preview it replaces, this runs once per
// selection rather than on every cursor move: the block is only shown after
// Enter, so re-rendering it while the user is still scrolling the list would
// be work nobody sees.
func (m *Model) syncDetail() {
	if m.selected.Key == "" {
		return
	}
	body := wrapBlock(
		wpexec.DetailBody(m.selected, m.displayName(m.selected)), m.detail.Width)
	m.detail.SetContent(body)
	m.detail.Height = detailHeight(body, m.viewportHeight())
	m.detail.YOffset = 0
}

// detailHeight sizes the viewport to its content, up to the rows the inline
// picker can spend. A viewport shorter than its fixed Height still renders
// the remaining rows as blanks, so a command declaring no arguments used to
// push the prompt nine empty lines down the screen.
func detailHeight(body string, budget int) int {
	// 6 covers the blank line, prompt, and footer rendered beneath it.
	max := budget - 6
	if max < minPaneHeight {
		max = minPaneHeight
	}
	if lines := strings.Count(body, "\n") + 1; lines < max {
		return lines
	}
	return max
}

// wrapBlock soft-wraps a help block to width, hanging-indenting the
// continuation of any line that was itself indented — so an option whose
// description runs long stays visibly attached to its "--flag" rather than
// resuming in column 0 where the next option's name belongs.
//
// Wrapping at all is the point: the viewport clips instead, and losing the
// end of the sentence that explains what an option does is precisely the
// failure this screen was added to fix.
func wrapBlock(s string, width int) string {
	if width <= 0 {
		return s
	}
	var out []string
	for _, line := range strings.Split(s, "\n") {
		indent := ""
		if strings.HasPrefix(line, "  ") {
			indent = "    "
		}
		wrapped := lipgloss.NewStyle().Width(width - len(indent)).Render(line)
		for i, part := range strings.Split(wrapped, "\n") {
			part = strings.TrimRight(part, " ")
			if i > 0 {
				part = indent + strings.TrimLeft(part, " ")
			}
			out = append(out, part)
		}
	}
	return strings.Join(out, "\n")
}

// displayName is what to call a command in its usage line: the bare basename
// a user can type, unless two commands in different categories share it (say
// a scripts/ and a trellis/ "database-backup"), in which case only the full
// key is unambiguous — and printing a usage line that would hit dispatch.go's
// "ambiguous command" error would be worse than printing a longer one.
func (m Model) displayName(e catalog.Entry) string {
	base := filepath.Base(e.Key)
	seen := 0
	for _, other := range m.all {
		if filepath.Base(other.Key) == base {
			seen++
		}
	}
	if seen > 1 {
		return e.Key
	}
	return base
}

func (m *Model) cursorEntry() int {
	if m.cursor >= len(m.filtered) {
		return len(m.filtered) - 1
	}
	return m.cursor
}

// updateCategory handles input for stageCategory, the outermost stage: pick
// "All categories" or one specific category, then drill into stageBrowse
// scoped to that choice. Port of trellis-cli's two-level nav (Phase F,
// docs/cli-ux-plan.md, option 3) — mirrored here rather than replacing
// stageBrowse so the flat, cross-category filter/search from option 2 stays
// available as the default (cursor starts on "All categories").
func (m Model) updateCategory(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC, tea.KeyEsc:
		m.result = Result{Quit: true}
		m.stage = stageDone
		return m, tea.Quit

	case tea.KeyEnter:
		if len(m.categories) == 0 {
			return m, nil
		}
		m.browseCategory = m.categories[m.catCursor].key
		m.filterQuery = nil
		m.applyFilter()
		m.stage = stageBrowse
		return m, nil

	case tea.KeyUp, tea.KeyCtrlP:
		if m.catCursor > 0 {
			m.catCursor--
		}
		return m, nil

	case tea.KeyDown, tea.KeyCtrlN:
		if m.catCursor < len(m.categories)-1 {
			m.catCursor++
		}
		return m, nil

	case tea.KeyRunes, tea.KeySpace:
		// Typing anywhere on the category-select stage jumps straight into
		// stageBrowse unscoped ("All categories") with the typed text as the
		// initial filter — restores the pre-Phase-F-option-3 "just start
		// typing to search" muscle memory that adding this stage as the new
		// default screen otherwise took away (arrow+enter was still the only
		// way to make a keypress do anything here).
		runes := msg.Runes
		if msg.Type == tea.KeySpace {
			runes = []rune{' '}
		}
		m.browseCategory = ""
		m.filterQuery = runes
		m.applyFilter()
		m.stage = stageBrowse
		return m, nil
	}
	return m, nil
}

func (m Model) updateBrowse(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC:
		m.result = Result{Quit: true}
		m.stage = stageDone
		return m, tea.Quit

	case tea.KeyEsc:
		// Back out one level to category-select rather than quitting — Esc
		// is "go up a level" everywhere in this picker (also true of
		// stageFields/stageFreeText below); Ctrl+C is the only "quit
		// entirely" key once past stageCategory.
		m.stage = stageCategory
		m.filterQuery = nil
		return m, nil

	case tea.KeyEnter:
		if len(m.filtered) == 0 {
			return m, nil
		}
		m.selected = m.filtered[m.cursorEntry()]
		return m.beginPrompting(), nil

	case tea.KeyUp, tea.KeyCtrlP:
		if m.cursor > 0 {
			m.cursor--
		}
		return m, nil

	case tea.KeyDown, tea.KeyCtrlN:
		if m.cursor < len(m.filtered)-1 {
			m.cursor++
		}
		return m, nil

	case tea.KeyBackspace:
		if len(m.filterQuery) > 0 {
			m.filterQuery = m.filterQuery[:len(m.filterQuery)-1]
			m.applyFilter()
		}
		return m, nil

	case tea.KeyRunes, tea.KeySpace:
		runes := msg.Runes
		if msg.Type == tea.KeySpace {
			runes = []rune{' '}
		}
		m.filterQuery = append(m.filterQuery, runes...)
		m.applyFilter()
		return m, nil
	}
	return m, nil
}

func (m *Model) applyFilter() {
	pool := m.all
	if m.browseCategory != "" {
		pool = filterByCategory(m.all, m.browseCategory)
	}
	m.filtered = filterEntries(pool, string(m.filterQuery))
	m.cursor = 0
	m.listTop = 0
}

func filterByCategory(all []catalog.Entry, category string) []catalog.Entry {
	var out []catalog.Entry
	for _, e := range all {
		if e.DisplayCategory == category {
			out = append(out, e)
		}
	}
	return out
}

// beginPrompting transitions from the browse list into guided per-field
// prompting for m.selected, port of prompt_manifest_args' branch on
// whether the command declares any @arg/@flag lines (wp-ops:494-497).
func (m Model) beginPrompting() Model {
	m.fields = buildFields(m.selected)
	m.fieldIdx = 0
	m.collected = nil
	m.errMsg = ""
	m.note = ""
	// The help block is loaded here, at the moment of selection, rather than
	// tracked live while browsing — this is the only stage that shows it.
	m.syncDetail()

	if len(m.fields) == 0 {
		m.stage = stageFreeText
		m.input = freshInput("Arguments (leave blank for none, --help for usage)")
		return m
	}

	m.stage = stageFields
	m.input = freshInput(promptLabel(m.fields[0]))
	return m
}

func freshInput(label string) textinput.Model {
	ti := textinput.New()
	ti.Prompt = "  " + label + ": "
	ti.Focus()
	return ti
}

func (m Model) updatePrompt(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC:
		m.result = Result{Quit: true}
		m.stage = stageDone
		return m, tea.Quit

	case tea.KeyEsc:
		// Back out to the browse list without quitting, port of a user
		// backing out of fzf_menu's prompt loop — bash has no equivalent
		// escape hatch mid-prompt, but leaving the picker running instead
		// of exiting the whole program on a stray Esc is worth the
		// divergence.
		m.stage = stageBrowse
		return m, nil

	case tea.KeyEnter:
		return m.submitPrompt()

	// The help block above the prompt can outrun its viewport for a command
	// with many options, so keep the scroll keys the browse stage no longer
	// needs. textinput ignores PgUp/PgDn, so nothing is taken from typing.
	case tea.KeyPgUp:
		m.detail.HalfPageUp()
		return m, nil

	case tea.KeyPgDown:
		m.detail.HalfPageDown()
		return m, nil
	}

	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}

func (m Model) submitPrompt() (tea.Model, tea.Cmd) {
	value := m.input.Value()

	if m.stage == stageFreeText {
		m.result = Result{Key: m.selected.Key, Args: append(append([]string{}, m.collected...), strings.Fields(value)...)}
		m.stage = stageDone
		return m, tea.Quit
	}

	f := m.fields[m.fieldIdx]
	outcome := resolveField(f, value)

	if outcome.Reprompt {
		m.errMsg = outcome.Note
		m.input.Reset()
		return m, nil
	}

	m.errMsg = ""
	m.note = outcome.Note
	m.collected = append(m.collected, outcome.Args...)
	m.fieldIdx++

	if m.fieldIdx >= len(m.fields) {
		m.stage = stageFreeText
		m.input = freshInput("Additional arguments (leave blank for none)")
		return m, nil
	}

	m.input = freshInput(promptLabel(m.fields[m.fieldIdx]))
	return m, nil
}

func (m Model) View() string {
	switch m.stage {
	case stageDone:
		return ""
	case stageCategory:
		return m.viewCategory()
	case stageFields, stageFreeText:
		return m.viewPrompt()
	default:
		return m.viewBrowse()
	}
}

func (m Model) viewCategory() string {
	var b strings.Builder
	b.WriteString(headerStyle.Render("wp-ops — WordPress Operations Tools"))
	b.WriteString("\n\n")
	// Same opening line trellis prints above its command table. The picker
	// is not the only way in — every row here is also reachable as
	// `wp-ops <command>` — and without this the screen reads as if arrow
	// keys were the only interface to 74 commands.
	b.WriteString(dimStyle.Render("Usage: wp-ops [--help] [--version] <command> [<args>]"))
	b.WriteString("\n\n")

	for i, opt := range m.categories {
		line := fmt.Sprintf("%-22s (%2d)  %s", opt.label, opt.count, opt.blurb)
		if i == m.catCursor {
			b.WriteString(cursorStyle.Render("> " + line))
		} else {
			b.WriteString("  " + line)
		}
		b.WriteString("\n")
	}

	b.WriteString("\n" + m.footer("↑/↓ move · enter select · esc quit", "↑/↓ · enter · esc"))
	return b.String()
}

// viewBrowse renders the command list as a single full-width column — name,
// then description, the two-column shape trellis prints for its own commands.
//
// It used to be a bordered list pane beside a bordered live-preview pane.
// That layout could not survive its own width arithmetic: rows were built as
// a 28-column name plus "[platform]" plus "(server)" (~43 columns) and
// rendered into a pane of m.width*2/5, so on any terminal under ~118 columns
// lipgloss wrapped every tagged row and the tags landed in the left margin of
// the next line. The preview pane lost the same fight horizontally, clipping
// descriptions and flag help mid-word. Both problems were the two panes
// competing for one terminal's width, so the fix is to stop splitting it:
// the list gets the full width here, and everything the preview used to show
// moves to the post-selection detail block (viewPrompt), where it also gets
// the full width. See docs/trellis-cli-comparison.md §5.
func (m Model) viewBrowse() string {
	var b strings.Builder

	crumb := "All categories"
	if m.browseCategory != "" {
		crumb = catalog.CategoryDisplayNames[m.browseCategory]
	}
	fmt.Fprintf(&b, "%s > %s > %s\n\n",
		headerStyle.Render("wp-ops"), crumb, string(m.filterQuery))

	visible := m.viewportHeight() - 6
	if visible < 5 {
		visible = 5
	}
	start, end := m.scrollWindow(visible)

	if len(m.filtered) == 0 {
		b.WriteString(dimStyle.Render("No matches."))
		b.WriteString("\n")
	}

	nameW := m.nameColumnWidth(start, end)
	descW := m.width
	if descW <= 0 {
		descW = fallbackWidth
	}
	// 2 for the cursor gutter, 2 for the gap after the name column.
	descW -= nameW + 4

	// lastCat starts empty so the window's first visible row always gets a
	// header, even mid-scroll — reorients the user after paging rather than
	// assuming they remember which category they scrolled into. Skipped
	// entirely when stageBrowse is already scoped to one category (the
	// breadcrumb above already says which).
	lastCat := ""
	for i := start; i < end; i++ {
		e := m.filtered[i]
		if m.browseCategory == "" && e.DisplayCategory != lastCat {
			b.WriteString(categoryHeaderStyle.Render(catalog.CategoryDisplayNames[e.DisplayCategory]))
			b.WriteString("\n")
			lastCat = e.DisplayCategory
		}

		name := truncate(filepath.Base(e.Key), nameW)
		row := fmt.Sprintf("%-*s  %s", nameW, name, m.describeRow(e, descW))
		if i == m.cursorEntry() {
			b.WriteString(cursorStyle.Render("> " + row))
		} else {
			b.WriteString("  " + row)
		}
		b.WriteString("\n")
	}

	b.WriteString("\n")
	b.WriteString(m.footer(
		"type to filter · ↑/↓ move · enter select · esc back · ctrl+c quit",
		"↑/↓ · enter · esc back"))
	return b.String()
}

// footer renders the key hints, falling back to an abbreviated form when the
// full one would wrap. A wrapped footer is the same class of defect the row
// layout was rewritten to remove — hints spilling into the next line read as
// broken output, not as a dense terminal UI.
func (m Model) footer(full, short string) string {
	width := m.width
	if width <= 0 {
		width = fallbackWidth
	}
	hints := full
	if len([]rune(hints)) > width {
		hints = short
	}
	return footerStyle.Render(truncate(hints, width))
}

// describeRow renders a row's description column, right-aligning the
// "(server)" warning within it when the width allows. Platform ("[trellis]",
// "[wordpress]") deliberately no longer appears per row: it was the quietest
// signal on the screen and the one most responsible for overflowing the row,
// and DetailBody now states it in full a keystroke later, before anything
// runs. "(server)" stays because "this will not run against your local site"
// is worth knowing while still scanning the list.
func (m Model) describeRow(e catalog.Entry, width int) string {
	tag := ""
	if e.RunsOn == "server" {
		tag = " (server)"
	}
	descW := width - len(tag)
	if descW < 12 {
		// Too narrow to carry both; the description wins.
		descW, tag = width, ""
	}
	if descW < 1 {
		return ""
	}
	desc := fmt.Sprintf("%-*s", descW, truncate(e.Description, descW))
	if tag == "" {
		return strings.TrimRight(desc, " ")
	}
	return desc + serverTag.Render(tag)
}

// nameColumnWidth sizes the name column to the longest basename actually on
// screen, within [minNameWidth, maxNameWidth]. Measuring the visible window
// rather than the whole catalog keeps a narrow category (say Sync, whose
// longest name is 11 characters) from inheriting Monitoring's gutter.
func (m Model) nameColumnWidth(start, end int) int {
	w := minNameWidth
	for i := start; i < end && i < len(m.filtered); i++ {
		if n := len(filepath.Base(m.filtered[i].Key)); n > w {
			w = n
		}
	}
	if w > maxNameWidth {
		w = maxNameWidth
	}
	return w
}

// scrollWindow keeps the cursor within a `visible`-row window over the
// filtered list, matching a typical scrolling list-picker's behavior.
func (m Model) scrollWindow(visible int) (start, end int) {
	if len(m.filtered) <= visible {
		return 0, len(m.filtered)
	}
	cur := m.cursorEntry()
	start = cur - visible/2
	if start < 0 {
		start = 0
	}
	end = start + visible
	if end > len(m.filtered) {
		end = len(m.filtered)
		start = end - visible
	}
	return start, end
}

// truncate shortens s to at most n display cells, ellipsizing when it cuts.
// Counts runes rather than bytes: descriptions now fill the width the preview
// pane used to occupy, so they get truncated far more often than the old
// 28-column name field ever was, and a byte-indexed cut through the em dash
// several of them contain would emit a partial rune.
func truncate(s string, n int) string {
	if n <= 0 {
		return ""
	}
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

// viewPrompt renders the chosen command's full help block above the argument
// prompt: usage line, description, arguments, options, requirements — the
// shape `trellis <command> --help` prints, at full terminal width. Showing it
// here rather than in a preview pane during browsing is what lets the browse
// list be a plain list, and means the help is on screen at the moment it's
// actually needed: while typing the values it documents.
func (m Model) viewPrompt() string {
	var b strings.Builder

	b.WriteString(m.detail.View())
	b.WriteString("\n\n")

	// No per-field description line here any more: it repeated verbatim what
	// the Arguments/Options block two lines above already says, which was
	// tolerable when the prompt screen showed nothing but the command name.
	b.WriteString(m.input.View())
	b.WriteString("\n")

	if m.errMsg != "" {
		fmt.Fprintf(&b, "\n%s\n", errorStyle.Render(m.errMsg))
	}
	if m.note != "" {
		fmt.Fprintf(&b, "\n%s\n", noteStyle.Render(m.note))
	}

	full := "enter confirm · esc back to list · ctrl+c quit"
	if m.detail.TotalLineCount() > m.detail.Height {
		full = "pgup/pgdn scroll help · " + full
	}
	b.WriteString("\n" + m.footer(full, "enter · esc back"))
	return b.String()
}
