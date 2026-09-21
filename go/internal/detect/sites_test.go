package detect

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func writeSites(t *testing.T, root, env, body string) {
	t.Helper()
	dir := filepath.Join(root, "group_vars", env)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "wordpress_sites.yml"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// TestTrellisSites covers the shape Trellis actually writes: sites as
// two-space-indented keys under a top-level wordpress_sites mapping, spread
// across one file per environment, with the same site named in more than
// one of them.
func TestTrellisSites(t *testing.T) {
	root := t.TempDir()
	writeSites(t, root, "production", `wordpress_sites:
  example.com:
    site_hosts:
      - canonical: example.com
        redirects:
          - www.example.com
    local_path: ../site
  shop.example.org:
    site_hosts:
      - canonical: shop.example.org
`)
	writeSites(t, root, "staging", `# Staging overrides
wordpress_sites:
  example.com:
    site_hosts:
      - canonical: staging.example.com
  beta.example.com:   # a trailing comment
    ssl:
      enabled: true

# Anything at column 0 ends the mapping, and nothing after it is a site.
other_top_level_key:
  not-a-site.com:
    x: 1
`)

	want := []string{"beta.example.com", "example.com", "shop.example.org"}
	if got := TrellisSites(root); !reflect.DeepEqual(got, want) {
		t.Errorf("TrellisSites() = %v, want %v", got, want)
	}
}

// TestTrellisSitesNoProject: every failure is silent and empty. A
// completion function has no business erroring, and an empty result simply
// means "no site names to offer".
func TestTrellisSitesNoProject(t *testing.T) {
	if got := TrellisSites(""); got != nil {
		t.Errorf("TrellisSites(\"\") = %v, want nil", got)
	}
	if got := TrellisSites(t.TempDir()); got != nil {
		t.Errorf("TrellisSites(empty dir) = %v, want nil", got)
	}

	root := t.TempDir()
	writeSites(t, root, "production", "# no wordpress_sites key at all\nfoo: bar\n")
	if got := TrellisSites(root); got != nil {
		t.Errorf("TrellisSites(file without the key) = %v, want nil", got)
	}

	// A vaulted file is ciphertext, not YAML — it must yield nothing rather
	// than garbage.
	root = t.TempDir()
	writeSites(t, root, "production", "$ANSIBLE_VAULT;1.1;AES256\n35613966613034...\n")
	if got := TrellisSites(root); got != nil {
		t.Errorf("TrellisSites(vaulted file) = %v, want nil", got)
	}
}
