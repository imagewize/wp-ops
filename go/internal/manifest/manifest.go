// Package manifest parses the "@directive" manifest blocks documented in
// docs/cli-ux-plan.md ("Directive format") out of a command script's header
// comment. It is a Go port of the bash implementation in wp-ops
// (manifest_directive_lines, load_manifest, manifest_parse_param_line) —
// see docs/m3-go-skeleton.md, task 2.
package manifest

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// maxDirectiveLines mirrors the bash parser's `head -80` — directives must
// appear in the first 80 lines of the file.
const maxDirectiveLines = 80

// Param is the shape shared by @arg and @flag lines: "NAME required|optional
// {choices-or-default} description". Bash parses both with the same
// function (manifest_parse_param_line); this is that function's Go
// counterpart, reused for both Command.Args and Command.Flags.
type Param struct {
	Name string `json:"name"`
	// RequiredRaw is the raw second token ("required", "optional", or
	// whatever malformed value was present — Lint flags anything else).
	RequiredRaw string `json:"required_raw"`
	Required    bool   `json:"required"`
	// Choices holds the "|"-separated values inside "{...}", when present.
	Choices []string `json:"choices,omitempty"`
	// Default holds a single bracketed value that isn't a choice list.
	Default     string `json:"default,omitempty"`
	Description string `json:"description,omitempty"`
	// Raw is the original "@arg"/"@flag" value line, kept for Lint's error
	// messages (bash's lint_manifest_command() quotes the offending line
	// verbatim).
	Raw string `json:"raw,omitempty"`
}

// Arg and Flag are aliases for Param: an @arg and an @flag line share an
// identical grammar and are only distinguished by which directive introduced
// them (see Command.Args / Command.Flags).
type Arg = Param
type Flag = Param

// Command holds every directive parsed out of one script's manifest block.
type Command struct {
	Key      string
	Desc     string
	Category string
	Platform string
	Runs     string
	Requires []string
	Args     []Arg
	Flags    []Flag
	Examples []string
	Doc      string
	// Mutates is the raw @mutates value ("true", "false", or "" when unset).
	// Kept as the raw string rather than a bool for the same reason Runs and
	// Platform are: "" has to stay distinguishable from an explicit value so
	// Lint can reject a typo, and so the "first directive wins" rule below
	// works the same way for all of them. catalog.Entry resolves it to a
	// bool — absent means mutating, the fail-safe reading.
	Mutates string

	// Annotated is true when the script had at least one recognized @
	// directive at all — the Go equivalent of bash's has_manifest(), which
	// checks presence rather than any specific field.
	Annotated bool
}

var (
	// Strips a leading comment marker ("#", "//", or "*"), with at most one
	// following space, same as bash's:
	//   sed -E 's/^[[:space:]]*(#|\/\/|\*)[[:space:]]?//'
	commentMarkerRe = regexp.MustCompile(`^[ \t]*(#|//|\*)[ \t]?`)

	// A recognized directive line, same as bash's:
	//   grep -E '^@[a-zA-Z]+([[:space:]]|$)'
	directiveLineRe = regexp.MustCompile(`^@[a-zA-Z]+([ \t]|$)`)

	// Splits "@directive  rest of the line" into its two tokens, mirroring
	// `read -r directive value <<< "$line"`: the first whitespace-delimited
	// token, then the remainder verbatim (leading separator whitespace
	// dropped, internal whitespace untouched).
	directiveSplitRe = regexp.MustCompile(`^(\S+)[ \t]*(.*)$`)

	// Strips "NAME  required-or-optional  " (first two whitespace-delimited
	// tokens plus trailing whitespace) off an @arg/@flag value, mirroring:
	//   sed -E 's/^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]*//'
	paramStripRe = regexp.MustCompile(`^[^ \t]+[ \t]+[^ \t]+[ \t]*`)

	// Splits the remainder of an @arg/@flag value into its optional
	// "{choices-or-default}" and free-text description, mirroring:
	//   ^\{([^}]*)\}[[:space:]]*(.*)$
	paramBracesRe = regexp.MustCompile(`^\{([^}]*)\}[ \t]*(.*)$`)
)

// directivesHandled is the set of directives load_manifest() recognizes.
// Anything else in a manifest block (e.g. "@version", "@see" in a PHP
// docblock) is silently ignored, matching bash's case statement.
var directivesHandled = map[string]bool{
	"@desc": true, "@category": true, "@runs": true, "@requires": true,
	"@doc": true, "@example": true, "@arg": true, "@flag": true, "@platform": true,
	"@mutates": true,
}

