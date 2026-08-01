package ui

import (
	tea "github.com/charmbracelet/bubbletea"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// RunPicker launches the interactive picker over c and blocks until the
// user either selects a command (with its guided-prompted argv) or backs
// out. Port of interactive_menu() (wp-ops:2001) minus the "pick another
// command?" outer loop, which the caller (cmd/interactive.go) owns so it
// can run the selected command with the picker's terminal control released
// first — same reasoning as fzf_menu exiting before execute_command runs
// (wp-ops:1993-1997).
func RunPicker(c *catalog.Catalog) (Result, error) {
	m := New(c)
	p := tea.NewProgram(m, tea.WithAltScreen())
	final, err := p.Run()
	if err != nil {
		return Result{}, err
	}
	return final.(Model).result, nil
}
