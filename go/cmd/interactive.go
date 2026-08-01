package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/ui"
)

// runInteractive launches the Bubble Tea picker and, on each selection,
// runs the chosen command and asks whether to pick another — port of
// interactive_menu()'s outer loop (wp-ops:2001-2013), collapsed onto a
// single picker implementation per M4 task 3 / open decision #3 (no
// separate fzf-present vs. fzf-absent path).
//
// The picker itself only ever returns after releasing the terminal (Bubble
// Tea's Program.Run has already torn down the alt screen by the time
// RunPicker returns), so executeEntry below runs with a normal terminal,
// same as fzf_menu exiting before execute_command (wp-ops:1993-1997).
func runInteractive(c *catalog.Catalog) int {
	for {
		result, err := ui.RunPicker(c)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		if result.Quit {
			return 0
		}

		e, ok := c.Lookup(result.Key)
		if !ok {
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", result.Key)
			return 1
		}

		fmt.Println()
		executeEntry(e, result.Args)

		fmt.Println()
		if !promptAgain() {
			return 0
		}
		fmt.Println()
	}
}

// promptAgain ports interactive_menu()'s "Pick another command? [Y/n]"
// (wp-ops:2009) — defaults to yes on a blank reply.
func promptAgain() bool {
	fmt.Print("Pick another command? [Y/n] ")
	reply, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	reply = strings.TrimSpace(reply)
	return reply == "" || reply[0] == 'y' || reply[0] == 'Y'
}
