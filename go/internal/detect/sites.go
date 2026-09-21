package detect

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"sort"
)

var (
	// The wordpress_sites mapping opens at column 0 — it is a top-level key
	// in group_vars/<env>/wordpress_sites.yml.
	sitesKeyRe = regexp.MustCompile(`^wordpress_sites:`)
	// A site is a two-space-indented key directly under it. Trellis writes
	// these as bare domains, so no quoting or flow syntax to unpick.
	siteNameRe = regexp.MustCompile(`^  ([A-Za-z0-9][A-Za-z0-9._-]*):\s*(#.*)?$`)
	// Any other column-0 content ends the mapping.
	topLevelRe = regexp.MustCompile(`^[^\s#]`)
)

// TrellisSites returns the site names declared across a Trellis project's
// group_vars/*/wordpress_sites.yml files, sorted and deduplicated. It is
// used for shell completion of the `site` / `site-name` arguments, which is
// why it reads the files with a line scanner rather than a YAML parser and
// why every error is swallowed into an empty result: a completion function
// has no business failing, printing, or pulling a YAML dependency into the
// binary for four lines of well-known structure.
//
// This is a stopgap. M5's shared site registry (docs/cli-ux-plan.md) is
// where site names are meant to come from once it exists; until then the
// Trellis project in front of you is the only place the CLI can learn them.
func TrellisSites(trellisDir string) []string {
	if trellisDir == "" {
		return nil
	}

	matches, err := filepath.Glob(filepath.Join(trellisDir, "group_vars", "*", "wordpress_sites.yml"))
	if err != nil {
		return nil
	}

	seen := map[string]bool{}
	for _, path := range matches {
		for _, name := range sitesInFile(path) {
			seen[name] = true
		}
	}
	if len(seen) == 0 {
		return nil
	}

	names := make([]string, 0, len(seen))
	for name := range seen {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// sitesInFile pulls the keys of the wordpress_sites mapping out of one
// group_vars file. Vaulted files (group_vars/*/vault.yml is where secrets
// live, not this) and anything else unparseable simply yield nothing.
func sitesInFile(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()

	var names []string
	inSites := false
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if !inSites {
			inSites = sitesKeyRe.MatchString(line)
			continue
		}
		if m := siteNameRe.FindStringSubmatch(line); m != nil {
			names = append(names, m[1])
			continue
		}
		if topLevelRe.MatchString(line) {
			break
		}
	}
	return names
}
