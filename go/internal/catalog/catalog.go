// Package catalog embeds the build-time command catalog (catalog.json,
// produced by ./gen — see docs/m3-go-skeleton.md, task 3) and exposes
// lookup/search over it. No filesystem scan happens at runtime: a malformed
// manifest fails the build (see gen/main.go), not the CLI's behavior.
package catalog

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/imagewize/wp-ops/go/internal/manifest"
)

//go:generate go run ./gen -out catalog.json

//go:embed catalog.json
var catalogJSON []byte

// Entry is one discoverable command. It carries everything the manifest
// parser found (or, for un-annotated files, the header-scrape fallback
// produced) so every Cobra subcommand — list, search, doctor, --json, the
// dynamic per-command registration — can be built from this alone.
type Entry struct {
	// Category is the top-level directory the command lives under, e.g.
	// "scripts", "trellis", "wp-cli".
	Category string `json:"category"`
	// Key is the repo-relative command key with its file extension
	// stripped, e.g. "scripts/backup/db-backup". This is what bash calls
	// command_key and what wp-ops <key> [args...] dispatches on.
	Key string `json:"key"`
	// Description is the manifest @desc when present, otherwise the
	// header-scrape fallback (see gen's fallbackDescription).
	Description string `json:"description"`
	// ScriptPath is the repo-relative file path including its extension,
	// e.g. "scripts/backup/db-backup.sh".
	ScriptPath string `json:"script_path"`
	// RunsOn is "local" or "server" — bash's is_server_side_command()
	// collapsed to a single field. An explicit "@runs either" still reports
	// "local" here, matching bash's is_server_side_command() (which only
	// special-cases "server").
	RunsOn string `json:"runs_on"`
	// Runs is the raw @runs value ("local", "server", "either", or "" when
	// unset) — kept alongside RunsOn because a few call sites (e.g. the
	// ansible executor's --help) care about "either" specifically.
	Runs     string           `json:"runs,omitempty"`
	Requires []string         `json:"requires,omitempty"`
	Doc      string           `json:"doc,omitempty"`
	Args     []manifest.Param `json:"args,omitempty"`
	Flags    []manifest.Param `json:"flags,omitempty"`
	Examples []string         `json:"examples,omitempty"`
	// ManifestCategory is the @category directive's own value (e.g.
	// "backup", "seo") — a finer-grained tag than Category (the top-level
	// directory). Bash parses it but never reads it back anywhere; kept here
	// for parity and for later phases to use, not currently consumed by any
	// wp-ops subcommand.
	ManifestCategory string `json:"manifest_category,omitempty"`
	// DisplayCategory is the grouping used by every human-facing surface —
	// list.go's category views, the interactive picker, and the per-category
	// Cobra commands (dispatch.go). It equals Category except for the
	// scripts/** subcategories big enough to warrant their own top-level
	// group (Phase F option 4, docs/cli-ux-plan.md): "monitoring", "images",
	// "patterns", "release" (see gen/main.go's promotedScriptCategories).
	// Deliberately kept separate from Category so --json (printJSON) keeps
	// reporting the directory-based "category" field it has always
	// reported: that output is a stable contract for external tooling, and
	// this human-facing split must not leak into it.
	DisplayCategory string `json:"display_category"`
	Annotated       bool   `json:"annotated"`
}

// RequiresString joins Requires the way bash's manifest_get "requires"
// (single-valued, space-separated) would render it — used by --json list to
// match the bash CLI's output field-for-field.
func (e Entry) RequiresString() string {
	return strings.Join(e.Requires, " ")
}

// Catalog is the full set of discovered commands, indexed for lookup.
type Catalog struct {
	Entries           []Entry
	byKey             map[string]Entry
	byCategory        map[string][]Entry
	byDisplayCategory map[string][]Entry
}

// Load parses the embedded catalog.json. It only returns an error if the
// embedded catalog is corrupt, which would mean the build itself is broken
// (go:generate failed silently or the file was hand-edited) — this should
// never happen against a catalog produced by ./gen.
func Load() (*Catalog, error) {
	var entries []Entry
	if err := json.Unmarshal(catalogJSON, &entries); err != nil {
		return nil, fmt.Errorf("catalog: embedded catalog.json is corrupt: %w", err)
	}

	c := &Catalog{
		Entries:           entries,
		byKey:             make(map[string]Entry, len(entries)),
		byCategory:        make(map[string][]Entry),
		byDisplayCategory: make(map[string][]Entry),
	}
	for _, e := range entries {
		c.byKey[e.Key] = e
		c.byCategory[e.Category] = append(c.byCategory[e.Category], e)
		c.byDisplayCategory[e.DisplayCategory] = append(c.byDisplayCategory[e.DisplayCategory], e)
	}
	for cat := range c.byCategory {
		sort.Slice(c.byCategory[cat], func(i, j int) bool {
			return c.byCategory[cat][i].Key < c.byCategory[cat][j].Key
		})
	}
	for cat := range c.byDisplayCategory {
		sort.Slice(c.byDisplayCategory[cat], func(i, j int) bool {
			return c.byDisplayCategory[cat][i].Key < c.byDisplayCategory[cat][j].Key
		})
	}
	return c, nil
}

// Lookup finds a command by its full "category/.../command" key. Ambiguous
// short-form / basename resolution lives in cmd (Cobra command wiring, task
// 7), not here — Catalog only does exact lookups and substring search.
func (c *Catalog) Lookup(key string) (Entry, bool) {
	e, ok := c.byKey[key]
	return e, ok
}

