package ui

import (
	"fmt"
	"path/filepath"
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
	stageBrowse stage = iota
	stageFields
	stageFreeText
	stageDone
)

// Result is what RunPicker returns: either a command to run with its
// assembled argv, or Quit if the user backed out without selecting
// anything (Esc/Ctrl+C from the browse list, port of fzf_menu returning
// non-zero on Esc, wp-ops:1982).
type Result struct {
	Key  string
	Args []string
	Quit bool
}

var (
	headerStyle   = lipgloss.NewStyle().Bold(true)
	dimStyle      = lipgloss.NewStyle().Faint(true)
	cursorStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212"))
	serverTag     = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	errorStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	noteStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	borderedPane  = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(0, 1)
	footerStyle   = dimStyle
	minListWidth  = 34
	minPaneHeight = 10
)

// Model is the Bubble Tea model backing the interactive picker. It replaces
// both fzf_menu() and interactive_command_menu() (open decision #3 in
// docs/m4-go-cli-completion.md): a single filterable, scrollable list with
// a live preview pane, followed by guided per-field prompting on selection.
type Model struct {
	all      []catalog.Entry
	filtered []catalog.Entry
	cursor   int
	listTop  int // first visible row, for scrolling a long filtered list

	filterQuery []rune

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

// New builds the initial model from a catalog, sorted the same way
// catalog.Search would return an unfiltered search (by key) — see
// filterEntries.
func New(c *catalog.Catalog) Model {
	m := Model{
		all:     c.Entries,
		preview: viewport.New(40, minPaneHeight),
		input:   textinput.New(),
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
	return c.Search(query)
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

func (m Model) updateBrowse(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.Type {
	case tea.KeyCtrlC, tea.KeyEsc:
		m.result = Result{Quit: true}
		m.stage = stageDone
		return m, tea.Quit

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
	m.filtered = filterEntries(m.all, string(m.filterQuery))
	m.cursor = 0
	m.listTop = 0
	m.syncPreview()
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
	if m.stage == stageDone {
		return ""
	}
	if m.stage == stageFields || m.stage == stageFreeText {
		return m.viewPrompt()
	}
	return m.viewBrowse()
}

func (m Model) viewBrowse() string {
	var list strings.Builder
	fmt.Fprintf(&list, "wp-ops > %s\n\n", string(m.filterQuery))

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
	for i := start; i < end; i++ {
		e := m.filtered[i]
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
	footer := footerStyle.Render("type to filter · ↑/↓ move · pgup/pgdn scroll preview · enter run · esc quit")

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