// DirectiveLines returns every recognized "@directive value" line found in
// the first maxDirectiveLines lines of scriptPath, comment markers already
// stripped. Port of manifest_directive_lines().
func DirectiveLines(scriptPath string) ([]string, error) {
	f, err := os.Open(scriptPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	for i := 0; i < maxDirectiveLines && scanner.Scan(); i++ {
		stripped := commentMarkerRe.ReplaceAllString(scanner.Text(), "")
		if directiveLineRe.MatchString(stripped) {
			lines = append(lines, stripped)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return lines, nil
}

// ParseParamLine parses one @arg/@flag value ("name required|optional
// {choices-or-default} description"). Port of manifest_parse_param_line().
func ParseParamLine(line string) Param {
	fields := strings.Fields(line)
	var name, required string
	if len(fields) > 0 {
		name = fields[0]
	}
	if len(fields) > 1 {
		required = fields[1]
	}

	rest := paramStripRe.ReplaceAllString(line, "")

	p := Param{Name: name, RequiredRaw: required, Required: required == "required", Raw: line}

	if m := paramBracesRe.FindStringSubmatch(rest); m != nil {
		braces, desc := m[1], m[2]
		if strings.Contains(braces, "|") {
			p.Choices = strings.Split(braces, "|")
		} else {
			p.Default = braces
		}
		p.Description = desc
	} else {
		p.Description = rest
	}

	return p
}

// splitDirective splits "@directive  rest of the line" into its directive
// token and verbatim remainder.
func splitDirective(line string) (directive, value string) {
	m := directiveSplitRe.FindStringSubmatch(line)
	if m == nil {
		return line, ""
	}
	return m[1], m[2]
}

// Parse builds a Command from a script's manifest block. Port of
// load_manifest(), inlined against a single command rather than an
// intermediate flat file (bash used a temp file to work around bash 3.2's
// lack of associative arrays; Go doesn't need that indirection).
func Parse(key, scriptPath string) (*Command, error) {
	lines, err := DirectiveLines(scriptPath)
	if err != nil {
		return nil, err
	}

	cmd := &Command{Key: key, Annotated: len(lines) > 0}

	for _, line := range lines {
		directive, value := splitDirective(line)
		if !directivesHandled[directive] {
			continue
		}

		switch directive {
		case "@desc":
			if cmd.Desc == "" {
				cmd.Desc = value
			}
		case "@category":
			if cmd.Category == "" {
				cmd.Category = value
			}
		case "@platform":
			if cmd.Platform == "" {
				cmd.Platform = value
			}
		case "@runs":
			if cmd.Runs == "" {
				cmd.Runs = value
			}
		case "@mutates":
			if cmd.Mutates == "" {
				cmd.Mutates = value
			}
		case "@requires":
			if cmd.Requires == nil && value != "" {
				cmd.Requires = strings.Fields(value)
			}
		case "@doc":
			if cmd.Doc == "" {
				cmd.Doc = value
			}
		case "@example":
			cmd.Examples = append(cmd.Examples, value)
		case "@arg":
			cmd.Args = append(cmd.Args, ParseParamLine(value))
		case "@flag":
			cmd.Flags = append(cmd.Flags, ParseParamLine(value))
		}
	}

	return cmd, nil
}

// RequiresString joins Requires back into the single space-separated value
// bash's manifest_get "requires" would have produced — used anywhere output
// needs to match bash's --json/help formatting exactly.
func (c *Command) RequiresString() string {
	return strings.Join(c.Requires, " ")
}

// Lint validates one command's directives, mirroring
// lint_manifest_command(). repoRoot is used to resolve @doc paths. It
// returns one message per problem found (nil/empty when clean).
func Lint(cmd *Command, repoRoot string) []string {
	var errs []string

	if cmd.Desc == "" {
		errs = append(errs, fmt.Sprintf("%s: missing @desc", cmd.Key))
	}

	if cmd.Runs != "" {
		switch cmd.Runs {
		case "local", "server", "either":
		default:
			errs = append(errs, fmt.Sprintf("%s: @runs '%s' must be local, server, or either", cmd.Key, cmd.Runs))
		}
	}

	// Spelled out here rather than shared with catalog.Platforms, matching
	// how @runs' values are handled: manifest is the lower layer and
	// importing catalog would invert the dependency. A typo caught here
	// fails the build; caught later it silently drops the command out of
	// every --platform filter.
	if cmd.Platform != "" {
		switch cmd.Platform {
		case "trellis", "wordpress", "any":
		default:
			errs = append(errs, fmt.Sprintf("%s: @platform '%s' must be trellis, wordpress, or any", cmd.Key, cmd.Platform))
		}
	}

	// Only "true"/"false" — not "yes", "1" or "no". @mutates decides whether
	// the MCP server makes a command surface to the user as its own decision
	// before it writes anything, so a value it doesn't understand must fail
	// the build rather than fall back to a default nobody chose.
	if cmd.Mutates != "" {
		switch cmd.Mutates {
		case "true", "false":
		default:
			errs = append(errs, fmt.Sprintf("%s: @mutates '%s' must be true or false", cmd.Key, cmd.Mutates))
		}
	}

	for _, p := range append(append([]Param{}, cmd.Args...), cmd.Flags...) {
		if p.Name == "" || p.RequiredRaw == "" {
			errs = append(errs, fmt.Sprintf("%s: malformed '%s' (expected: name required|optional {choices-or-default} description)", cmd.Key, p.Raw))
			continue
		}
		switch p.RequiredRaw {
		case "required", "optional":
		default:
			errs = append(errs, fmt.Sprintf("%s: '%s' requiredness must be 'required' or 'optional', got '%s'", cmd.Key, p.Name, p.RequiredRaw))
		}
	}

	if cmd.Doc != "" {
		if _, err := os.Stat(repoRoot + "/" + cmd.Doc); err != nil {
			errs = append(errs, fmt.Sprintf("%s: @doc points at a missing file '%s'", cmd.Key, cmd.Doc))
		}
	}

	return errs
}
