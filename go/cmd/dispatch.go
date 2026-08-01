package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/detect"
	wpexec "github.com/imagewize/wp-ops/go/internal/exec"
)

// registerCatalogCommands builds two layers of dynamic Cobra commands on
// top of the embedded catalog:
//
//   - one hidden command per entry, named by its full key
//     ("scripts/backup/db-backup") — the full-key form. Hidden so 66
//     entries don't drown out `wp-ops --help`; still directly invocable by
//     name.
//   - one visible command per active category ("scripts", "trellis", ...)
//     that resolves its first argument as a basename within (falling back
//     to across all of) that category — the short form, port of main()'s
//     category-prefixed branch (wp-ops:2238-2283).
//
// Both DisableFlagParsing, since the underlying scripts own their own flag
// grammars; wp-ops re-parses none of it (see internal/exec/shell.go).
func registerCatalogCommands(c *catalog.Catalog) {
	for _, e := range c.Entries {
		entry := e // capture
		leaf := &cobra.Command{
			Use:                entry.Key,
			Short:              entry.Description,
			DisableFlagParsing: true,
			Hidden:             true,
			Args:               cobra.ArbitraryArgs,
			RunE: func(cc *cobra.Command, args []string) error {
				os.Exit(executeEntry(entry, args))
				return nil
			},
		}
		rootCmd.AddCommand(leaf)
	}

	for _, category := range c.Categories() {
		cat := category // capture
		catCmd := &cobra.Command{
			Use:                cat,
			Short:              fmt.Sprintf("%s commands", catalog.CategoryDisplayNames[cat]),
			DisableFlagParsing: true,
			Args:               cobra.ArbitraryArgs,
			RunE: func(cc *cobra.Command, args []string) error {
				runCategory(mustCatalog(), cat, args)
				return nil
			},
		}
		rootCmd.AddCommand(catCmd)
	}
}

// runCategory resolves a bare command name within a category, port of
// main()'s "wp-ops <category> <command>" branch (wp-ops:2246-2283):
// preferring a basename match inside the category, falling back to the
// whole catalog when the category has no match at all.
func runCategory(c *catalog.Catalog, category string, args []string) {
	if len(args) == 0 || args[0] == "--help" || args[0] == "-h" {
		printCategoryCommands(c, category)
		fmt.Printf("Usage: wp-ops %s <command> [args...]\n", category)
		return
	}

	candidate, rest := args[0], args[1:]

	// A full key works here too, e.g. "wp-ops scripts scripts/backup/db-backup"
	// — bash checks the exact full command_key first regardless of the
	// stripped category prefix (wp-ops:2256-2260).
	if e, ok := c.Lookup(candidate); ok {
		os.Exit(executeEntry(e, rest))
		return
	}

	matches := c.FindByBasename(candidate)
	var inCategory []catalog.Entry
	for _, m := range matches {
		if m.Category == category {
			inCategory = append(inCategory, m)
		}
	}
	if len(inCategory) == 0 {
		inCategory = matches
	}

	switch len(inCategory) {
	case 0:
		printUnknownCommand(c, candidate)
		os.Exit(1)
	case 1:
		os.Exit(executeEntry(inCategory[0], rest))
	default:
		printAmbiguous(candidate, inCategory)
		os.Exit(1)
	}
}

