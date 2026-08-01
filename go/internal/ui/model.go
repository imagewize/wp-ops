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
	for _, cat := range c.Categories() {
		opts = append(opts, categoryOption{
			key:   cat,
			label: catalog.CategoryDisplayNames[cat],
			count: len(c.CommandsIn(cat)),
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
	borderedPane        = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(0, 1)
	footerStyle         = dimStyle
	categoryHeaderStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("245"))
	minListWidth        = 34
	minPaneHeight       = 10
)

// Model is the Bubble Tea model backing the interactive picker. It replaces
// both fzf_menu() and interactive_command_menu() (open decision #3 in
// docs/m4-go-cli-completion.md): a category-select stage (Phase F, option 3)
// leading into a filterable, scrollable list with a live preview pane,
// followed by guided per-field prompting on selection.
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

	preview viewport.Model

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
		preview:    viewport.New(40, minPaneHeight),
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
		ri, rj := categoryRank(entries[i].Category), categoryRank(entries[j].Category)
		if ri != rj {
			return ri < rj
		}
		return entries[i].Key < entries[j].Key
	})
	return entries
}

// categoryRank orders by position in catalog.Categories (the curated,
// most-used-first order), falling back to the end of the list for any
// category that isn't in it — defensive only, every real category is.
func categoryRank(category string) int {
	for i, cat := range catalog.Categories {
		if cat == category {
			return i
		}
	}
	return len(catalog.Categories)
}

func (m Model) Init() tea.Cmd {
	return textinput.Blink
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.resizePreview()
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

func (m *Model) resizePreview() {
	listWidth := minListWidth
	if m.width > 0 {
		listWidth = m.width * 2 / 5
		if listWidth < minListWidth {
			listWidth = minListWidth
		}
	}
	previewWidth := m.width - listWidth - 6
	if previewWidth < 20 {
		previewWidth = 20
	}
	previewHeight := m.height - 6
	if previewHeight < minPaneHeight {
		previewHeight = minPaneHeight
	}
	m.preview.Width = previewWidth
	m.preview.Height = previewHeight
	m.syncPreview()
}

func (m *Model) syncPreview() {
	if len(m.filtered) == 0 {
		m.preview.SetContent("No matches.")
		return
	}
	e := m.filtered[m.cursorEntry()]
	m.preview.SetContent(wpexec.PreviewBody(e))
	m.preview.YOffset = 0
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
		m.syncPreview()
		return m, nil

	case tea.KeyDown, tea.KeyCtrlN:
		if m.cursor < len(m.filtered)-1 {
			m.cursor++
		}
		m.syncPreview()
		return m, nil

	case tea.KeyPgUp:
		m.preview.HalfViewUp()
		return m, nil

	case tea.KeyPgDown:
		m.preview.HalfViewDown()
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
	m.syncPreview()
}

func filterByCategory(all []catalog.Entry, category string) []catalog.Entry {
	var out []catalog.Entry
	for _, e := range all {
		if e.Category == category {
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
	b.WriteString(headerStyle.Render("wp-ops — interactive picker"))
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

	b.WriteString("\n" + footerStyle.Render("↑/↓ move · enter select · esc quit"))
	return b.String()
}

func (m Model) viewBrowse() string {
	var list strings.Builder
	crumb := "All categories"
	if m.browseCategory != "" {
		crumb = catalog.CategoryDisplayNames[m.browseCategory]
	}
	fmt.Fprintf(&list, "wp-ops > %s > %s\n\n", crumb, string(m.filterQuery))

	listWidth := minListWidth
	if m.width > 0 {
		listWidth = m.width * 2 / 5
		if listWidth < minListWidth {
			listWidth = minListWidth
		}
	}

	visible := m.height - 8
	if visible < 5 {
		visible = 5
	}
	start, end := m.scrollWindow(visible)

	if len(m.filtered) == 0 {
		list.WriteString(dimStyle.Render("No matches."))
	}
	// lastCat starts empty so the window's first visible row always gets a
	// header, even mid-scroll — reorients the user after paging rather than
	// assuming they remember which category they scrolled into. Skipped
	// entirely when stageBrowse is already scoped to one category (the
	// breadcrumb above already says which).
	lastCat := ""
	for i := start; i < end; i++ {
		e := m.filtered[i]
		if m.browseCategory == "" && e.Category != lastCat {
			list.WriteString(categoryHeaderStyle.Render(catalog.CategoryDisplayNames[e.Category]))
			list.WriteString("\n")
			lastCat = e.Category
		}
		line := fmt.Sprintf("%-28s", truncate(filepath.Base(e.Key), 28))
		if e.RunsOn == "server" {
			line += " " + serverTag.Render("(server)")
		}
		if i == m.cursorEntry() {
			list.WriteString(cursorStyle.Render("> " + line))
		} else {
			list.WriteString("  " + line)
		}
		list.WriteString("\n")
	}

	listPane := borderedPane.Width(listWidth).Render(list.String())
	previewPane := borderedPane.Render(m.preview.View())

	body := lipgloss.JoinHorizontal(lipgloss.Top, listPane, previewPane)
	footer := footerStyle.Render("type to filter · ↑/↓ move · pgup/pgdn scroll preview · enter run · esc back · ctrl+c quit")

	return headerStyle.Render("wp-ops — interactive picker") + "\n" + body + "\n" + footer
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

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}

func (m Model) viewPrompt() string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s\n", headerStyle.Render(m.selected.Key))
	if m.selected.Description != "" {
		fmt.Fprintf(&b, "%s\n", dimStyle.Render(m.selected.Description))
	}
	b.WriteString("\n")

	if m.stage == stageFields {
		f := m.fields[m.fieldIdx]
		if f.param.Description != "" {
			fmt.Fprintf(&b, "  %s\n", dimStyle.Render(f.param.Description))
		}
	}

	b.WriteString(m.input.View())
	b.WriteString("\n")

	if m.errMsg != "" {
		fmt.Fprintf(&b, "\n%s\n", errorStyle.Render(m.errMsg))
	}
	if m.note != "" {
		fmt.Fprintf(&b, "\n%s\n", noteStyle.Render(m.note))
	}

	b.WriteString("\n" + footerStyle.Render("enter confirm · esc back to list · ctrl+c quit"))
	return b.String()
}
