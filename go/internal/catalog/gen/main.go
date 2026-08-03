// Command gen walks the repo the same way bash's discover_commands() does
// and emits catalog.json: every discoverable command, manifest-parsed where
// annotated, header-scrape-scraped as a fallback where not (currently just
// mcp-server/*, the two commands Phase A never annotated — see
// docs/m3-go-skeleton.md, task 3, decision #2).
//
// Invoked via `go generate ./...` against the catalog package (see the
// //go:generate directive in catalog.go). Fails loudly (build breaks) on a
// malformed manifest rather than degrading the catalog — see the parent
// plan's "Build-time catalog" note in docs/cli-ux-plan.md.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

// excludedFilenames mirrors discover_commands()'s
// `! -name "wp-ops" ! -name "variable-check.yml" ! -name "transient-debug-browser.php"`.
var excludedFilenames = map[string]bool{
	"wp-ops":                      true,
	"variable-check.yml":          true,
	"transient-debug-browser.php": true,
}

// excludedDirs are directories the walk never descends into: build
// artifacts and dependency trees (gitignored, so absent in a fresh CI
// checkout) that would otherwise get scanned for the mcp-server category's
// .js extension the moment a contributor runs `npm install`/`npm run build`
// locally — e.g. mcp-server/node_modules, mcp-server/dist.
var excludedDirs = map[string]bool{
	"node_modules": true,
	"dist":         true,
	".git":         true,
}

// extensionsFor mirrors discover_commands()'s per-category name_matchers.
func extensionsFor(category string) map[string]bool {
	exts := map[string]bool{".sh": true, ".js": true}
	switch category {
	case "trellis":
		exts[".yml"] = true
	case "scripts":
		exts[".py"] = true
	case "wp-cli", "bedrock":
		exts[".php"] = true
	case "wordpress-utilities":
		exts[".php"] = true
		exts[".css"] = true
	}
	return exts
}

// serverSideFallback mirrors bash's hardcoded SERVER_SIDE_COMMANDS — only
// consulted for a command with no @runs at all (today, that's just
// mcp-server/dev and mcp-server/start, neither of which is in this list, so
// it never fires; ported for exactness, matching is_server_side_command()'s
// own fallback order).
// promotedScriptCategories are the @category values under scripts/** with
// enough commands (4+) to warrant their own top-level DisplayCategory
// (Phase F option 4, docs/cli-ux-plan.md) rather than staying folded into
// "scripts" alongside backup/git/misc/sync/woocommerce (2-3 commands each).
var promotedScriptCategories = map[string]bool{
	"monitoring": true,
	"images":     true,
	"patterns":   true,
	"release":    true,
}

// displayCategoryFor computes catalog.Entry.DisplayCategory: the manifest's
// own @category value for a promoted scripts/** subcategory, otherwise the
// directory category unchanged. See DisplayCategory's doc comment for why
// this is kept separate from Category.
func displayCategoryFor(category, manifestCategory string) string {
	if category == "scripts" && promotedScriptCategories[manifestCategory] {
		return manifestCategory
	}
	return category
}

var serverSideFallback = map[string]bool{
	"scripts/monitoring/traffic-monitor":  true,
	"scripts/monitoring/security-monitor": true,
	"scripts/monitoring/ai-bot-monitor":   true,
	"scripts/monitoring/error-monitor":    true,
	"scripts/monitoring/monitor":          true,
	"scripts/backup/site-backup":          true,
}

func main() {
	out := flag.String("out", "catalog.json", "output path, relative to the catalog package directory")
	flag.Parse()

	repoRoot, err := findRepoRoot()
	if err != nil {
		fatalf("%v", err)
	}

	var entries []catalog.Entry
	var lintErrors []string

	for _, category := range catalog.Categories {
		categoryDir := filepath.Join(repoRoot, category)
		if info, err := os.Stat(categoryDir); err != nil || !info.IsDir() {
			continue
		}

		exts := extensionsFor(category)
		var files []string
		err := filepath.WalkDir(categoryDir, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				if excludedDirs[d.Name()] {
					return filepath.SkipDir
				}
				return nil
			}
			if !exts[filepath.Ext(path)] {
				return nil
			}
			if excludedFilenames[filepath.Base(path)] {
				return nil
			}
			files = append(files, path)
			return nil
		})
		if err != nil {
			fatalf("walking %s: %v", categoryDir, err)
		}
		sort.Strings(files)

		for _, path := range files {
			rel, err := filepath.Rel(repoRoot, path)
			if err != nil {
				fatalf("%v", err)
			}
			rel = filepath.ToSlash(rel)
			key := strings.TrimSuffix(rel, filepath.Ext(rel))

			cmd, err := manifest.Parse(key, path)
			if err != nil {
				fatalf("parsing manifest for %s: %v", rel, err)
			}
			lintErrors = append(lintErrors, manifest.Lint(cmd, repoRoot)...)

			entry := catalog.Entry{
				Category:         category,
				DisplayCategory:  displayCategoryFor(category, cmd.Category),
				Key:              key,
				ScriptPath:       rel,
				Runs:             cmd.Runs,
				Requires:         cmd.Requires,
				Doc:              cmd.Doc,
				Args:             cmd.Args,
				Flags:            cmd.Flags,
				Examples:         cmd.Examples,
				ManifestCategory: cmd.Category,
				Annotated:        cmd.Annotated,
			}

			if cmd.Desc != "" {
				entry.Description = cmd.Desc
			} else {
				entry.Description = fallbackDescription(path, key)
			}

			entry.RunsOn = runsOnFor(cmd.Runs, key)

			entries = append(entries, entry)
		}
	}

	// A malformed manifest fails the build outright — see the package doc.
	// A missing @desc is deliberately *not* fatal here: every currently
	// annotated command already has one (manifest lint / CI catches
	// regressions), but a script can validly have zero manifest directives
	// at all and fall back to the header scrape, and Lint() flags that
	// exact case as "missing @desc" too. Only real malformations
	// (bad @runs, malformed @arg/@flag, a dangling @doc) should break the
	// build.
	var hardErrors []string
	for _, e := range lintErrors {
		if strings.Contains(e, "missing @desc") {
			continue
		}
		hardErrors = append(hardErrors, e)
	}
	if len(hardErrors) > 0 {
		for _, e := range hardErrors {
			fmt.Fprintln(os.Stderr, "catalog: "+e)
		}
		fatalf("%d manifest error(s) found — fix before regenerating the catalog", len(hardErrors))
	}

	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		fatalf("marshaling catalog: %v", err)
	}
	data = append(data, '\n')

	outPath := *out
	if !filepath.IsAbs(outPath) {
		// go:generate runs with cwd set to the directory holding the
		// //go:generate comment (the catalog package), not this gen/
		// subdirectory — resolve relative to that when invoked that way,
		// falling back to cwd otherwise.
		if cwd, err := os.Getwd(); err == nil {
			outPath = filepath.Join(cwd, outPath)
		}
	}
	if err := os.WriteFile(outPath, data, 0o644); err != nil {
		fatalf("writing %s: %v", outPath, err)
	}

	fmt.Fprintf(os.Stderr, "catalog: wrote %d commands to %s\n", len(entries), outPath)
}

