package exec

import (
	"bytes"
	"errors"
	"os"
	osexec "os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/imagewize/wp-ops/go/internal/catalog"
)

func writeSnippet(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "footer.php")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	return path
}

func lookupSnippetEntry(t *testing.T) catalog.Entry {
	t.Helper()
	c, err := catalog.Load()
	if err != nil {
		t.Fatalf("catalog.Load: %v", err)
	}
	e, ok := c.Lookup("wordpress-utilities/snippets/post-expiry-noindex")
	if !ok {
		t.Fatal("wordpress-utilities/snippets/post-expiry-noindex not found in catalog")
	}
	return e
}

func TestPrintSnippet_TTY(t *testing.T) {
	path := writeSnippet(t, "<?php echo 'hi'; ?>")
	var buf bytes.Buffer
	if err := PrintSnippet(&buf, path, true); err != nil {
		t.Fatalf("PrintSnippet: %v", err)
	}
	out := buf.String()
	if !strings.Contains(out, path) {
		t.Errorf("output missing file path header:\n%s", out)
	}
	if !strings.Contains(out, "<?php echo 'hi'; ?>") {
		t.Errorf("output missing file content:\n%s", out)
	}
	if !strings.Contains(out, "Reference snippet") {
		t.Errorf("output missing reference-snippet notice:\n%s", out)
	}
}

func TestPrintSnippet_Piped(t *testing.T) {
	body := "<?php echo 'hi'; ?>"
	path := writeSnippet(t, body)
	var buf bytes.Buffer
	if err := PrintSnippet(&buf, path, false); err != nil {
		t.Fatalf("PrintSnippet: %v", err)
	}
	if buf.String() != body {
		t.Errorf("piped output = %q, want raw content %q", buf.String(), body)
	}
}

func TestRunSnippet_Path(t *testing.T) {
	path := writeSnippet(t, "content")
	e := catalog.Entry{Key: "wordpress-utilities/snippets/footer"}
	var out, errOut bytes.Buffer

	code := RunSnippet(&out, &errOut, e, path, []string{"--path"}, false)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
	if strings.TrimSpace(out.String()) != path {
		t.Errorf("output = %q, want %q", out.String(), path)
	}
}

func TestRunSnippet_DefaultPrintsContent(t *testing.T) {
	body := "raw content"
	path := writeSnippet(t, body)
	e := catalog.Entry{Key: "wordpress-utilities/snippets/footer"}
	var out, errOut bytes.Buffer

	code := RunSnippet(&out, &errOut, e, path, nil, false)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
	if out.String() != body {
		t.Errorf("output = %q, want %q", out.String(), body)
	}
}

func TestClipboardCmd_FallbackChain(t *testing.T) {
	tests := []struct {
		name      string
		available map[string]bool
		want      []string
	}{
		{"pbcopy preferred", map[string]bool{"pbcopy": true, "xclip": true}, []string{"pbcopy"}},
		{"xclip when no pbcopy", map[string]bool{"xclip": true}, []string{"xclip", "-selection", "clipboard"}},
		{"xsel when no pbcopy or xclip", map[string]bool{"xsel": true}, []string{"xsel", "--clipboard", "--input"}},
		{"clip.exe last resort", map[string]bool{"clip.exe": true}, []string{"clip.exe"}},
		{"none available", map[string]bool{}, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			lookPath := func(name string) (string, error) {
				if tt.available[name] {
					return "/usr/bin/" + name, nil
				}
				return "", errors.New("not found")
			}
			got := clipboardCmd(lookPath)
			if !equalSlices(got, tt.want) {
				t.Errorf("clipboardCmd = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestRunSnippet_CopyNoClipboardTool(t *testing.T) {
	// clipboardCmd relies on exec.LookPath directly inside CopySnippet, so on
	// a machine with none of the four tools on PATH this exercises the real
	// fallback message; skip if the test host happens to have one.
	if clipboardCmd(osexec.LookPath) != nil {
		t.Skip("a clipboard tool is present on this machine; can't exercise the no-tool path")
	}

	path := writeSnippet(t, "content")
	e := catalog.Entry{Key: "wordpress-utilities/snippets/footer"}
	var out, errOut bytes.Buffer

	code := RunSnippet(&out, &errOut, e, path, []string{"--copy"}, false)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(errOut.String(), "--path instead") {
		t.Errorf("stderr missing --path fallback guidance:\n%s", errOut.String())
	}
}

func TestFormatSnippetHelp_Annotated(t *testing.T) {
	e := lookupSnippetEntry(t)
	help := FormatSnippetHelp(e)

	for _, want := range []string{
		e.Description,
		"reference snippet meant to be copied",
		"Usage: wp-ops wordpress-utilities/snippets/post-expiry-noindex            Print the snippet",
		"--copy      Copy it to the clipboard",
		"--path      Print only the file path",
	} {
		if !strings.Contains(help, want) {
			t.Errorf("FormatSnippetHelp output missing %q:\n%s", want, help)
		}
	}
}

func equalSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
