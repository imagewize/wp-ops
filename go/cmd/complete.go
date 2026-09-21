package cmd

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/detect"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

// Argument completion from the manifest — Phase G item G3
// (docs/cli-ux-plan.md). Completion used to stop at the command name:
// `wp-ops backup <TAB>` offered the ten basenames, and `wp-ops db-pull
// <TAB>` offered nothing at all, even though the manifest declares
// `site` and `env` with `{production|staging}` choices right there in the
// script header. Everything below turns that already-parsed @arg/@flag
// data into completions.

// universalFlags are handled by executeEntry for every entry regardless of
// executor, so they complete on every command (see dispatch.go).
var universalFlags = []cobra.Completion{
	cobra.CompletionWithDesc("--help", "Show this command's own help"),
	cobra.CompletionWithDesc("--where", "Print the path to this command's script"),
}

// siteArgNames are the @arg names that hold a Trellis site name. Both
// spellings are in the catalog — the playbooks use `site`, the shell
// scripts `site-name` — and neither declares choices, because the answer
// lives in the project rather than in the script.
var siteArgNames = map[string]bool{"site": true, "site-name": true}

// pathArgNames and pathArgSuffixes mark the @arg names that hold a
// filesystem path, so completion can hand the slot back to the shell's own
// file completion instead of suppressing it. Erring here is cheap: the
// worst case is a filename menu on an argument that wanted a word.
var pathArgNames = map[string]bool{
	"path": true, "input": true, "output": true, "files": true, "template": true,
}

var pathArgSuffixes = []string{"-file", "_file", "-dir", "_dir", "-path", "_path"}

func isPathArg(name string) bool {
	if pathArgNames[name] {
		return true
	}
	for _, suffix := range pathArgSuffixes {
		if strings.HasSuffix(name, suffix) {
			return true
		}
	}
	return false
}

// positionalIndex reports which @arg slot the token being completed fills,
// given the tokens already typed after the command name.
//
// Flags are skipped rather than parsed. wp-ops deliberately re-parses none
// of a script's flag grammar (DisableFlagParsing everywhere — see
// dispatch.go), so it cannot know whether the token after `--host` is that
// flag's value or the next positional. Counting only non-flag tokens gets
// the common cases right and, in the `--flag value positional` case, offers
// the previous slot's completions — wrong, but wrong in a way that costs a
// keystroke rather than a mistake, since nothing is inserted without the
// user picking it.
func positionalIndex(args []string) int {
	n := 0
	for _, a := range args {
		if strings.HasPrefix(a, "-") {
			continue
		}
		n++
	}
	return n
}

// entryArgCompletions completes one catalog entry's arguments. args is
// everything typed after the command name; toComplete is the partial token
// under the cursor.
func entryArgCompletions(e catalog.Entry, args []string, toComplete string) ([]cobra.Completion, cobra.ShellCompDirective) {
	if strings.HasPrefix(toComplete, "-") {
		return flagCompletions(e), cobra.ShellCompDirectiveNoFileComp
	}

	idx := positionalIndex(args)
	if idx >= len(e.Args) {
		// Either the command declares no arguments, or every declared slot
		// is filled. Say nothing rather than guess — but keep file
		// completion off, so an undeclared slot doesn't silently dump the
		// working directory.
		return nil, cobra.ShellCompDirectiveNoFileComp
	}

	p := e.Args[idx]
	var comps []cobra.Completion

	switch {
	case len(p.Choices) > 0:
		for _, choice := range p.Choices {
			comps = append(comps, cobra.CompletionWithDesc(choice, p.Description))
		}
	case siteArgNames[p.Name]:
		for _, site := range completionSites() {
			comps = append(comps, cobra.CompletionWithDesc(site, p.Description))
		}
	}

	// With real values to offer, their descriptions already say what the
	// slot is. Without any, the hint is the whole point: it's the
	// difference between "TAB does nothing" and knowing what to type.
	if len(comps) == 0 {
		comps = cobra.AppendActiveHelp(comps, argHint(p))
		if isPathArg(p.Name) {
			return comps, cobra.ShellCompDirectiveDefault
		}
	}

	return comps, cobra.ShellCompDirectiveNoFileComp
}