// Categories returns category names in Categories (curated) order, skipping
// any with zero discovered commands — mirrors bash's get_active_categories().
// This is the directory-based grouping consumed by printJSON, kept distinct
// from DisplayCategories so --json stays byte-for-byte identical to bash.
func (c *Catalog) Categories() []string {
	var out []string
	for _, cat := range Categories {
		if len(c.byCategory[cat]) > 0 {
			out = append(out, cat)
		}
	}
	return out
}

// DisplayCategories returns DisplayCategory names in DisplayOrder (curated)
// order, skipping any with zero discovered commands. This is what every
// human-facing surface — list.go's views, the interactive picker, and
// dispatch.go's per-category Cobra commands — groups by; see DisplayCategory
// for why it's kept separate from Categories.
func (c *Catalog) DisplayCategories() []string {
	var out []string
	for _, cat := range DisplayOrder {
		if len(c.byDisplayCategory[cat]) > 0 {
			out = append(out, cat)
		}
	}
	return out
}

// CommandsIn returns a category's commands sorted by key.
func (c *Catalog) CommandsIn(category string) []Entry {
	return c.byCategory[category]
}

// CommandsInDisplay returns a DisplayCategory's commands sorted by key —
// the DisplayCategory counterpart to CommandsIn, used by every human-facing
// grouped view.
func (c *Catalog) CommandsInDisplay(category string) []Entry {
	return c.byDisplayCategory[category]
}

// FindByBasename returns every entry whose key's final path segment matches
// basename — the set candidate list for ambiguous short-form resolution
// (e.g. "wp-ops db-backup" when only "scripts/backup/db-backup" exists).
func (c *Catalog) FindByBasename(basename string) []Entry {
	var out []Entry
	for _, e := range c.Entries {
		segs := strings.Split(e.Key, "/")
		if segs[len(segs)-1] == basename {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key < out[j].Key })
	return out
}

// Search returns every entry whose key or description contains term
// (case-insensitive), sorted by key — backs `wp-ops search <term>`.
func (c *Catalog) Search(term string) []Entry {
	term = strings.ToLower(term)
	var out []Entry
	for _, e := range c.Entries {
		if strings.Contains(strings.ToLower(e.Key), term) || strings.Contains(strings.ToLower(e.Description), term) {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key < out[j].Key })
	return out
}

// Categories lists the category directories to scan, in curated
// (most-used-first) display order — a direct port of bash's CATEGORIES
// array. Shared between the generator (task 3) and the catalog's own
// Categories() method so the two can't drift.
var Categories = []string{
	"scripts",
	"trellis",
	"wp-cli",
	"bedrock",
	"nginx",
	"wordpress-utilities",
	"troubleshooting",
	"mcp-server",
}

// DisplayOrder lists DisplayCategory names in curated (most-used-first)
// order — the DisplayCategory counterpart to Categories, consumed by
// Catalog.DisplayCategories(). "scripts" keeps the subcategories too small
// to warrant their own top-level group (Phase F option 4,
// docs/cli-ux-plan.md: backup, git, misc, sync, woocommerce — 11 commands
// combined); monitoring/images/patterns/release split out right after it
// since each has enough commands (4+) to stand alone. See gen/main.go's
// promotedScriptCategories for the threshold.
var DisplayOrder = []string{
	"scripts",
	"monitoring",
	"images",
	"patterns",
	"release",
	"trellis",
	"wp-cli",
	"bedrock",
	"nginx",
	"wordpress-utilities",
	"troubleshooting",
	"mcp-server",
}

// CategoryDisplayNames mirrors bash's CATEGORY_DISPLAY_NAMES, parallel to
// Categories, plus the DisplayOrder-only entries split out of "scripts".
var CategoryDisplayNames = map[string]string{
	"scripts":             "Scripts",
	"monitoring":          "Monitoring",
	"images":              "Images",
	"patterns":            "Patterns",
	"release":             "Release",
	"trellis":             "Trellis",
	"wp-cli":              "WP-CLI",
	"bedrock":             "Bedrock",
	"nginx":               "Nginx",
	"wordpress-utilities": "WordPress Utilities",
	"troubleshooting":     "Troubleshooting",
	"mcp-server":          "MCP Server",
}

// CategoryBlurbs is a one-line summary per category — shown alongside its
// command count in cmd's compact `list` view and ui's picker category-select
// stage. Phase F, docs/cli-ux-plan.md. Lives here (not in cmd) so both `cmd`
// and `internal/ui` can use the same text without either importing the
// other.
var CategoryBlurbs = map[string]string{
	"scripts":             "Backup, git, sync, and other one-off utility scripts",
	"monitoring":          "Log monitoring, uptime checks, and traffic analysis",
	"images":              "Image resizing, WebP/AVIF conversion, and Openverse downloads",
	"patterns":            "Block pattern screenshots and format conversion",
	"release":             "WordPress plugin/theme release and asset upload automation",
	"trellis":             "Trellis provisioning, backups, and Ansible playbook commands",
	"wp-cli":              "WordPress diagnostics, audits, and WP-CLI-driven tools",
	"bedrock":             "Bedrock/Composer pattern validation",
	"wordpress-utilities": "Reusable snippets copied into WordPress projects",
	"mcp-server":          "MCP server dev/start commands",
}
