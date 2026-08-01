package cmd

import (
	"path/filepath"
	"testing"

	"github.com/spf13/cobra"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

// TestCategoryBasenameCompletions ports the manual pass in
// docs/m4-go-cli-completion.md task 4: `wp-ops <category> <TAB>` offers
// every basename in that category, deduplicated, and stops completing once
// a basename is already present (the rest of argv belongs to the
// underlying script, not to wp-ops).
func TestCategoryBasenameCompletions(t *testing.T) {
	fn := categoryBasenameCompletions("scripts")

	got, directive := fn(nil, nil, "")
	if directive != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("directive = %v, want ShellCompDirectiveNoFileComp", directive)
	}
	if len(got) == 0 {
		t.Fatal("want at least one basename completion for the scripts category")
	}

	seen := make(map[string]bool, len(got))
	for _, b := range got {
		if seen[b] {
			t.Errorf("duplicate basename completion %q", b)
		}
		seen[b] = true
	}

	// db-backup is scripts/backup/db-backup.sh — a stable, unlikely-to-move
	// entry to pin against, same choice serverside_test.go makes elsewhere.
	if !seen["db-backup"] {
		t.Errorf("want db-backup among scripts completions, got %v", got)
	}

	got2, directive2 := fn(nil, []string{"db-backup"}, "")
	if directive2 != cobra.ShellCompDirectiveNoFileComp {
		t.Errorf("directive with a basename already chosen = %v, want ShellCompDirectiveNoFileComp", directive2)
	}
	if len(got2) != 0 {
		t.Errorf("want no completions once a basename is already chosen, got %v", got2)
	}
}

// TestCategoryBasenameCompletionsScoped checks that a category's
// completions only ever contain basenames that actually live in that
// category — the point of the two-token grammar
// (docs/m4-go-cli-completion.md task 4).
func TestCategoryBasenameCompletionsScoped(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("loading catalog: %v", err)
	}

	inScripts := make(map[string]bool)
	for _, e := range c.CommandsIn("scripts") {
		inScripts[filepath.Base(e.Key)] = true
	}

	fn := categoryBasenameCompletions("scripts")
	got, _ := fn(nil, nil, "")
	for _, b := range got {
		if !inScripts[b] {
			t.Errorf("scripts completions included %q, which isn't a scripts basename", b)
		}
	}
}
