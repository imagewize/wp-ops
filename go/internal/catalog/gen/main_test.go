package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

// writeTemp writes content to a file named name in a fresh temp dir and
// returns its path.
func writeTemp(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("writing %s: %v", path, err)
	}
	return path
}

// TestExtensionsFor pins the per-category file-type filter to bash's
// name_matchers in discover_commands() (wp-ops:551-574). Widening one of
// these silently pulls non-runnable reference code into the catalog, which is
// exactly what the per-category carve-outs exist to prevent.
func TestExtensionsFor(t *testing.T) {
	tests := []struct {
		category string
		want     []string
	}{
		{"scripts", []string{".sh", ".js", ".py"}},
		{"trellis", []string{".sh", ".js", ".yml"}},
		{"wp-cli", []string{".sh", ".js", ".php"}},
		{"bedrock", []string{".sh", ".js", ".php"}},
		{"wordpress-utilities", []string{".sh", ".js", ".php", ".css"}},
		{"nginx", []string{".sh", ".js"}},
		{"troubleshooting", []string{".sh", ".js"}},
		{"mcp-server", []string{".sh", ".js"}},
	}

	for _, tt := range tests {
		t.Run(tt.category, func(t *testing.T) {
			got := extensionsFor(tt.category)
			if len(got) != len(tt.want) {
				t.Fatalf("got %d extensions %v, want %d %v", len(got), got, len(tt.want), tt.want)
			}
			for _, ext := range tt.want {
				if !got[ext] {
					t.Errorf("missing %s (got %v)", ext, got)
				}
			}
		})
	}

	// The carve-outs only make sense if they're actually exclusive.
	if extensionsFor("trellis")[".py"] {
		t.Error("trellis should not match .py — only scripts/ holds standalone Python")
	}
	if extensionsFor("wordpress-utilities")[".yml"] {
		t.Error("only trellis should match .yml (other categories' .yml is config data)")
	}
	if extensionsFor("nginx")[".php"] {
		t.Error("only wp-cli/bedrock/wordpress-utilities should match .php")
	}
}

// TestRunsOnFor ports the precedence in is_server_side_command()
// (wp-ops:126): an explicit @runs wins outright, and the hardcoded
// SERVER_SIDE_COMMANDS list is consulted only when @runs is absent.
func TestRunsOnFor(t *testing.T) {
	tests := []struct {
		name string
		runs string
		key  string
		want string
	}{
		{"explicit server", "server", "scripts/git/git-log-oneline", "server"},
		{"explicit local", "local", "scripts/git/git-log-oneline", "local"},
		{"no runs, not in fallback list", "", "scripts/git/git-log-oneline", "local"},
		{"no runs, in fallback list", "", "scripts/backup/db-backup", "server"},
		{
			// The whole point of the precedence: an explicit @runs local on a
			// command that's *also* in the hardcoded list must stay local.
			"explicit local overrides fallback list",
			"local", "scripts/monitoring/traffic-monitor", "local",
		},
		{
			// An unrecognised @runs value is non-empty, so it short-circuits
			// the fallback list too — same as bash's `[[ $runs == server ]]`.
			"unknown runs value is local, not fallback",
			"somewhere-else", "scripts/backup/site-backup", "local",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := runsOnFor(tt.runs, tt.key); got != tt.want {
				t.Errorf("runsOnFor(%q, %q) = %q, want %q", tt.runs, tt.key, got, tt.want)
			}
		})
	}
}

// TestDisplayCategoryFor covers the Phase F option 4 split
// (docs/cli-ux-plan.md): scripts/** subcategories with 4+ commands get
// promoted to their own DisplayCategory, everything else — including
// other categories' own @category tags, e.g. trellis/backup/*.yml also
// using "backup" — stays untouched.
func TestDisplayCategoryFor(t *testing.T) {
	tests := []struct {
		name             string
		category         string
		manifestCategory string
		want             string
	}{
		{"promoted scripts subcategory: monitoring", "scripts", "monitoring", "monitoring"},
		{"promoted scripts subcategory: images", "scripts", "images", "images"},
		{"promoted scripts subcategory: patterns", "scripts", "patterns", "patterns"},
		{"promoted scripts subcategory: release", "scripts", "release", "release"},
		{"non-promoted scripts subcategory stays scripts: backup", "scripts", "backup", "scripts"},
		{"non-promoted scripts subcategory stays scripts: woocommerce", "scripts", "woocommerce", "scripts"},
		{"scripts file with no @category at all", "scripts", "", "scripts"},
		{
			// trellis/backup/*.yml also tags "@category backup" — must not be
			// swept into the scripts-only "backup" grouping (there isn't one;
			// "backup" was never promoted) nor otherwise affected, since
			// promotion only ever applies within category == "scripts".
			"non-scripts category is never overridden, even with a matching manifest tag",
			"trellis", "backup", "trellis",
		},
		{
			"non-scripts category with a promoted-looking manifest tag is still untouched",
			"trellis", "monitoring", "trellis",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := displayCategoryFor(tt.category, tt.manifestCategory); got != tt.want {
				t.Errorf("displayCategoryFor(%q, %q) = %q, want %q", tt.category, tt.manifestCategory, got, tt.want)
			}
		})
	}
}

