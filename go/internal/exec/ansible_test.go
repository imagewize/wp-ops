package exec

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/imagewize/wp-ops/go/internal/catalog"
	"github.com/imagewize/wp-ops/go/internal/manifest"
)

func TestFormatHelp_AnnotatedPlaybook(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("trellis/backup/database-backup")
	if !ok {
		t.Fatal("trellis/backup/database-backup not found in catalog")
	}

	help := FormatHelp(e, "/srv/trellis-project")

	for _, want := range []string{
		// Real positionals under the name a user types, not the catalog key
		// with an "[args...]" placeholder — see UsageLine.
		"Usage: wp-ops database-backup <site> <env>",
		e.Description,
		"Arguments:",
		"site",
		"env",
		"production|staging|development",
		"Requires: ansible-playbook",
		"Docs: trellis/backup/README.md",
		"Script: trellis/backup/database-backup.yml",
		"Runs via ansible-playbook against the Trellis project at $TRELLIS_DIR",
		"(currently: /srv/trellis-project)",
	} {
		if !strings.Contains(help, want) {
			t.Errorf("FormatHelp output missing %q:\n%s", want, help)
		}
	}
}

func TestFormatHelp_TrellisDirNotSet(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, _ := c.Lookup("trellis/backup/database-backup")

	help := FormatHelp(e, "")
	if !strings.Contains(help, "(currently: not set)") {
		t.Errorf("FormatHelp with empty trellisDir missing 'not set':\n%s", help)
	}
}

func testEntry() catalog.Entry {
	return catalog.Entry{
		Key:       "trellis/monitoring/security-scan",
		Annotated: true,
		Args: []manifest.Param{
			{Name: "site", Required: true, Description: "Site name as in wordpress_sites.yml"},
			{Name: "env", Required: true, Description: "Target environment"},
		},
		Flags: []manifest.Param{
			{Name: "hours", Description: "How many hours of log history to scan"},
			{Name: "threshold", Description: "Requests-per-IP alert threshold"},
		},
	}
}

