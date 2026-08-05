package exec

import (
	"fmt"
	"path/filepath"
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

// PreviewBody renders the same manifest-derived usage/args/flags/examples
// body used by every executor's --help, without any executor-specific
// trailer (the "Runs via ansible-playbook..."/"Runs as: wp ..." lines
// FormatHelp/FormatWPCLIHelp/FormatSnippetHelp append). The internal/ui
// picker's preview pane reuses this verbatim per M4 task 3, rather than
// re-deriving its own rendering of a catalog.Entry.
func PreviewBody(e catalog.Entry) string {
	var b strings.Builder
	writeManifestHelpBody(&b, e)
	return b.String()
}

// UsageLine renders a real usage line — "Usage: wp-ops db-backup [site-name]
// [environment] [options]" — from a command's declared @arg/@flag manifest,
// naming the command the way a user would type it (Entry.CommandName) rather
// than by its internal catalog key.
//
// This is the shape trellis-cli's per-command Help() hand-writes ("Usage:
// trellis deploy [options] ENVIRONMENT [SITE]"); here it's derived, so it
// can't drift from the arguments the command actually documents.
func UsageLine(e catalog.Entry) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Usage: wp-ops %s", e.CommandName())

	for _, a := range e.Args {
		if a.Required {
			fmt.Fprintf(&b, " <%s>", a.Name)
		} else {
			fmt.Fprintf(&b, " [%s]", a.Name)
		}
	}
	if len(e.Flags) > 0 {
		b.WriteString(" [options]")
	}
	// Nothing declared (un-annotated commands, and annotated ones that take
	// no arguments) still accepts a free-text argv — the picker's final
	// prompt passes it straight through — so say so rather than implying the
	// command takes nothing.
	if len(e.Args) == 0 && len(e.Flags) == 0 {
		b.WriteString(" [args...]")
	}
	return b.String()
}

// DetailBody renders the block the picker shows once a command is chosen:
// the same manifest material as --help, but headed by UsageLine's real usage
// rather than the "<full-key> [args...]" placeholder, and without the
// Script: trailer (an implementation detail at the moment someone is about
// to answer "site-url:"). Requires/platform/server-side facts collapse onto
// one meta line — they used to be per-row tags in the browse list, where
// they wrapped and broke the column alignment at any realistic pane width.
func DetailBody(e catalog.Entry) string {
	var b strings.Builder
	b.WriteString(UsageLine(e))
	b.WriteString("\n\n")

	if e.Description != "" {
		fmt.Fprintf(&b, "%s\n\n", e.Description)
	}

	// Requirements come before the parameter blocks, not after them as
	// --help orders things: the picker shows this in a viewport roughly 14
	// rows tall, and a command with several options pushes whatever trails
	// them below the fold. "Needs curl" and "runs on the server" are the two
	// facts that decide whether to run the command at all, so they belong
	// above the material you scroll through, not after it.
	var meta []string
	if len(e.Requires) > 0 {
		meta = append(meta, "Requires: "+e.RequiresString())
	}
	if e.Platform != "" {
		meta = append(meta, "Platform: "+e.Platform)
	}
	if e.RunsOn == "server" {
		meta = append(meta, "Runs on the server")
	} else if note := localSiteDependencyNote(e); note != "" {
		// Not server-side, but still tied to a project on disk: .php scripts
		// run via `wp eval-file`/`wp --require` against $WP_SITE_DIR, .yml
		// playbooks via ansible-playbook against $TRELLIS_DIR (see
		// executeWPCLI/executeAnsible in cmd/dispatch.go, which dispatch on
		// this same extension). --help already states this via the
		// executor-specific trailer FormatWPCLIHelp/FormatHelp append after
		// this body; DetailBody has no such trailer, so it has to say so
		// here or the picker never mentions it before prompting for args.
		meta = append(meta, note)
	}
	if len(meta) > 0 {
		fmt.Fprintf(&b, "%s\n\n", strings.Join(meta, " · "))
	}

	// Examples precede the parameter tables, as they do in trellis-cli's
	// hand-written help ("$ trellis alias --skip-local" sits above Options).
	// Same fold argument as the meta line: a worked invocation is the most
	// actionable thing here for someone about to type an argument, and the
	// exhaustive per-parameter tables are what can afford to scroll.
	if len(e.Examples) > 0 {
		fmt.Fprintln(&b, "Examples:")
		for _, ex := range e.Examples {
			fmt.Fprintf(&b, "  %s\n", ex)
		}
		fmt.Fprintln(&b)
	}

	writeParamBlock(&b, "Arguments:", e.Args)
	// "Options:" rather than --help's "Flags:", matching the heading
	// trellis-cli uses and the one `--help` output conventionally carries.
	writeParamBlock(&b, "Options:", e.Flags)

	if e.Doc != "" {
		fmt.Fprintf(&b, "Docs: %s\n", e.Doc)
	}

	return strings.TrimRight(b.String(), "\n")
}

// localSiteDependencyNote reports the env var a "local" command still
// resolves a project from, if any, keyed off the same file extension
// executeEntry (cmd/dispatch.go) dispatches on — so this can't drift from
// which executor actually runs the command. Plain scripts (.sh/.js/...)
// return "": most of them are self-contained (image conversion, git
// helpers) and don't target a WP_SITE_DIR/TRELLIS_DIR project at all.
func localSiteDependencyNote(e catalog.Entry) string {
	switch filepath.Ext(e.ScriptPath) {
	case ".php":
		return "Runs locally against $WP_SITE_DIR"
	case ".yml":
		return "Runs locally against $TRELLIS_DIR"
	default:
		return ""
	}
}

// writeManifestHelpBody renders the shared body of print_manifest_help
// (wp-ops:352): usage line, description, arguments, flags, requires, the
// server-side note, examples, docs, and the script path. FormatHelp
// (ansible.go) and FormatGenericHelp both build on this, differing only in
// the executor-specific trailer bash appends after it.
func writeManifestHelpBody(b *strings.Builder, e catalog.Entry) {
	if !e.Annotated {
		fmt.Fprintf(b, "%s\n\n", UsageLine(e))
		fmt.Fprintf(b, "Description: %s\n\n", e.Description)
		fmt.Fprintf(b, "Script: %s\n", e.ScriptPath)
		return
	}

	fmt.Fprintf(b, "%s\n\n", UsageLine(e))

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
