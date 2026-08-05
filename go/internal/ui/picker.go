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
//
// Deliberately *not* tea.WithAltScreen: the picker renders inline, in the
// terminal's primary buffer, the way `fzf --height` does. The alternate
// screen buffer keeps no scrollback of its own and discards everything
// drawn in it on exit, which is what made a bare `wp-ops` read as "a
// separate prompt" rather than a command that printed something — see
// docs/trellis-cli-comparison.md §1, where `trellis`'s staying-in-the-
// buffer behavior is the whole difference being closed. Inline rendering
// is why Model caps its own height at maxInlineRows instead of filling
// the window (model.go's viewportHeight).
func RunPicker(c *catalog.Catalog) (Result, error) {
	m := New(c)
	p := tea.NewProgram(m)
	final, err := p.Run()
	if err != nil {
		return Result{}, err
	}
	return final.(Model).result, nil
}
