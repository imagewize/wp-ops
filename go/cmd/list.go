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

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List every command by category",
	RunE: func(cc *cobra.Command, args []string) error {
		c := mustCatalog()
		if jsonFlag {
			printJSON(c)
			return nil
		}
		printCategorizedList(c)
		return nil
	},
}

func init() {
	listCmd.Flags().BoolVar(&jsonFlag, "json", false, "Output as JSON")
	rootCmd.AddCommand(listCmd)
}

func printCategorizedList(c *catalog.Catalog) {
	fmt.Println("wp-ops — WordPress Operations Tools")
	fmt.Println()

	for _, category := range c.Categories() {
		fmt.Printf("%s (%s):\n\n", catalog.CategoryDisplayNames[category], category)
		printCategoryEntries(c.CommandsIn(category))
		fmt.Println()
	}

	fmt.Println("Run 'wp-ops search <term>' to find a command")
	fmt.Println("Run 'wp-ops doctor' to check dependencies and environment")
	fmt.Println("Run 'wp-ops --json' for machine-readable command list")
}

func printCategoryCommands(c *catalog.Catalog, category string) {
	entries := c.CommandsIn(category)
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
// own printf uses $cmd_key for both fields.
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
