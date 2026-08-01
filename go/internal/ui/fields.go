// Package ui implements the interactive Bubble Tea picker that replaces
// bash's fzf_menu()/interactive_command_menu() (wp-ops:1962, wp-ops:2047)
// and their shared prompt_manifest_args() guided-prompting helper
// (wp-ops:484). See docs/m4-go-cli-completion.md, task 3.
package ui

import (
	"fmt"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

// fieldKind distinguishes an @arg from an @flag line — same value shape,
// different assembly into the final argv (a flag contributes its own name
// plus a value; an arg contributes only the value).
type fieldKind int

const (
	kindArg fieldKind = iota
	kindFlag
)

// field is one guided prompt, built from a single @arg/@flag manifest line.
// Port of the per-line state prompt_one_manifest_param computes before
// prompting (wp-ops:420-431).
type field struct {
	param     manifest.Param
	kind      fieldKind
	isBoolean bool
	hint      string
}

// buildFields walks an entry's declared @arg/@flag lines in source order
// (args first, then flags — matching prompt_manifest_args, wp-ops:518-524)
// and computes each one's prompt shape. Returns nil for an entry with no
// declared args/flags at all (including un-annotated entries), which the
// caller falls back to a single free-text prompt for, same as bash
// (wp-ops:494-497).
func buildFields(e catalog.Entry) []field {
	var out []field
	for _, p := range e.Args {
		out = append(out, newField(p, kindArg))
	}
	for _, p := range e.Flags {
		out = append(out, newField(p, kindFlag))
	}
	return out
}

func newField(p manifest.Param, kind fieldKind) field {
	f := field{param: p, kind: kind}

	hasBraces := len(p.Choices) > 0 || p.Default != ""
	if kind == kindFlag && !hasBraces {
		f.isBoolean = true
		return f
	}

	switch {
	case len(p.Choices) > 0:
		f.hint = fmt.Sprintf(" [%s]", strings.Join(p.Choices, "|"))
	case p.Default != "":
		if p.Required {
			f.hint = fmt.Sprintf(" (e.g. %s)", p.Default)
		} else {
			f.hint = fmt.Sprintf(" [default: %s]", p.Default)
		}
	}
	return f
}

// fieldOutcome is what applying a submitted value to a field produced —
// returned by resolveField so the caller (the Bubble Tea Update loop) can
// decide whether to advance to the next field or reprompt the same one.
type fieldOutcome struct {
	// Reprompt is true when a required field was left blank — the caller
	// must show the error and keep the same field active, port of the
	// `continue` in prompt_one_manifest_param's while loop (wp-ops:456-459).
	Reprompt bool
	// Args is what to append to the accumulated argv for this field, if
	// anything (nil for a skipped optional field or a boolean answered "no").
	Args []string
	// Note is a non-fatal warning to surface (e.g. a value outside the
	// declared choices), port of wp-ops:462-464. Empty when there's nothing
	// to show.
	Note string
}

// resolveField applies one submitted value to a field, port of
// prompt_one_manifest_param's body (wp-ops:420-473) minus the actual
// terminal I/O, which the Bubble Tea model owns.
func resolveField(f field, value string) fieldOutcome {
	if f.isBoolean {
		if len(value) > 0 && (value[0] == 'y' || value[0] == 'Y') {
			return fieldOutcome{Args: []string{f.param.Name}}
		}
		return fieldOutcome{}
	}

	if value == "" {
		if f.param.Required {
			return fieldOutcome{Reprompt: true, Note: fmt.Sprintf("%s is required.", f.param.Name)}
		}
		return fieldOutcome{}
	}

	var note string
	if len(f.param.Choices) > 0 && !containsChoice(f.param.Choices, value) {
		note = fmt.Sprintf("Note: %q isn't one of %s — using it anyway.", value, strings.Join(f.param.Choices, "|"))
	}

	if f.kind == kindFlag {
		return fieldOutcome{Args: []string{f.param.Name, value}, Note: note}
	}
	return fieldOutcome{Args: []string{value}, Note: note}
}

func containsChoice(choices []string, value string) bool {
	for _, c := range choices {
		if c == value {
			return true
		}
	}
	return false
}

// promptLabel is the text shown above a field's input, port of the
// "  ${_MP_NAME}${hint}: " prompt (wp-ops:454) and the boolean "?"  variant
// (wp-ops:437).
func promptLabel(f field) string {
	if f.isBoolean {
		return fmt.Sprintf("%s? [y/N]", f.param.Name)
	}
	return fmt.Sprintf("%s%s", f.param.Name, f.hint)
}