// TestCleanDescription ports clean_description() (wp-ops:221).
func TestCleanDescription(t *testing.T) {
	tests := []struct {
		name        string
		description string
		filename    string
		want        string
	}{
		{"trims surrounding whitespace", "   Backup the database   ", "db-backup.sh", "Backup the database"},
		{"strips self-referential filename and dash", "db-backup.sh - Backup the database", "db-backup.sh", "Backup the database"},
		{"strips em dash separator", "db-backup.sh — Backup the database", "db-backup.sh", "Backup the database"},
		{"strips colon separator", "db-backup.sh: Backup the database", "db-backup.sh", "Backup the database"},
		{"leaves a non-matching filename alone", "Backup the database", "other.sh", "Backup the database"},
		{
			// The comment on bash's version calls out this exact case: keep a
			// whole first sentence, not a fragment ending mid-clause.
			"keeps only the first sentence",
			"Resize images (in place). Trims whitespace, too", "batch-resize.sh",
			"Resize images (in place).",
		},
		{"strips trailing punctuation", "Backup the database,", "db-backup.sh", "Backup the database"},
		{"strips trailing semicolon and space", "Backup the database ; ", "db-backup.sh", "Backup the database"},
		{"empty stays empty", "", "db-backup.sh", ""},
		{"a lone separator collapses to empty", " - ", "db-backup.sh", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := cleanDescription(tt.description, tt.filename); got != tt.want {
				t.Errorf("cleanDescription(%q, %q) = %q, want %q", tt.description, tt.filename, got, tt.want)
			}
		})
	}
}

// TestCleanDescriptionTruncation covers the 72-character cap separately,
// since the interesting part is that it counts runes rather than bytes —
// byte-slicing a multibyte description would emit invalid UTF-8 into
// catalog.json.
func TestCleanDescriptionTruncation(t *testing.T) {
	t.Run("exactly 72 runes is untouched", func(t *testing.T) {
		in := strings.Repeat("a", 72)
		if got := cleanDescription(in, "x.sh"); got != in {
			t.Errorf("got %q (%d runes), want it unchanged", got, len([]rune(got)))
		}
	})

	t.Run("73 runes truncates to 71 plus ellipsis", func(t *testing.T) {
		got := cleanDescription(strings.Repeat("a", 73), "x.sh")
		want := strings.Repeat("a", 71) + "…"
		if got != want {
			t.Errorf("got %q, want %q", got, want)
		}
		if n := len([]rune(got)); n != 72 {
			t.Errorf("got %d runes, want 72", n)
		}
	})

	t.Run("truncates on runes, not bytes", func(t *testing.T) {
		// 80 two-byte runes: a byte-slice at 71 would land mid-rune.
		got := cleanDescription(strings.Repeat("é", 80), "x.sh")
		want := strings.Repeat("é", 71) + "…"
		if got != want {
			t.Errorf("got %q, want %q", got, want)
		}
		if !utf8.ValidString(got) {
			t.Error("truncated description is not valid UTF-8")
		}
	})
}

