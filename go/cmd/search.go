package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var platformSearchFlag string

var searchCmd = &cobra.Command{
	Use:   "search <term>",
	Short: "Search commands by name or description",
	Args:  cobra.ArbitraryArgs,
	RunE: func(cc *cobra.Command, args []string) error {
		if len(args) == 0 {
			fmt.Fprintf(os.Stderr, "Usage: %s search <term>\n", cmdName())
			os.Exit(1)
		}
		runSearch(args[0])
		return nil
	},
}

func init() {
	searchCmd.Flags().StringVar(&platformSearchFlag, "platform", "", platformFlagUsage)
	rootCmd.AddCommand(searchCmd)
}

// runSearch ports print_search_results (wp-ops:1566), including the "the
// docs mention it" cross-reference into docs.go's full-text doc search
// (wp-ops:1582-1586).
func runSearch(term string) {
	c := mustCatalog()
	if err := validatePlatform(platformSearchFlag); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	matches := c.FilterByPlatform(platformSearchFlag).Search(term)

	if len(matches) == 0 {
		fmt.Printf("No commands match '%s'.\n\n", term)
		if hasDocMatches(term) {
			fmt.Printf("The documentation mentions it though — try %s docs %s.\n\n", cmdName(), term)
		}
		fmt.Printf("Run %s to browse everything by category.\n", cmdName())
		os.Exit(1)
	}

	noun := "matches"
	if len(matches) == 1 {
		noun = "match"
	}
	fmt.Printf("%d %s for '%s':\n\n", len(matches), noun, term)
	for _, m := range matches {
		tag := ""
		if m.RunsOn == "server" {
			tag = "(server) "
		}
		// Always badged, not just under --platform: search is the surface
		// where you're comparing unfamiliar commands, so "will this run
		// against my site" is exactly the question the badge answers. Under
		// --platform every row carries the same value and it's redundant.
		if m.Platform != "" && platformSearchFlag == "" {
			tag += "[" + m.Platform + "] "
		}
		fmt.Printf("  %-40s %s%s\n", m.Key, tag, m.Description)
	}
	fmt.Println()
}
