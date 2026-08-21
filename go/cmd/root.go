// Package cmd wires the Cobra command tree for the wp-ops Go CLI: dynamic
// per-catalog-entry commands (full key + category-short forms), list,
// search, doctor, and --json/--version. See docs/m3-go-skeleton.md, task 7.
package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/detect"
)

// jsonFlag backs `list --json` (list.go registers its own, properly-parsed
// flag). Root itself can't use Cobra flag parsing at all — see DisableFlagParsing below.
var jsonFlag bool

var rootCmd = &cobra.Command{
	Use:   "wp-ops",
	Short: "Unified CLI wrapper for wp-ops tools",
	// Long is filled in by Execute() so every usage line spells the name
	// the user actually typed — see rootLong and cmdName().
	// Arbitrary args: a bare command name that isn't one of the explicitly
	// registered children (list/search/doctor/category commands/full-key
	// commands) falls through here and is resolved as a basename against
	// the whole catalog — port of main()'s fallback path (wp-ops:2246-2309).
	Args: cobra.ArbitraryArgs,
	RunE: rootRunE,
	// Root dispatches bare command names too (e.g. "wp-ops db-backup
	// --where"), whose remaining args are passed straight through to the
	// script unparsed — same reasoning as the dynamic per-entry commands in
	// dispatch.go. If Cobra parsed root's own flags first, an unrecognized
	// "--where"/"--url"/... anywhere in argv would hard-error before RunE
	// ever saw it. --json/--version/--help are checked manually below
	// instead, matching bash's `case "${1:-}" in ...` (wp-ops:2168), which
	// only ever inspects the first token too.
	DisableFlagParsing: true,
	// The dynamic per-entry/category commands manage their own exit codes
	// via os.Exit (to propagate the underlying script's real exit status),
	// so Cobra's own usage-on-error printing would be redundant/wrong here.
	SilenceUsage:      true,
	SilenceErrors:     true,
	ValidArgsFunction: rootBasenameCompletions,
}

func rootRunE(cc *cobra.Command, args []string) error {
	c := mustCatalog()
	// What we *show* is scoped to how we were invoked (see
	// defaultPlatform); what we *run*, below, never is. --json stays
	// unscoped too — it's a stable contract for external tooling.
	listing := c.FilterByPlatform(defaultPlatform())

	if len(args) == 0 {
		// Port of main()'s `[[ -t 0 && -t 1 ]]` branch (wp-ops:2154-2157):
		// launch the picker only on a real interactive terminal; a
		// piped/redirected invocation keeps printing list-equivalent output
		// so `wp-ops | less` etc. still work.
		if detect.IsTerminal(os.Stdin) && detect.IsTerminal(os.Stdout) {
			os.Exit(runInteractive(listing))
			return nil
		}
		printCategorizedList(listing)
		return nil
	}

	switch args[0] {
	case "--json":
		printJSON(c)
		return nil
	case "--version", "-v":
		printVersion()
		return nil
	case "--help", "-h":
		printCategorizedList(listing)
		return nil
	}

	candidate, rest := args[0], args[1:]

	if e, ok := c.Lookup(candidate); ok {
		os.Exit(executeEntry(e, rest))
		return nil
	}

	matches := c.FindByBasename(candidate)
	switch len(matches) {
	case 0:
		printUnknownCommand(c, candidate)
		os.Exit(1)
	case 1:
		os.Exit(executeEntry(matches[0], rest))
	default:
		printAmbiguous(candidate, matches)
		os.Exit(1)
	}
	return nil
}

// rootLong renders the root help against the invoked name, so a
// `trellis ops` user is told to run `trellis ops backup`, not
// `wp-ops backup`. Under bare wp-ops the output is byte-for-byte what it
// was before this became a template.
func rootLong(name string) string {
	pad := func(usage string) string {
		// Descriptions start at column 40, as they did when this was a
		// literal string built around "wp-ops". The longest wp-ops row
		// ("wp-ops <category>/<command> [args...]") is 37, so nothing
		// overflows under the original name; "trellis ops" is 5 wider and
		// pushes its three longest rows out, hence the guard.
		if len(usage) >= 40 {
			return usage + " "
		}
		return usage + strings.Repeat(" ", 40-len(usage))
	}
	rows := [][2]string{
		{name + " <category>/<command> [args...]", "Run a command by its full key"},
		{name + " <category> <command> [args...]", "Run a command by category + name"},
		{name + " <command> [args...]", "Run a command by its bare name"},
		{name + " <command> --where", "Print the path to a command's script"},
		{name + " <command> --help", "Show a command's own help"},
		{"", ""},
		{name + " list", "List every command by category"},
		{name + " search <term>", "Search commands by name or description"},
		{name + " docs [term] [-l]", "Search the guides (no term lists them)"},
		{name + " doctor", "Check dependencies and environment"},
		{name + " init", "Install shell completions"},
		{name + " mcp-register", "Show MCP registration snippets for Claude/Mistral/Codex"},
		{name + " --json", "Output the command list as JSON"},
		{name + " --version", "Show version"},
	}

	var b strings.Builder
	fmt.Fprintf(&b, `%s is a single entry point for WordPress operations tools,
scripts, and utilities: backups, monitoring, WP-CLI helpers, Trellis
playbooks, and more.
`, name)
	for _, r := range rows {
		if r[0] == "" {
			b.WriteString("\n")
			continue
		}
		fmt.Fprintf(&b, "  %s%s\n", pad(r[0]), r[1])
	}
	return strings.TrimRight(b.String(), "\n")
}

// Execute runs the root command.
func Execute() error {
	rootCmd.Use = cmdName()
	rootCmd.Long = rootLong(cmdName())
	registerCatalogCommands(mustCatalog())
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return err
	}
	return nil
}
