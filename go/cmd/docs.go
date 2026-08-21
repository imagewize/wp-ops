// Port of the bash CLI's "Documentation Search" section (wp-ops:1610-1736)
// and its dispatch (wp-ops:2196-2211) — M4 task 5,
// docs/m4-go-cli-completion.md. Unrelated to the per-command @doc manifest
// directive (catalog.Entry.Doc, already surfaced by executors' --help and
// --json): this is a full-text search over every *.md file in the repo,
// independent of any command's manifest.
package cmd

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/spf13/cobra"
)

// docMatchLimit caps how many matching lines are shown per document before
// the rest are summarised as "… N more" — a long guide can otherwise bury
// every other matching document under one file's hits (wp-ops:1621).
const docMatchLimit = 3

// docLineWidth truncates a shown matching line so a long paragraph stays on
// one row (wp-ops:1624).
const docLineWidth = 96

var (
	docsPathsOnly bool
	docsWholeWord bool
)

var docsCmd = &cobra.Command{
	Use:   "docs [term]",
	Short: "Search the guides (no term lists them)",
	Args:  cobra.MaximumNArgs(1),
	RunE: func(cc *cobra.Command, args []string) error {
		term := ""
		if len(args) > 0 {
			term = args[0]
		}
		os.Exit(runDocs(term, docsPathsOnly, docsWholeWord))
		return nil
	},
}

func init() {
	docsCmd.Flags().BoolVarP(&docsPathsOnly, "files", "l", false, "Print only matching file paths")
	docsCmd.Flags().BoolVar(&docsPathsOnly, "paths", false, "Alias for --files")
	docsCmd.Flags().BoolVarP(&docsWholeWord, "word", "w", false, "Match whole words only")
	rootCmd.AddCommand(docsCmd)
}

// docLine is one matching line, already collapsed/truncated for display.
type docLine struct {
	number int
	text   string
}

// docResult is one document with at least one match.
type docResult struct {
	relPath    string
	matchCount int
	lines      []docLine
}

func runDocs(term string, pathsOnly, wholeWord bool) int {
	root, err := repoRoot()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	if term == "" {
		printDocsList(root)
		return 0
	}

	results, err := searchDocs(root, term, wholeWord)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	if len(results) == 0 {
		fmt.Printf("No documents match '%s'.\n\n", term)
		fmt.Printf("Try %s search %s to look for a command instead.\n", cmdName(), term)
		return 1
	}

	if pathsOnly {
		for _, r := range results {
			fmt.Println(r.relPath)
		}
		return 0
	}

	noun := "documents"
	if len(results) == 1 {
		noun = "document"
	}
	fmt.Printf("%d %s matching '%s':\n\n", len(results), noun, term)

	for _, r := range results {
		matchNoun := "matches"
		if r.matchCount == 1 {
			matchNoun = "match"
		}
		fmt.Printf("  %s (%d %s)\n", r.relPath, r.matchCount, matchNoun)
		for _, l := range r.lines {
			fmt.Printf("    %5d  %s\n", l.number, l.text)
		}
		if r.matchCount > docMatchLimit {
			fmt.Printf("    %5s  … %d more\n", "", r.matchCount-docMatchLimit)
		}
		fmt.Println()
	}

	if wholeWord {
		fmt.Printf("Paths only (for piping to an editor): %s docs %s -l\n\n", cmdName(), term)
	} else {
		fmt.Printf("Whole words only: %s docs %s -w   ·   paths only: %s docs %s -l\n\n", cmdName(), term, cmdName(), term)
	}

	return 0
}

func printDocsList(root string) {
	docs, err := findDocs(root)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return
	}

	fmt.Printf("Documentation (%d files)\n\n", len(docs))
	for _, d := range docs {
		fmt.Printf("  %s\n", relDocPath(root, d))
	}
	fmt.Println()
	fmt.Printf("Search inside them with: %s docs <term>\n", cmdName())
	fmt.Println()
}

// hasDocMatches backs search.go's "the documentation mentions it though"
// cross-reference (wp-ops:1582-1586) when a command search comes up empty.
func hasDocMatches(term string) bool {
	root, err := repoRoot()
	if err != nil {
		return false
	}
	results, err := searchDocs(root, term, false)
	return err == nil && len(results) > 0
}

// searchDocs walks every *.md file under root and returns one docResult per
// file with at least one match, in findDocs' (sorted, repo-relative-path)
// order.
func searchDocs(root, term string, wholeWord bool) ([]docResult, error) {
	re, err := compileDocTerm(term, wholeWord)
	if err != nil {
		return nil, err
	}

	docs, err := findDocs(root)
	if err != nil {
		return nil, err
	}

	var results []docResult
	for _, doc := range docs {
		count, lines, err := searchDocFile(doc, re)
		if err != nil {
			// Matches bash's `2>/dev/null` on the grep calls: an unreadable
			// file is skipped, not a hard failure.
			continue
		}
		if count > 0 {
			results = append(results, docResult{
				relPath:    relDocPath(root, doc),
				matchCount: count,
				lines:      lines,
			})
		}
	}
	return results, nil
}

// findDocs mirrors find_docs (wp-ops:1630-1634): every *.md file in the
// repo, excluding .git/node_modules/vendor, sorted.
func findDocs(root string) ([]string, error) {
	var docs []string
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case ".git", "node_modules", "vendor":
				return fs.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(d.Name(), ".md") {
			docs = append(docs, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(docs)
	return docs, nil
}

func relDocPath(root, path string) string {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return path
	}
	return rel
}

// compileDocTerm builds the case-insensitive matcher grep -i (or grep -wi
// for --word) implements, per DOC_GREP_OPTS (wp-ops:1628).
func compileDocTerm(term string, wholeWord bool) (*regexp.Regexp, error) {
	pattern := regexp.QuoteMeta(term)
	if wholeWord {
		pattern = `\b` + pattern + `\b`
	}
	return regexp.Compile("(?i)" + pattern)
}

// collapseDocWhitespace mirrors print_docs_results' sed pipeline
// (wp-ops:1719-1720): markdown indentation and list markers carry no
// meaning once a line is shown out of context.
var docWhitespaceRun = regexp.MustCompile(`[ \t]{2,}`)

func collapseDocWhitespace(s string) string {
	s = strings.TrimLeft(s, " \t")
	s = docWhitespaceRun.ReplaceAllString(s, " ")

	runes := []rune(s)
	if len(runes) > docLineWidth {
		return string(runes[:docLineWidth-1]) + "…"
	}
	return s
}

// searchDocFile scans one file line by line, matching grep -c (matchCount,
// the number of matching lines) and grep -n | head -N (the first
// docMatchLimit matching lines, collapsed/truncated for display).
func searchDocFile(path string, re *regexp.Regexp) (matchCount int, lines []docLine, err error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, nil, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	lineNum := 0
	for scanner.Scan() {
		lineNum++
		text := scanner.Text()
		if !re.MatchString(text) {
			continue
		}
		matchCount++
		if len(lines) < docMatchLimit {
			lines = append(lines, docLine{number: lineNum, text: collapseDocWhitespace(text)})
		}
	}
	if err := scanner.Err(); err != nil {
		return 0, nil, err
	}
	return matchCount, lines, nil
}
