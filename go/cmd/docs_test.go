package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// writeDocs materializes a small doc tree under t.TempDir() and returns its
// root, so findDocs/searchDocs can be exercised against real files without
// touching the repo checkout.
func writeDocs(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for rel, content := range files {
		path := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatalf("mkdir for %s: %v", rel, err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatalf("writing %s: %v", rel, err)
		}
	}
	return root
}

// TestFindDocs ports find_docs (wp-ops:1630-1634): every *.md file, sorted,
// excluding .git/node_modules/vendor and non-.md files.
func TestFindDocs(t *testing.T) {
	root := writeDocs(t, map[string]string{
		"README.md":                  "top",
		"guides/backup.md":           "guide",
		"guides/notes.txt":           "not markdown",
		".git/COMMIT_EDITMSG":        "not a doc",
		"node_modules/pkg/README.md": "vendored, excluded",
		"vendor/lib/README.md":       "vendored, excluded",
	})

	got, err := findDocs(root)
	if err != nil {
		t.Fatalf("findDocs: %v", err)
	}

	want := []string{
		filepath.Join(root, "README.md"),
		filepath.Join(root, "guides/backup.md"),
	}
	if len(got) != len(want) {
		t.Fatalf("findDocs = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("findDocs[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

// TestCompileDocTerm covers the -w/--word distinction (DOC_GREP_OPTS,
// wp-ops:1628): a bare term matches as a substring, --word requires a word
// boundary so short terms like "oom" don't hit inside "server room".
func TestCompileDocTerm(t *testing.T) {
	tests := []struct {
		name      string
		term      string
		wholeWord bool
		text      string
		want      bool
	}{
		{"substring match", "oom", false, "the server room is loud", true},
		{"whole word rejects a substring hit", "oom", true, "the server room is loud", false},
		{"whole word matches a standalone word", "oom", true, "an OOM killer event", true},
		{"case-insensitive by default", "Manifest", false, "the manifest file", true},
		{"regex metacharacters are literal", "wp-ops", false, "run wp-ops docs", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			re, err := compileDocTerm(tt.term, tt.wholeWord)
			if err != nil {
				t.Fatalf("compileDocTerm: %v", err)
			}
			if got := re.MatchString(tt.text); got != tt.want {
				t.Errorf("MatchString(%q) = %v, want %v", tt.text, got, tt.want)
			}
		})
	}
}

// TestCollapseDocWhitespace ports the sed pipeline in print_docs_results
// (wp-ops:1719-1720): trim leading indentation, collapse runs of 2+
// whitespace, then truncate to docLineWidth with an ellipsis.
func TestCollapseDocWhitespace(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"trims leading indentation", "    - a list item", "- a list item"},
		{"collapses internal runs", "a   b    c", "a b c"},
		{"short line is untouched otherwise", "hello world", "hello world"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := collapseDocWhitespace(tt.in); got != tt.want {
				t.Errorf("collapseDocWhitespace(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}

	long := ""
	for i := 0; i < 120; i++ {
		long += "x"
	}
	got := collapseDocWhitespace(long)
	if len(got) == 0 {
		t.Fatal("collapseDocWhitespace returned empty string")
	}
	runes := []rune(got)
	if len(runes) != docLineWidth {
		t.Errorf("truncated length = %d, want %d", len(runes), docLineWidth)
	}
	if runes[len(runes)-1] != '…' {
		t.Errorf("truncated line should end with an ellipsis, got %q", got)
	}
}

// TestSearchDocFile pins matchCount against grep -c (matching lines, not
// occurrences) and the docMatchLimit cap on lines actually returned.
func TestSearchDocFile(t *testing.T) {
	root := writeDocs(t, map[string]string{
		"many.md": "manifest one\nmanifest two\nmanifest three\nmanifest four\nno hit here\n",
	})
	re, err := compileDocTerm("manifest", false)
	if err != nil {
		t.Fatalf("compileDocTerm: %v", err)
	}

	count, lines, err := searchDocFile(filepath.Join(root, "many.md"), re)
	if err != nil {
		t.Fatalf("searchDocFile: %v", err)
	}
	if count != 4 {
		t.Errorf("matchCount = %d, want 4", count)
	}
	if len(lines) != docMatchLimit {
		t.Fatalf("len(lines) = %d, want %d", len(lines), docMatchLimit)
	}
	if lines[0].number != 1 || lines[0].text != "manifest one" {
		t.Errorf("lines[0] = %+v, want {1 manifest one}", lines[0])
	}
}

// TestSearchDocs covers the end-to-end aggregation: only files with at
// least one match are returned, in findDocs' sorted order.
func TestSearchDocs(t *testing.T) {
	root := writeDocs(t, map[string]string{
		"a.md": "nothing relevant here",
		"b.md": "the manifest directive lives here",
		"c.md": "MANIFEST in caps, twice: manifest",
	})

	results, err := searchDocs(root, "manifest", false)
	if err != nil {
		t.Fatalf("searchDocs: %v", err)
	}
	if len(results) != 2 {
		t.Fatalf("len(results) = %d, want 2", len(results))
	}
	if results[0].relPath != "b.md" || results[1].relPath != "c.md" {
		t.Errorf("results in wrong order: %+v", results)
	}
	if results[1].matchCount != 1 {
		t.Errorf("c.md matchCount = %d, want 1 (grep -c counts matching lines, not occurrences)", results[1].matchCount)
	}
}

// TestSearchDocsNoMatches confirms an empty result set, not an error, is
// how "no documents match" is signalled — runDocs relies on this to print
// its own message rather than propagating a search error.
func TestSearchDocsNoMatches(t *testing.T) {
	root := writeDocs(t, map[string]string{"a.md": "irrelevant content"})

	results, err := searchDocs(root, "zzznomatchxyz", false)
	if err != nil {
		t.Fatalf("searchDocs: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("results = %v, want none", results)
	}
}
