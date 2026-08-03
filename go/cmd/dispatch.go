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

	for _, category := range c.DisplayCategories() {
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
			ValidArgsFunction: categoryBasenameCompletions(cat),
		}
		rootCmd.AddCommand(catCmd)
	}
}

// categoryBasenameCompletions backs `wp-ops <category> <TAB>` completion:
// bash's actual completion grammar (print_completion, wp-ops:2098) is
// exactly two tokens — category, then a basename within it — and stops
// there (cword >= 3 gets no completions, since anything past the basename
// belongs to the underlying script's own argv). ValidArgsFunction is called
// once per positional slot regardless of DisableFlagParsing, so this only
// needs to guard on "am I completing the first arg after the category".
func categoryBasenameCompletions(cat string) func(cc *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	return func(cc *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
		if len(args) != 0 {
			return nil, cobra.ShellCompDirectiveNoFileComp
		}
		entries := mustCatalog().CommandsInDisplay(cat)
		seen := make(map[string]bool, len(entries))
		basenames := make([]string, 0, len(entries))
		for _, e := range entries {
			b := filepath.Base(e.Key)
			if seen[b] {
				continue
			}
			seen[b] = true
			basenames = append(basenames, b)
		}
		return basenames, cobra.ShellCompDirectiveNoFileComp
	}
}

// rootBasenameCompletions backs `wp-ops <TAB>` for basenames like
// "db-backup": the per-entry full-key commands registered above are
// Hidden, and Cobra's default subcommand-name completion skips hidden
// commands, so without this only categories/list/search/etc. would
// complete — even though a bare basename (rootRunE's FindByBasename
// fallback) is a valid invocation. Cobra calls ValidArgsFunction in
// addition to its subcommand-name matching (not instead of), so this
// supplements rather than replaces the category/subcommand completions.
func rootBasenameCompletions(cc *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
	if len(args) != 0 {
		return nil, cobra.ShellCompDirectiveNoFileComp
	}
	entries := mustCatalog().Entries
	seen := make(map[string]bool, len(entries))
	basenames := make([]string, 0, len(entries))
	for _, e := range entries {
		b := filepath.Base(e.Key)
		if seen[b] {
			continue
		}
		seen[b] = true
		basenames = append(basenames, b)
	}
	return basenames, cobra.ShellCompDirectiveNoFileComp
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
		if m.DisplayCategory == category {
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

	// Checked before the .php branch below: wordpress-utilities/* snippets
	// are reference files, several of them .php, so the category prefix
	// must win over the extension or they'd be run through WP-CLI instead
	// of printed/copied.
	if strings.HasPrefix(e.Key, "wordpress-utilities/") {
		return executeSnippet(e, args, isHelp)
	}

	if ext == ".php" {
		return executeWPCLI(e, args, isHelp)
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

	playbookArgs, err := wpexec.BuildPlaybookArgs(e, args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
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

	code, err := wpexec.RunPlaybook(trellisDir, filepath.Join(root, e.ScriptPath), playbookArgs)
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

func executeSnippet(e catalog.Entry, args []string, isHelp bool) int {
	if isHelp {
		fmt.Print(wpexec.FormatSnippetHelp(e))
		return 0
	}

	root, err := repoRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	scriptPath := filepath.Join(root, e.ScriptPath)
	tty := detect.IsTerminal(os.Stdout)

	return wpexec.RunSnippet(os.Stdout, os.Stderr, e, scriptPath, args, tty)
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
