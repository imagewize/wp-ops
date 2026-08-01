package exec

import (
	"fmt"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

// FormatGenericHelp renders --help for a .sh/.js/.py command (and, until M4
// implements their own executors, wp-cli/.php and wordpress-utilities
// commands too) from its catalog entry. Manifest-first by construction — no
// probing the script itself, unlike bash's fallback path (wp-ops:1459-1480)
// which risks actually running the script with "--help" as a positional
// argument when it has no --help handling of its own.
func FormatGenericHelp(e catalog.Entry) string {
	var b strings.Builder
	writeManifestHelpBody(&b, e)
	return b.String()
}

// writeManifestHelpBody renders the shared body of print_manifest_help
// (wp-ops:352): usage line, description, arguments, flags, requires, the
// server-side note, examples, docs, and the script path. FormatHelp
// (ansible.go) and FormatGenericHelp both build on this, differing only in
// the executor-specific trailer bash appends after it.
func writeManifestHelpBody(b *strings.Builder, e catalog.Entry) {
	if !e.Annotated {
		fmt.Fprintf(b, "Usage: wp-ops %s [args...]\n\n", e.Key)
		fmt.Fprintf(b, "Description: %s\n\n", e.Description)
		fmt.Fprintf(b, "Script: %s\n", e.ScriptPath)
		return
	}

	fmt.Fprintf(b, "Usage: wp-ops %s [args...]\n\n", e.Key)

	if e.Description != "" {
		fmt.Fprintf(b, "%s\n\n", e.Description)
	}

	writeParamBlock(b, "Arguments:", e.Args)
	writeParamBlock(b, "Flags:", e.Flags)

	if len(e.Requires) > 0 {
		fmt.Fprintf(b, "Requires: %s\n\n", e.RequiresString())
	}

	if e.Runs == "server" {
		fmt.Fprintln(b, "Runs on the server — run without --help for SSH instructions.")
		fmt.Fprintln(b)
	}

	if len(e.Examples) > 0 {
		fmt.Fprintln(b, "Examples:")
		for _, ex := range e.Examples {
			fmt.Fprintf(b, "  %s\n", ex)
		}
		fmt.Fprintln(b)
	}

	if e.Doc != "" {
		fmt.Fprintf(b, "Docs: %s\n", e.Doc)
	}
	fmt.Fprintf(b, "Script: %s\n", e.ScriptPath)
}

func writeParamBlock(b *strings.Builder, heading string, params []manifest.Param) {
	if len(params) == 0 {
		return
	}
	fmt.Fprintln(b, heading)
	for _, p := range params {
		fmt.Fprintln(b, formatParamLine(p))
	}
	fmt.Fprintln(b)
}

// formatParamLine is the Go port of manifest_print_param_line (wp-ops:341).
func formatParamLine(p manifest.Param) string {
	braces := p.Default
	if len(p.Choices) > 0 {
		braces = strings.Join(p.Choices, "|")
	}
	if braces != "" {
		return fmt.Sprintf("  %-18s %-9s {%s}  %s", p.Name, p.RequiredRaw, braces, p.Description)
	}
	return fmt.Sprintf("  %-18s %-9s %s", p.Name, p.RequiredRaw, p.Description)
}