// argHint renders one @arg as a single line of ActiveHelp: the name, whether
// it is required, its description, and the manifest's bracketed value as an
// example. That bracketed value is deliberately *not* offered as a
// completion — `{example.com}`, `{~/wp-cli.phar}`, `{/opt/plesk/php/8.2/bin/php}`
// are placeholders showing the shape of an answer, and inserting one as
// though it were a default would be worse than offering nothing.
func argHint(p manifest.Param) string {
	var b strings.Builder
	b.WriteString(p.Name)
	if p.Required {
		b.WriteString(" (required)")
	} else {
		b.WriteString(" (optional)")
	}
	if p.Description != "" {
		b.WriteString(" — ")
		b.WriteString(p.Description)
	}
	if p.Default != "" {
		b.WriteString(" [e.g. ")
		b.WriteString(p.Default)
		b.WriteString("]")
	}
	return b.String()
}

func flagCompletions(e catalog.Entry) []cobra.Completion {
	comps := make([]cobra.Completion, 0, len(e.Flags)+len(universalFlags))
	for _, f := range e.Flags {
		comps = append(comps, cobra.CompletionWithDesc(f.Name, f.Description))
	}
	return append(comps, universalFlags...)
}

// completionSites resolves site names for the `site`/`site-name` slots
// without prompting or printing anything — resolveTrellisDir() asks for
// confirmation on a detected directory, which a completion function must
// never do. $TRELLIS_DIR wins when set, exactly as it does at run time; a
// project detected from the working directory is used silently, since
// reading its group_vars is harmless in a way running a playbook against it
// is not.
func completionSites() []string {
	if dir := os.Getenv("TRELLIS_DIR"); dir != "" {
		return detect.TrellisSites(dir)
	}
	cwd, err := os.Getwd()
	if err != nil {
		return nil
	}
	home, _ := os.UserHomeDir()
	if dir, ok := detect.TrellisDir(cwd, home); ok {
		return detect.TrellisSites(dir)
	}
	return nil
}

// resolveForCompletion finds the entry a typed command name refers to,
// using the same two-step resolution as execution (full key first, then an
// unambiguous basename — see rootRunE and runCategory). An ambiguous
// basename resolves to nothing: the entries behind it may declare different
// arguments, and running it would be an error anyway.
func resolveForCompletion(c *catalog.Catalog, candidate string) (catalog.Entry, bool) {
	if e, ok := c.Lookup(candidate); ok {
		return e, true
	}
	if matches := c.FindByBasename(candidate); len(matches) == 1 {
		return matches[0], true
	}
	return catalog.Entry{}, false
}

// scopedResolveForCompletion is resolveForCompletion for the category form
// (`wp-ops backup db-pull <TAB>`), preferring a basename owned by the
// category before falling back to the whole catalog — the resolution order
// runCategory dispatches on.
func scopedResolveForCompletion(c *catalog.Catalog, scope categoryScope, candidate string) (catalog.Entry, bool) {
	if e, ok := c.Lookup(candidate); ok {
		return e, true
	}

	owned := make(map[string]bool)
	for _, e := range scope.members(c) {
		owned[e.Key] = true
	}
	var inCategory []catalog.Entry
	matches := c.FindByBasename(candidate)
	for _, m := range matches {
		if owned[m.Key] {
			inCategory = append(inCategory, m)
		}
	}
	if len(inCategory) == 0 {
		inCategory = matches
	}
	if len(inCategory) == 1 {
		return inCategory[0], true
	}
	return catalog.Entry{}, false
}

// basenames lists every command's short name once, for the command-name
// slot. Shared by the root and per-category completions, which differ only
// in which entries they draw from. Deliberately bare names rather than
// name-plus-description: that is a separate change to a surface G3 doesn't
// touch, and these are pinned as bare strings by dispatch_test.go.
func basenames(entries []catalog.Entry) []cobra.Completion {
	seen := make(map[string]bool, len(entries))
	out := make([]cobra.Completion, 0, len(entries))
	for _, e := range entries {
		b := filepath.Base(e.Key)
		if seen[b] {
			continue
		}
		seen[b] = true
		out = append(out, b)
	}
	return out
}
