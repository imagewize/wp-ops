// Package cmd wires the Cobra command tree for the wp-ops Go CLI: dynamic
// per-catalog-entry commands (full key + category-short forms), list,
// search, doctor, and --json/--version. See docs/m3-go-skeleton.md, task 7.
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/detect"
)

// jsonFlag backs `list --json` (list.go registers its own, properly-parsed
// flag). Root itself can't use Cobra flag parsing at all — see DisableFlagParsing below.
var jsonFlag bool

var rootCmd = &cobra.Command{
	Use:   "wp-ops",
	Short: "Unified CLI wrapper for wp-ops tools",
	Long: `wp-ops is a single entry point for WordPress operations tools,
scripts, and utilities: backups, monitoring, WP-CLI helpers, Trellis
playbooks, and more.

  wp-ops <category>/<command> [args...]   Run a command by its full key
  wp-ops <category> <command> [args...]   Run a command by category + name
  wp-ops <command> [args...]              Run a command by its bare name
  wp-ops <command> --where                Print the path to a command's script
  wp-ops <command> --help                 Show a command's own help

  wp-ops list                             List every command by category
  wp-ops search <term>                    Search commands by name or description
  wp-ops docs [term] [-l]                 Search the guides (no term lists them)
  wp-ops doctor                           Check dependencies and environment
  wp-ops --json                           Output the command list as JSON
  wp-ops --version                        Show version`,
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
	SilenceUsage:  true,
	SilenceErrors: true,
}

func rootRunE(cc *cobra.Command, args []string) error {
	c := mustCatalog()

	if len(args) == 0 {
		// Port of main()'s `[[ -t 0 && -t 1 ]]` branch (wp-ops:2154-2157):
		// launch the picker only on a real interactive terminal; a
		// piped/redirected invocation keeps printing list-equivalent output
		// so `wp-ops | less` etc. still work.
		if detect.IsTerminal(os.Stdin) && detect.IsTerminal(os.Stdout) {
			os.Exit(runInteractive(c))
			return nil
		}
		printCategorizedList(c)
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
		printCategorizedList(c)
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

// Execute runs the root command.
func Execute() error {
	registerCatalogCommands(mustCatalog())
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return err
	}
	return nil
}