// executeEntry runs one catalog entry, handling --where/--help, the
// server-side guard, and dispatch to the right executor. Port of
// execute_command() (wp-ops:1383).
func executeEntry(e catalog.Entry, args []string) int {
	// Checked before dispatch, same as bash (wp-ops:1400) — the file you'd
	// read, edit, or copy into a project is often what you actually want,
	// for every executor type.
	if len(args) > 0 && args[0] == "--where" {
		root, err := repoRoot()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println(filepath.Join(root, e.ScriptPath))
		return 0
	}

	isHelp := len(args) > 0 && (args[0] == "--help" || args[0] == "-h")
	ext := filepath.Ext(e.ScriptPath)

	if ext == ".yml" {
		return executeAnsible(e, args, isHelp)
	}

	if ext == ".php" {
		return executeWPCLI(e, args, isHelp)
	}

	// wordpress-utilities/* snippets don't have a Go executor yet —
	// internal/exec/snippet.go is M4 task 2 (docs/m4-go-cli-completion.md).
	// Still in the catalog (list/search/doctor/--json need it for parity),
	// just not runnable through this binary yet.
	if strings.HasPrefix(e.Key, "wordpress-utilities/") {
		if isHelp {
			fmt.Print(wpexec.FormatGenericHelp(e))
			return 0
		}
		fmt.Fprintf(os.Stderr, "%s isn't runnable through the Go CLI yet — its executor lands in M4.\n", e.Key)
		fmt.Fprintf(os.Stderr, "Run it via the bash CLI instead: wp-ops %s %s\n", e.Key, strings.Join(args, " "))
		return 1
	}

	if isHelp {
		fmt.Print(wpexec.FormatGenericHelp(e))
		return 0
	}

	// Bash runs this guard before the .yml/.php branches above rather than
	// here; the placement is equivalent in practice because every
	// server-side command is a .sh (all 8 of them), so none of them can
	// reach those branches. See serverside.go.
	if proceed, code := serverSideGuard(os.Stderr, e, args); !proceed {
		return code
	}

	root, err := repoRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	code, err := wpexec.Run(filepath.Join(root, e.ScriptPath), args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printCompletionBanner(e.Key, code)
	return code
}

func executeAnsible(e catalog.Entry, args []string, isHelp bool) int {
	if isHelp {
		fmt.Print(wpexec.FormatHelp(e, os.Getenv("TRELLIS_DIR")))
		return 0
	}

	if !wpexec.AnsiblePlaybookAvailable() {
		fmt.Fprintln(os.Stderr, "ansible-playbook not found on PATH. Install Ansible first.")
		return 1
	}

	trellisDir, ok := resolveTrellisDir()
	if !ok {
		return 1
	}

	root, err := repoRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	code, err := wpexec.RunPlaybook(trellisDir, filepath.Join(root, e.ScriptPath), args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printCompletionBanner(e.Key, code)
	return code
}

func executeWPCLI(e catalog.Entry, args []string, isHelp bool) int {
	root, err := repoRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	scriptPath := filepath.Join(root, e.ScriptPath)
	wpCommand := wpexec.RegisteredWPCommand(scriptPath)

	if isHelp {
		fmt.Print(wpexec.FormatWPCLIHelp(e, os.Getenv("WP_SITE_DIR"), wpCommand))
		return 0
	}

	if !wpexec.WPAvailable() {
		fmt.Fprintln(os.Stderr, "wp (WP-CLI) not found on PATH. Install WP-CLI first.")
		return 1
	}

	wpSiteDir, ok := resolveWPSiteDir()
	if !ok {
		return 1
	}

	code, err := wpexec.RunWPCLI(wpSiteDir, scriptPath, wpCommand, args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printCompletionBanner(e.Key, code)
	return code
}

func printCompletionBanner(key string, code int) {
	if !detect.IsTerminal(os.Stdout) {
		return
	}
	fmt.Println()
	if code == 0 {
		fmt.Printf("✓ %s completed\n", key)
	} else {
		fmt.Printf("✗ %s exited with code %d\n", key, code)
	}
}

// printUnknownCommand ports main()'s final fallback (wp-ops:2297-2309).
func printUnknownCommand(c *catalog.Catalog, candidate string) {
	fmt.Fprintf(os.Stderr, "Unknown command or category: %s\n\n", candidate)
	if best, ok := suggestSimilar(c, candidate); ok {
		fmt.Fprintln(os.Stderr, "Did you mean:")
		fmt.Fprintf(os.Stderr, "  wp-ops %s\n\n", best)
	}
	fmt.Fprintf(os.Stderr, "Try wp-ops search %s, or wp-ops to browse everything.\n", candidate)
}

// printAmbiguous ports print_ambiguous (wp-ops:1517).
func printAmbiguous(name string, matches []catalog.Entry) {
	fmt.Fprintf(os.Stderr, "'%s' matches more than one command:\n\n", name)
	for _, m := range matches {
		fmt.Fprintf(os.Stderr, "  %-40s %s\n", m.Key, m.Description)
	}
	fmt.Fprintln(os.Stderr)
	fmt.Fprintf(os.Stderr, "Run it by its full name, e.g. wp-ops %s\n", matches[0].Key)
}

// suggestSimilar ports suggest_similar (wp-ops:1533): a substring match on
// the basename scores len(name)-len(input)+5 (rewarding a tighter length
// match), plus a +10 bonus when the basename is a *prefix* match rather
// than merely containing input somewhere in the middle.
func suggestSimilar(c *catalog.Catalog, input string) (string, bool) {
	bestMatch := ""
	bestScore := 0

	for _, e := range c.Entries {
		name := filepath.Base(e.Key)
		score := 0
		if strings.Contains(name, input) {
			score = len(name) - len(input) + 5
		}
		if strings.HasPrefix(name, input) {
			score += 10
		}
		if score > bestScore {
			bestScore = score
			bestMatch = e.Key
		}
	}

	if bestMatch != "" && bestScore > 0 {
		return bestMatch, true
	}
	return "", false
}
