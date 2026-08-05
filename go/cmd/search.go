package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

var platformSearchFlag string

var searchCmd = &cobra.Command{
	Use:   "search <term>",
	Short: "Search commands by name or description",
	Args:  cobra.ArbitraryArgs,
	RunE: func(cc *cobra.Command, args []string) error {
		if len(args) == 0 {
			fmt.Fprintln(os.Stderr, "Usage: wp-ops search <term>")
			os.Exit(1)
		}
		runSearch(args[0])
		return nil
	},
}

func init() {
	searchCmd.Flags().StringVar(&platformSearchFlag, "platform", "", "Filter by platform: trellis, wordpress, any")
	rootCmd.AddCommand(searchCmd)
}

// runSearch ports print_search_results (wp-ops:1566), including the "the
// docs mention it" cross-reference into docs.go's full-text doc search
// (wp-ops:1582-1586).
func runSearch(term string) {
	c := mustCatalog()
	var matches []catalog.Entry
	
	if platformSearchFlag != "" {
		// Filter by platform first, then search
		filtered := c.FilterByPlatform(platformSearchFlag)
		matches = filtered.Search(term)
	} else {
		matches = c.Search(term)
	}

	if len(matches) == 0 {
		fmt.Printf("No commands match '%s'.\n\n", term)
		if hasDocMatches(term) {
			fmt.Printf("The documentation mentions it though — try wp-ops docs %s.\n\n", term)
		}
		fmt.Println("Run wp-ops to browse everything by category.")
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
		// Add platform tag if filtering by platform
		if m.Platform != "" && platformSearchFlag != "" {
			tag += "[" + m.Platform + "] "
		}
		fmt.Printf("  %-40s %s%s\n", m.Key, tag, m.Description)
	}
	fmt.Println()
}
