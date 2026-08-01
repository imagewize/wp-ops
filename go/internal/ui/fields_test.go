package ui

import (
	"reflect"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

func TestBuildFields_ArgsBeforeFlags(t *testing.T) {
	e := catalog.Entry{
		Args:  []manifest.Param{{Name: "site", RequiredRaw: "required", Required: true}},
		Flags: []manifest.Param{{Name: "--dry-run", RequiredRaw: "optional"}},
	}
	fields := buildFields(e)
	if len(fields) != 2 {
		t.Fatalf("len(fields) = %d, want 2", len(fields))
	}
	if fields[0].kind != kindArg || fields[0].param.Name != "site" {
		t.Errorf("fields[0] = %+v, want the arg first", fields[0])
	}
	if fields[1].kind != kindFlag || fields[1].param.Name != "--dry-run" {
		t.Errorf("fields[1] = %+v, want the flag second", fields[1])
	}
}

func TestBuildFields_NoArgsOrFlags(t *testing.T) {
	e := catalog.Entry{Annotated: true, Description: "does a thing"}
	if fields := buildFields(e); fields != nil {
		t.Errorf("buildFields() = %+v, want nil", fields)
	}
}

func TestNewField_BooleanFlag(t *testing.T) {
	// A flag with no {choices-or-default} braces at all is a boolean
	// switch, port of prompt_one_manifest_param's is_boolean branch
	// (wp-ops:425-426).
	f := newField(manifest.Param{Name: "--force", RequiredRaw: "optional"}, kindFlag)
	if !f.isBoolean {
		t.Errorf("isBoolean = false, want true for a bracket-less flag")
	}
	if f.hint != "" {
		t.Errorf("hint = %q, want empty for a boolean flag", f.hint)
	}
}

func TestNewField_ArgWithNoBraces_NotBoolean(t *testing.T) {
	// Only flags go boolean on no-braces; a bare @arg with no braces is
	// still a plain required/optional text field.
	f := newField(manifest.Param{Name: "site", RequiredRaw: "required"}, kindArg)
	if f.isBoolean {
		t.Errorf("isBoolean = true, want false for an @arg")
	}
}

func TestNewField_Choices(t *testing.T) {
	f := newField(manifest.Param{Name: "env", RequiredRaw: "required", Choices: []string{"staging", "production"}}, kindArg)
	if f.hint != " [staging|production]" {
		t.Errorf("hint = %q, want choice list", f.hint)
	}
}

func TestNewField_DefaultRequired(t *testing.T) {
	f := newField(manifest.Param{Name: "port", RequiredRaw: "required", Required: true, Default: "22"}, kindArg)
	if f.hint != " (e.g. 22)" {
		t.Errorf("hint = %q, want example-style hint for a required default", f.hint)
	}
}

func TestNewField_DefaultOptional(t *testing.T) {
	f := newField(manifest.Param{Name: "port", RequiredRaw: "optional", Default: "22"}, kindArg)
	if f.hint != " [default: 22]" {
		t.Errorf("hint = %q, want default-style hint for an optional default", f.hint)
	}
}

func TestResolveField_BooleanYes(t *testing.T) {
	f := field{param: manifest.Param{Name: "--force"}, isBoolean: true}
	for _, in := range []string{"y", "Y", "yes"} {
		out := resolveField(f, in)
		if !reflect.DeepEqual(out.Args, []string{"--force"}) {
			t.Errorf("resolveField(%q).Args = %v, want [--force]", in, out.Args)
		}
	}
}

func TestResolveField_BooleanNo(t *testing.T) {
	f := field{param: manifest.Param{Name: "--force"}, isBoolean: true}
	for _, in := range []string{"", "n", "no", "anything else"} {
		out := resolveField(f, in)
		if out.Args != nil {
			t.Errorf("resolveField(%q).Args = %v, want nil", in, out.Args)
		}
	}
}

func TestResolveField_RequiredBlank_Reprompts(t *testing.T) {
	f := field{param: manifest.Param{Name: "site", Required: true}}
	out := resolveField(f, "")
	if !out.Reprompt {
		t.Fatal("Reprompt = false, want true for a blank required field")
	}
	if out.Note == "" {
		t.Error("expected an error note when reprompting")
	}
}

func TestResolveField_OptionalBlank_Skips(t *testing.T) {
	f := field{param: manifest.Param{Name: "env", Required: false}}
	out := resolveField(f, "")
	if out.Reprompt {
		t.Fatal("Reprompt = true, want false for a blank optional field")
	}
	if out.Args != nil {
		t.Errorf("Args = %v, want nil for a skipped optional field", out.Args)
	}
}

func TestResolveField_Arg_AppendsValueOnly(t *testing.T) {
	f := field{kind: kindArg, param: manifest.Param{Name: "site"}}
	out := resolveField(f, "example.com")
	if !reflect.DeepEqual(out.Args, []string{"example.com"}) {
		t.Errorf("Args = %v, want [example.com]", out.Args)
	}
}

func TestResolveField_Flag_AppendsNameAndValue(t *testing.T) {
	f := field{kind: kindFlag, param: manifest.Param{Name: "--env"}}
	out := resolveField(f, "staging")
	if !reflect.DeepEqual(out.Args, []string{"--env", "staging"}) {
		t.Errorf("Args = %v, want [--env staging]", out.Args)
	}
}

func TestResolveField_ChoiceMismatch_NotesButAccepts(t *testing.T) {
	f := field{kind: kindArg, param: manifest.Param{Name: "env", Choices: []string{"staging", "production"}}}
	out := resolveField(f, "dev")
	if out.Reprompt {
		t.Fatal("Reprompt = true, want false — an off-list value is still accepted")
	}
	if !reflect.DeepEqual(out.Args, []string{"dev"}) {
		t.Errorf("Args = %v, want [dev]", out.Args)
	}
	if out.Note == "" {
		t.Error("expected a note about the off-list value")
	}
}

func TestResolveField_ChoiceMatch_NoNote(t *testing.T) {
	f := field{kind: kindArg, param: manifest.Param{Name: "env", Choices: []string{"staging", "production"}}}
	out := resolveField(f, "staging")
	if out.Note != "" {
		t.Errorf("Note = %q, want empty for an on-list value", out.Note)
	}
}

func TestFilterEntries_EmptyQueryReturnsAll(t *testing.T) {
	all := []catalog.Entry{
		{Key: "scripts/backup/db-backup", Description: "backup"},
		{Key: "trellis/provision/tags", Description: "provision"},
	}
	got := filterEntries(all, "")
	if len(got) != 2 {
		t.Fatalf("filterEntries(\"\") = %d entries, want 2", len(got))
	}
}

func TestFilterEntries_MatchesKeyOrDescription(t *testing.T) {
	all := []catalog.Entry{
		{Key: "scripts/backup/db-backup", Description: "database backup"},
		{Key: "wp-cli/security/scanner", Description: "malware scan"},
	}
	got := filterEntries(all, "backup")
	if len(got) != 1 || got[0].Key != "scripts/backup/db-backup" {
		t.Fatalf("filterEntries(%q) = %+v, want just db-backup", "backup", got)
	}
}