// TestFallbackDescription covers the header scrape used for un-annotated
// files — the path that keeps mcp-server/* in the catalog without annotating
// it (docs/m3-go-skeleton.md, decision #2).
func TestFallbackDescription(t *testing.T) {
	tests := []struct {
		name    string
		file    string
		key     string
		content string
		want    string
	}{
		{
			"php docblock",
			"scanner-wrapper.php", "wp-cli/security/scanner-wrapper",
			"<?php\n/**\n * Run both malware scanners\n */\n",
			"Run both malware scanners",
		},
		{
			"js docblock wins over a later line comment",
			"index.js", "mcp-server/index",
			"/**\n * Start the MCP server\n */\n// not this one\n",
			"Start the MCP server",
		},
		{
			"js falls back to a line comment when there is no docblock",
			"start.js", "mcp-server/start",
			"// Start the MCP server\nconsole.log('hi')\n",
			"Start the MCP server",
		},
		{
			"shell skips the shebang",
			"git-log-oneline.sh", "scripts/git/git-log-oneline",
			"#!/usr/bin/env bash\n# Compact git log output\nset -euo pipefail\n",
			"Compact git log output",
		},
		{
			"python docstring",
			"openverse_search.py", "scripts/images/openverse_search",
			"#!/usr/bin/env python3\n\"\"\"Search Openverse for images\"\"\"\n",
			"Search Openverse for images",
		},
		{
			"description is cleaned, not just scraped",
			"db-backup.sh", "scripts/backup/db-backup",
			"#!/usr/bin/env bash\n# db-backup.sh - Back up a database. And more prose here\n",
			"Back up a database.",
		},
		{
			"no comment at all falls back to the key's basename",
			"mystery.sh", "scripts/misc/mystery",
			"set -euo pipefail\necho hi\n",
			"mystery",
		},
		{
			// hashCommentRe requires whitespace after '#', so a bare '#!' or
			// '#comment' is not a description.
			"tightly-packed comment is not scraped",
			"tight.sh", "scripts/misc/tight",
			"#!/usr/bin/env bash\n#nospace\n",
			"tight",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := writeTemp(t, tt.file, tt.content)
			if got := fallbackDescription(path, tt.key); got != tt.want {
				t.Errorf("fallbackDescription(%s) = %q, want %q", tt.file, got, tt.want)
			}
		})
	}
}

// TestFallbackDescriptionLineLimits covers the per-extension scan windows:
// 20 lines for comment-style headers, 5 for a Python docstring. A description
// buried below the window is deliberately not found.
func TestFallbackDescriptionLineLimits(t *testing.T) {
	t.Run("python docstring past line 5 is not scraped", func(t *testing.T) {
		content := strings.Repeat("\n", 6) + `"""Too far down"""` + "\n"
		path := writeTemp(t, "late.py", content)
		if got := fallbackDescription(path, "scripts/images/late"); got != "late" {
			t.Errorf("got %q, want the basename fallback %q", got, "late")
		}
	})

	t.Run("python docstring within line 5 is scraped", func(t *testing.T) {
		content := strings.Repeat("\n", 3) + `"""Close enough"""` + "\n"
		path := writeTemp(t, "early.py", content)
		if got := fallbackDescription(path, "scripts/images/early"); got != "Close enough" {
			t.Errorf("got %q, want %q", got, "Close enough")
		}
	})

	t.Run("shell comment past line 20 is not scraped", func(t *testing.T) {
		content := strings.Repeat("\n", 25) + "# Too far down\n"
		path := writeTemp(t, "late.sh", content)
		if got := fallbackDescription(path, "scripts/misc/late"); got != "late" {
			t.Errorf("got %q, want the basename fallback %q", got, "late")
		}
	})
}

func TestScrapeFirstMissingFile(t *testing.T) {
	got := scrapeFirst(filepath.Join(t.TempDir(), "nope.sh"), 20, hashCommentRe)
	if got != "" {
		t.Errorf("got %q, want empty string for an unreadable file", got)
	}
}

// TestFindRepoRoot guards the "four directories up from this source file"
// assumption — it breaks silently if the gen package is ever moved.
func TestFindRepoRoot(t *testing.T) {
	root, err := findRepoRoot()
	if err != nil {
		t.Fatalf("findRepoRoot(): %v", err)
	}
	for _, want := range []string{"wp-ops", "go.mod", "scripts"} {
		if _, err := os.Stat(filepath.Join(root, want)); err != nil {
			t.Errorf("repo root %s is missing %s: %v", root, want, err)
		}
	}
}

// TestExcludedFilenames pins the exclusion set to bash's
// `! -name ...` filters — each of these is a real file that would otherwise
// be discovered as a bogus command.
func TestExcludedFilenames(t *testing.T) {
	for _, name := range []string{"wp-ops", "variable-check.yml", "transient-debug-browser.php"} {
		if !excludedFilenames[name] {
			t.Errorf("%s should be excluded from discovery", name)
		}
	}
	if len(excludedFilenames) != 3 {
		t.Errorf("got %d exclusions, want 3 — bash's filter list has not changed", len(excludedFilenames))
	}
}