// runsOnFor ports is_server_side_command() (wp-ops:126): an explicit @runs is
// authoritative — "server" means server, any *other* non-empty value means
// local — and only a command with no @runs at all falls through to the
// hardcoded SERVER_SIDE_COMMANDS list.
func runsOnFor(runs, key string) string {
	switch {
	case runs == "server":
		return "server"
	case runs != "":
		return "local"
	case serverSideFallback[key]:
		return "server"
	default:
		return "local"
	}
}

// fallbackDescription ports discover_commands()'s per-extension header
// scrape + clean_description() for un-annotated files.
func fallbackDescription(path, key string) string {
	var raw string
	switch filepath.Ext(path) {
	case ".js", ".php", ".css":
		raw = scrapeFirst(path, 20, docblockLineRe)
		if raw == "" {
			raw = scrapeFirst(path, 20, lineCommentRe)
		}
	case ".py":
		raw = scrapeFirst(path, 5, pyDocstringRe)
	default:
		raw = scrapeFirst(path, 20, hashCommentRe)
	}

	desc := cleanDescription(raw, filepath.Base(path))
	if desc == "" {
		desc = filepath.Base(key)
	}
	return desc
}

var (
	docblockLineRe = regexp.MustCompile(`^\s*\*\s+(\S.*)$`)
	lineCommentRe  = regexp.MustCompile(`^\s*//\s*(\S.*)$`)
	pyDocstringRe  = regexp.MustCompile(`^"""([^"]+)"""$`)
	hashCommentRe  = regexp.MustCompile(`^#\s(.*)$`)

	sentenceEndRe   = regexp.MustCompile(`\. .*$`)
	leadingSepRe    = regexp.MustCompile(`^\s*[-—:]\s*`)
	trailingPunctRe = regexp.MustCompile(`[\s,;:]*$`)
)

// scrapeFirst returns the capture group of the first line (within the first
// maxLines) matching re, or "" if none match.
func scrapeFirst(path string, maxLines int, re *regexp.Regexp) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	data := make([]byte, 0, 4096)
	buf := make([]byte, 4096)
	for {
		n, _ := f.Read(buf)
		if n == 0 {
			break
		}
		data = append(data, buf[:n]...)
		if len(data) > 64*1024 {
			break
		}
	}

	lines := strings.SplitN(string(data), "\n", maxLines+1)
	for i, line := range lines {
		if i >= maxLines {
			break
		}
		if m := re.FindStringSubmatch(line); m != nil {
			return m[1]
		}
	}
	return ""
}

// cleanDescription ports clean_description(): trim, drop a leading
// self-referential filename, drop a leading separator, keep only the first
// sentence, trim trailing punctuation, cap at 72 runes.
func cleanDescription(description, filename string) string {
	description = strings.TrimSpace(description)
	description = strings.TrimPrefix(description, filename)
	description = leadingSepRe.ReplaceAllString(description, "")

	if strings.Contains(description, ". ") {
		description = sentenceEndRe.ReplaceAllString(description, ".")
	}

	description = trailingPunctRe.ReplaceAllString(description, "")

	if r := []rune(description); len(r) > 72 {
		description = string(r[:71]) + "…"
	}

	return description
}

// findRepoRoot locates the repo root from this source file's own path
// (go/internal/catalog/gen/main.go is always four directories below repo
// root), independent of the working directory `go generate` happens to run
// with.
func findRepoRoot() (string, error) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		return "", fmt.Errorf("could not determine gen's own source path")
	}
	root := filepath.Clean(filepath.Join(filepath.Dir(thisFile), "..", "..", "..", ".."))
	if _, err := os.Stat(filepath.Join(root, "wp-ops")); err != nil {
		return "", fmt.Errorf("resolved repo root %s doesn't contain wp-ops: %w", root, err)
	}
	return root, nil
}

func fatalf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "catalog gen: "+format+"\n", args...)
	os.Exit(1)
}
