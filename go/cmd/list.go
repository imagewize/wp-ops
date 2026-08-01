package cmd

import (
	"bytes"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

var allFlag bool

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List every command by category",
	RunE: func(cc *cobra.Command, args []string) error {
		c := mustCatalog()
		switch {
		case jsonFlag:
			printJSON(c)
		case allFlag:
			printAllCommands(c)
		default:
			printCategorizedList(c)
		}
		return nil
	},
}

func init() {
	listCmd.Flags().BoolVar(&jsonFlag, "json", false, "Output as JSON")
	listCmd.Flags().BoolVar(&allFlag, "all", false, "List every command in every category, with descriptions")
	rootCmd.AddCommand(listCmd)
}

// printCategorizedList renders the compact, category-only default view —
// what bare `wp-ops` and `wp-ops list` show. Full per-command output moved
// to printAllCommands (`--all`); a single category's commands are already
// available via `wp-ops <category>` (dispatch.go's per-category Cobra
// commands), so this view doesn't need to duplicate that.
func printCategorizedList(c *catalog.Catalog) {
	fmt.Println("wp-ops — WordPress Operations Tools")
	fmt.Println()

	for _, category := range c.DisplayCategories() {
		entries := c.CommandsInDisplay(category)
		fmt.Printf("  %-22s (%2d)  %s\n", catalog.CategoryDisplayNames[category], len(entries), catalog.CategoryBlurbs[category])
	}

	fmt.Println()
	fmt.Println("Run 'wp-ops <category>' to see a category's commands (e.g. 'wp-ops trellis')")
	fmt.Println("Run 'wp-ops list --all' to see every command with its description")
	fmt.Println("Run 'wp-ops search <term>' to find a command")
	fmt.Println("Run 'wp-ops doctor' to check dependencies and environment")
	fmt.Println("Run 'wp-ops --json' for machine-readable command list")
}

// printAllCommands is the original full listing: every command in every
// category, one line each with its description. Kept behind `list --all`
// since it's still the only single-command way to see the whole catalog at
// once (e.g. for grepping).
func printAllCommands(c *catalog.Catalog) {
	fmt.Println("wp-ops — WordPress Operations Tools (full list)")
	fmt.Println()

	for _, category := range c.DisplayCategories() {
		fmt.Printf("%s (%s):\n\n", catalog.CategoryDisplayNames[category], category)
		printCategoryEntries(c.CommandsInDisplay(category))
		fmt.Println()
	}

	fmt.Println("Run 'wp-ops list' for a compact category summary")
	fmt.Println("Run 'wp-ops search <term>' to find a command")
	fmt.Println("Run 'wp-ops doctor' to check dependencies and environment")
	fmt.Println("Run 'wp-ops --json' for machine-readable command list")
}

func printCategoryCommands(c *catalog.Catalog, category string) {
	entries := c.CommandsInDisplay(category)
	if len(entries) == 0 {
		fmt.Printf("No commands found in category: %s\n", catalog.CategoryDisplayNames[category])
		return
	}
	fmt.Printf("%s Commands:\n\n", catalog.CategoryDisplayNames[category])
	printCategoryEntries(entries)
	fmt.Println()
}

func printCategoryEntries(entries []catalog.Entry) {
	for _, e := range entries {
		tag := ""
		if e.RunsOn == "server" {
			tag = "(server) "
		}
		fmt.Printf("  %-32s %s%s\n", filepath.Base(e.Key), tag, e.Description)
	}
}

// printJSON renders the catalog as JSON, matching bash's print_json
// (wp-ops:853) field-for-field: category is the top-level directory (not
// the @category manifest directive), and path duplicates command — bash's
// own printf uses $cmd_key for both fields. Deliberately uses Categories()/
// CommandsIn() (the directory grouping), not DisplayCategories()/
// CommandsInDisplay() — this is the one surface that must stay byte-for-byte
// identical to bash's output (see go/scripts/parity-check.sh), so the
// scripts/** DisplayCategory split (monitoring/images/patterns/release)
// must never leak into it.
func printJSON(c *catalog.Catalog) {
	type jsonEntry struct {
		Category    string `json:"category"`
		Command     string `json:"command"`
		Description string `json:"description"`
		Path        string `json:"path"`
		RunsOn      string `json:"runs_on"`
		Requires    string `json:"requires"`
		Doc         string `json:"doc"`
	}

	var lines []string
	for _, category := range c.Categories() {
		for _, e := range c.CommandsIn(category) {
			obj := jsonEntry{
				Category:    category,
				Command:     e.Key,
				Description: e.Description,
				Path:        e.Key,
				RunsOn:      e.RunsOn,
				Requires:    e.RequiresString(),
				Doc:         e.Doc,
			}

			var buf bytes.Buffer
			enc := json.NewEncoder(&buf)
			enc.SetEscapeHTML(false)
			_ = enc.Encode(obj)
			lines = append(lines, "  "+strings.TrimRight(buf.String(), "\n"))
		}
	}

	fmt.Println("[")
	fmt.Println(strings.Join(lines, ",\n"))
	fmt.Println("]")
}
