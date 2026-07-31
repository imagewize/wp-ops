package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

var versionRe = regexp.MustCompile(`^## \[(\d+\.\d+\.\d+)\]`)

// getVersion ports get_version() (wp-ops:186): the toolkit's version lives
// in CHANGELOG.md (Keep a Changelog format) rather than a second
// hand-maintained copy.
func getVersion() string {
	root, err := repoRoot()
	if err != nil {
		return "unknown"
	}

	f, err := os.Open(filepath.Join(root, "CHANGELOG.md"))
	if err != nil {
		return "unknown"
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if m := versionRe.FindStringSubmatch(scanner.Text()); m != nil {
			return m[1]
		}
	}
	return "unknown"
}

func printVersion() {
	c := mustCatalog()
	root, err := repoRoot()
	if err != nil {
		root = "unknown location"
	}
	fmt.Printf("wp-ops %s\n", getVersion())
	fmt.Printf("%d commands from %s\n", len(c.Entries), root)
}
