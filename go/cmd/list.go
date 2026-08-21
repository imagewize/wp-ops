package cmd

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

var allFlag bool
var platformFlag string

// platformFlagUsage is shared by `list` and `search` so the two can't drift
// from each other or from catalog.Platforms.
var platformFlagUsage = "Filter by platform: " + strings.Join(catalog.Platforms, ", ")

// validatePlatform rejects an unknown --platform value up front. Without it
// a typo silently filters the catalog down to nothing, which reads as "no
// such commands exist" rather than "no such platform".
func validatePlatform(platform string) error {
	if platform == "" {
		return nil
	}
	for _, p := range catalog.Platforms {
		if platform == p {
			return nil
		}
	}
	return fmt.Errorf("%s: unknown platform %q — expected one of: %s", cmdName(),
		platform, strings.Join(catalog.Platforms, ", "))
}

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List every command by category",
	RunE: func(cc *cobra.Command, args []string) error {
		c := mustCatalog()
		if err := validatePlatform(platformFlag); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		platform := platformFlag
		if platform == "" {
			// Unset means "the default for how we were invoked": no
			// filter under wp-ops, @platform trellis under `trellis ops`.
			// An explicit --platform always wins over that default.
			platform = defaultPlatform()
		}
		filtered := c.FilterByPlatform(platform)
		switch {
		case jsonFlag:
			printJSON(filtered)
		case allFlag:
			printAllCommands(filtered)
		default:
			printCategorizedList(filtered)
		}
		return nil
	},
}

func init() {
	listCmd.Flags().BoolVar(&jsonFlag, "json", false, "Output as JSON")
	listCmd.Flags().BoolVar(&allFlag, "all", false, "List every command in every category, with descriptions")
	listCmd.Flags().StringVar(&platformFlag, "platform", "", platformFlagUsage)
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

	n := cmdName()
	fmt.Println()
	fmt.Printf("Run '%s <category>' to see a category's commands (e.g. '%s backup')\n", n, n)
	fmt.Printf("Run '%s list --all' to see every command with its description\n", n)
	if asTrellisPlugin() {
		// The scoped view hides ~two thirds of the catalog, so say where
		// the rest is. Same binary, one word away — the cask installs
		// both names.
		fmt.Println("Showing @platform trellis commands only — run 'wp-ops' for the full catalog")
	} else {
		fmt.Printf("Run '%s list --platform wordpress' to see only what runs on any WP site\n", n)
	}
	fmt.Printf("Run '%s search <term>' to find a command\n", n)
	fmt.Printf("Run '%s doctor' to check dependencies and environment\n", n)
	fmt.Printf("Run '%s --json' for machine-readable command list\n", n)
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

	n := cmdName()
	fmt.Printf("Run '%s list' for a compact category summary\n", n)
	fmt.Printf("Run '%s search <term>' to find a command\n", n)
	fmt.Printf("Run '%s doctor' to check dependencies and environment\n", n)
	fmt.Printf("Run '%s --json' for machine-readable command list\n", n)
}

func printCategoryCommands(category string, entries []catalog.Entry) {
	if len(entries) == 0 {
		fmt.Printf("No commands found in category: %s\n", catalog.CategoryDisplayNames[category])
		return
	}

	// Scope the listing the same way the category summary is scoped, so
	// the counts agree. But a category with nothing tagged @platform
	// trellis (SEO, Images, Git...) still has commands that run fine here,
	// so fall back to the whole category rather than claiming it's empty.
	scoped := filterEntriesByPlatform(entries, defaultPlatform())
	unscoped := len(scoped) == 0
	if unscoped {
		scoped = entries
	}

	fmt.Printf("%s Commands:\n\n", catalog.CategoryDisplayNames[category])
	printCategoryEntries(scoped)
	if unscoped {
		fmt.Printf("\nNothing here is Trellis-specific — these run on any WordPress site.\n")
	}
	fmt.Println()
}

// filterEntriesByPlatform keeps the per-category listing consistent with
// the counts in the category summary. Execution is deliberately not
// filtered — naming a non-trellis command under `trellis ops` still runs
// it; only what we *advertise* is scoped.
func filterEntriesByPlatform(entries []catalog.Entry, platform string) []catalog.Entry {
	if platform == "" {
		return entries
	}
	var kept []catalog.Entry
	for _, e := range entries {
		if e.Platform == platform {
			kept = append(kept, e)
		}
	}
	return kept
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

// printJSON renders the catalog as JSON: category is the top-level
// directory (not the @category manifest directive), and path duplicates
// command. Deliberately uses Categories()/CommandsIn() (the directory
// grouping), not DisplayCategories()/CommandsInDisplay() — this output is
// a stable contract for external tooling, so the scripts/**
// DisplayCategory split (monitoring/images/patterns/release) must never
// leak into it.
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