func TestBuildPlaybookArgs_Positional(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), []string{"example.com", "production"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"-e", "site=example.com", "-e", "env=production"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestBuildPlaybookArgs_PositionalWithFlags(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), []string{
		"example.com", "production", "--hours", "48", "--threshold=50",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{
		"-e", "site=example.com",
		"-e", "env=production",
		"-e", "hours=48",
		"-e", "threshold=50",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestBuildPlaybookArgs_TrailingRawExtraVar(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), []string{
		"example.com", "production", "-e", "retention_days=10",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{
		"-e", "site=example.com",
		"-e", "env=production",
		"-e", "retention_days=10",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestBuildPlaybookArgs_LegacyRawPassthrough(t *testing.T) {
	raw := []string{"-e", "site=example.com", "-e", "env=production"}
	got, err := BuildPlaybookArgs(testEntry(), raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(got, raw) {
		t.Errorf("got %v, want unchanged %v", got, raw)
	}
}

func TestBuildPlaybookArgs_MissingRequiredArg(t *testing.T) {
	_, err := BuildPlaybookArgs(testEntry(), []string{"example.com"})
	if err == nil {
		t.Fatal("expected an error for a missing required argument, got nil")
	}
	if !strings.Contains(err.Error(), "<env>") {
		t.Errorf("error should name the missing argument <env>: %v", err)
	}
}

func TestBuildPlaybookArgs_MissingFlagValue(t *testing.T) {
	_, err := BuildPlaybookArgs(testEntry(), []string{"example.com", "production", "--hours"})
	if err == nil {
		t.Fatal("expected an error for a flag with no value, got nil")
	}
}

func TestBuildPlaybookArgs_EmptyArgs(t *testing.T) {
	got, err := BuildPlaybookArgs(testEntry(), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("got %v, want empty", got)
	}
}

func TestBuildPlaybookArgs_NoManifestArgsPassesThrough(t *testing.T) {
	e := catalog.Entry{Key: "trellis/backup/database-pull", Annotated: false}
	raw := []string{"example.com", "production"}
	got, err := BuildPlaybookArgs(e, raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(got, raw) {
		t.Errorf("got %v, want unchanged %v", got, raw)
	}
}

func TestStagePlaybookInProjectDir_CopiesEntryAndImportedSibling(t *testing.T) {
	srcDir := t.TempDir()
	trellisDir := t.TempDir()

	writeFile(t, filepath.Join(srcDir, "variable-check.yml"), "# variable-check\n")
	writeFile(t, filepath.Join(srcDir, "files-pull.yml"), strings.Join([]string{
		"---",
		"- import_playbook: variable-check.yml",
		"  vars:",
		"    playbook: files-pull.yml",
		"",
		"- name: Pull uploads",
		"  hosts: web",
		"",
	}, "\n"))

	entryPath, cleanup, err := stagePlaybookInProjectDir(trellisDir, filepath.Join(srcDir, "files-pull.yml"))
	if err != nil {
		t.Fatalf("stagePlaybookInProjectDir: %v", err)
	}
	defer cleanup()

	if filepath.Dir(entryPath) != trellisDir {
		t.Errorf("entry path %s not staged inside trellisDir %s", entryPath, trellisDir)
	}

	entryContent, err := os.ReadFile(entryPath)
	if err != nil {
		t.Fatalf("reading staged entry: %v", err)
	}
	if strings.Contains(string(entryContent), "import_playbook: variable-check.yml") {
		t.Errorf("staged entry still references the unstaged sibling name:\n%s", entryContent)
	}

	matches, _ := filepath.Glob(filepath.Join(trellisDir, stagedPlaybookPrefix+"*variable-check.yml"))
	if len(matches) != 1 {
		t.Fatalf("expected exactly one staged variable-check.yml copy, got %v", matches)
	}

	// The rewritten import_playbook line must point at that exact staged sibling.
	if !strings.Contains(string(entryContent), "import_playbook: "+filepath.Base(matches[0])) {
		t.Errorf("staged entry does not reference staged sibling %s:\n%s", filepath.Base(matches[0]), entryContent)
	}
}

func TestStagePlaybookInProjectDir_CleanupRemovesStagedFiles(t *testing.T) {
	srcDir := t.TempDir()
	trellisDir := t.TempDir()

	writeFile(t, filepath.Join(srcDir, "variable-check.yml"), "# variable-check\n")
	writeFile(t, filepath.Join(srcDir, "files-pull.yml"), "- import_playbook: variable-check.yml\n")

	_, cleanup, err := stagePlaybookInProjectDir(trellisDir, filepath.Join(srcDir, "files-pull.yml"))
	if err != nil {
		t.Fatalf("stagePlaybookInProjectDir: %v", err)
	}

	before, _ := filepath.Glob(filepath.Join(trellisDir, stagedPlaybookPrefix+"*"))
	if len(before) != 2 {
		t.Fatalf("expected 2 staged files before cleanup, got %d: %v", len(before), before)
	}

	cleanup()

	after, _ := filepath.Glob(filepath.Join(trellisDir, stagedPlaybookPrefix+"*"))
	if len(after) != 0 {
		t.Errorf("expected 0 staged files after cleanup, got %d: %v", len(after), after)
	}
}

func TestStagePlaybookInProjectDir_NoImports(t *testing.T) {
	srcDir := t.TempDir()
	trellisDir := t.TempDir()

	writeFile(t, filepath.Join(srcDir, "quick-status.yml"), "- name: check\n  hosts: web\n")

	entryPath, cleanup, err := stagePlaybookInProjectDir(trellisDir, filepath.Join(srcDir, "quick-status.yml"))
	if err != nil {
		t.Fatalf("stagePlaybookInProjectDir: %v", err)
	}
	defer cleanup()

	content, err := os.ReadFile(entryPath)
	if err != nil {
		t.Fatalf("reading staged entry: %v", err)
	}
	if !strings.Contains(string(content), "hosts: web") {
		t.Errorf("staged content unexpectedly altered:\n%s", content)
	}
}

func TestSweepStalePlaybookStaging_RemovesLeftoversFromPriorRun(t *testing.T) {
	trellisDir := t.TempDir()
	stale := filepath.Join(trellisDir, stagedPlaybookPrefix+"abc123-files-pull.yml")
	writeFile(t, stale, "stale content")
	aged := time.Now().Add(-2 * stalePlaybookStagingAge)
	if err := os.Chtimes(stale, aged, aged); err != nil {
		t.Fatalf("aging fixture: %v", err)
	}

	sweepStalePlaybookStaging(trellisDir, time.Now())

	if _, err := os.Stat(stale); !os.IsNotExist(err) {
		t.Errorf("expected stale staged file to be removed, stat err = %v", err)
	}
}

// A second wp-ops run against the same project must not delete the staged
// playbooks of a run that's still going.
func TestSweepStalePlaybookStaging_KeepsFilesFromAnInFlightRun(t *testing.T) {
	trellisDir := t.TempDir()
	fresh := filepath.Join(trellisDir, stagedPlaybookPrefix+"xyz789-database-pull.yml")
	writeFile(t, fresh, "in-flight content")

	sweepStalePlaybookStaging(trellisDir, time.Now())

	if _, err := os.Stat(fresh); err != nil {
		t.Errorf("in-flight staged file was swept away: %v", err)
	}
}

func TestStagePlaybookInProjectDir_SweepLeavesAConcurrentRunAlone(t *testing.T) {
	srcDir := t.TempDir()
	trellisDir := t.TempDir()
	writeFile(t, filepath.Join(srcDir, "files-pull.yml"), "- hosts: web\n")

	first, cleanupFirst, err := stagePlaybookInProjectDir(trellisDir, filepath.Join(srcDir, "files-pull.yml"))
	if err != nil {
		t.Fatalf("first stagePlaybookInProjectDir: %v", err)
	}
	defer cleanupFirst()

	_, cleanupSecond, err := stagePlaybookInProjectDir(trellisDir, filepath.Join(srcDir, "files-pull.yml"))
	if err != nil {
		t.Fatalf("second stagePlaybookInProjectDir: %v", err)
	}
	defer cleanupSecond()

	if _, err := os.Stat(first); err != nil {
		t.Errorf("second run's sweep removed the first run's staged playbook: %v", err)
	}
}

// End-to-end proof of the bug this staging exists for: a playbook living
// outside the Trellis project resolves the project's group_vars once
// RunPlaybook stages it inside. Also covers a relative TRELLIS_DIR, which
// resolveTrellisDir accepts and which the trellisDir-joined staged path
// would otherwise resolve a second time against itself.
func TestRunPlaybook_ResolvesGroupVarsWithRelativeTrellisDir(t *testing.T) {
	if !AnsiblePlaybookAvailable() {
		t.Skip("ansible-playbook not on PATH")
	}

	base := t.TempDir()
	trellisDir := filepath.Join(base, "trellis")
	assetDir := filepath.Join(base, "assets", "trellis", "backup")
	dirs := []string{
		filepath.Join(trellisDir, "group_vars", "all"),
		filepath.Join(trellisDir, "hosts"),
		assetDir,
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", dir, err)
		}
	}

	writeFile(t, filepath.Join(trellisDir, "ansible.cfg"), "[defaults]\ninventory = hosts\n")
	// hosts/ is a directory, as in a real Trellis project (hosts/production,
	// hosts/staging, ...). That detail is the whole point: it means the
	// inventory's own directory has no group_vars/ sibling, so group_vars can
	// only be found via the executed playbook's directory — which is exactly
	// what staging into the project provides.
	writeFile(t, filepath.Join(trellisDir, "hosts", "production"),
		"[web]\nlocalhost ansible_connection=local\n")
	writeFile(t, filepath.Join(trellisDir, "group_vars", "all", "main.yml"),
		"---\nprobe_var: from_group_vars\n")

	writeFile(t, filepath.Join(assetDir, "variable-check.yml"), strings.Join([]string{
		"---",
		"- name: variable check",
		"  hosts: web",
		"  gather_facts: no",
		"  tasks:",
		"    - debug:",
		"        msg: checked",
		"",
	}, "\n"))
	writeFile(t, filepath.Join(assetDir, "files-pull.yml"), strings.Join([]string{
		"---",
		"- import_playbook: variable-check.yml",
		"",
		"- name: probe group_vars",
		"  hosts: web",
		"  gather_facts: no",
		"  tasks:",
		"    - assert:",
		"        that: probe_var == 'from_group_vars'",
		"",
	}, "\n"))

	t.Chdir(base)
	t.Setenv("ANSIBLE_CONFIG", filepath.Join(trellisDir, "ansible.cfg"))

	code, err := RunPlaybook("trellis", filepath.Join(assetDir, "files-pull.yml"), nil)
	if err != nil {
		t.Fatalf("RunPlaybook: %v", err)
	}
	if code != 0 {
		t.Errorf("playbook exited %d, want 0 — group_vars did not resolve against the project", code)
	}

	leftovers, _ := filepath.Glob(filepath.Join(trellisDir, stagedPlaybookPrefix+"*"))
	if len(leftovers) != 0 {
		t.Errorf("staged files left behind after the run: %v", leftovers)
	}
}

func TestWithWPOpsRoot_PrependsAbsoluteRootSoCallerOverridesWin(t *testing.T) {
	root := t.TempDir()
	got := WithWPOpsRoot([]string{"-e", "site=example.com"}, root)

	want := []string{"-e", "wp_ops_root=" + root, "-e", "site=example.com"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("WithWPOpsRoot = %v, want %v", got, want)
	}
}

func TestWithWPOpsRoot_MakesRelativeRootAbsolute(t *testing.T) {
	root := t.TempDir()
	t.Chdir(filepath.Dir(root))

	got := WithWPOpsRoot(nil, filepath.Base(root))
	if len(got) != 2 || !filepath.IsAbs(strings.TrimPrefix(got[1], "wp_ops_root=")) {
		t.Errorf("WithWPOpsRoot did not absolutize a relative root: %v", got)
	}
}

func TestBuildPlaybookArgs_RealCatalogEntry(t *testing.T) {
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("trellis/backup/database-backup")
	if !ok {
		t.Fatal("trellis/backup/database-backup not found in catalog")
	}

	got, err := BuildPlaybookArgs(e, []string{"example.com", "production"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"-e", "site=example.com", "-e", "env=production"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}
