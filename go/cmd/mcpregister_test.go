package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const runShPath = "/fake/wp-ops/mcp-server/run.sh"

func TestCheckClaudeConfig(t *testing.T) {
	tmp := t.TempDir()

	t.Run("file missing", func(t *testing.T) {
		r := checkClaudeConfig(filepath.Join(tmp, "does-not-exist.json"), runShPath)
		if r.status != regNotFound {
			t.Fatalf("status = %v, want regNotFound", r.status)
		}
		if !strings.Contains(r.snippet, runShPath) {
			t.Errorf("snippet %q missing run.sh path", r.snippet)
		}
	})

	t.Run("already registered", func(t *testing.T) {
		path := filepath.Join(tmp, "registered.json")
		content := `{"mcpServers":{"wp-ops":{"command":"node","args":["x"]}},"projects":{}}`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkClaudeConfig(path, runShPath)
		if r.status != regAlreadyRegistered {
			t.Fatalf("status = %v, want regAlreadyRegistered", r.status)
		}
	})

	t.Run("needs registration, other servers present", func(t *testing.T) {
		path := filepath.Join(tmp, "other.json")
		content := `{"mcpServers":{"some-other-tool":{"command":"x"}}}`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkClaudeConfig(path, runShPath)
		if r.status != regNeedsRegistration {
			t.Fatalf("status = %v, want regNeedsRegistration", r.status)
		}
		if !strings.Contains(r.snippet, `"wp-ops"`) || !strings.Contains(r.snippet, runShPath) {
			t.Errorf("snippet missing expected content: %q", r.snippet)
		}
	})

	t.Run("malformed json", func(t *testing.T) {
		path := filepath.Join(tmp, "broken.json")
		if err := os.WriteFile(path, []byte("{not json"), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkClaudeConfig(path, runShPath)
		if r.status != regParseError {
			t.Fatalf("status = %v, want regParseError", r.status)
		}
		if r.parseErr == nil {
			t.Error("parseErr = nil, want non-nil")
		}
	})
}

func TestCheckVibeConfig(t *testing.T) {
	tmp := t.TempDir()

	t.Run("file missing", func(t *testing.T) {
		r := checkVibeConfig(filepath.Join(tmp, "does-not-exist.toml"), runShPath)
		if r.status != regNotFound {
			t.Fatalf("status = %v, want regNotFound", r.status)
		}
	})

	t.Run("already registered among other servers", func(t *testing.T) {
		path := filepath.Join(tmp, "registered.toml")
		content := `
[[mcp_servers]]
name = "fetch_server"
transport = "stdio"
command = "uvx"
args = ["mcp-server-fetch"]

[[mcp_servers]]
name = "wp_ops"
transport = "stdio"
command = "/some/path/run.sh"
args = []
`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkVibeConfig(path, runShPath)
		if r.status != regAlreadyRegistered {
			t.Fatalf("status = %v, want regAlreadyRegistered", r.status)
		}
	})

	t.Run("needs registration", func(t *testing.T) {
		path := filepath.Join(tmp, "other.toml")
		content := `
[[mcp_servers]]
name = "fetch_server"
transport = "stdio"
command = "uvx"
args = ["mcp-server-fetch"]
`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkVibeConfig(path, runShPath)
		if r.status != regNeedsRegistration {
			t.Fatalf("status = %v, want regNeedsRegistration", r.status)
		}
		if !strings.Contains(r.snippet, `name = "wp_ops"`) || !strings.Contains(r.snippet, runShPath) {
			t.Errorf("snippet missing expected content: %q", r.snippet)
		}
	})

	t.Run("malformed toml", func(t *testing.T) {
		path := filepath.Join(tmp, "broken.toml")
		if err := os.WriteFile(path, []byte("[[mcp_servers]\nname = "), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkVibeConfig(path, runShPath)
		if r.status != regParseError {
			t.Fatalf("status = %v, want regParseError", r.status)
		}
	})
}

func TestCheckCodexConfig(t *testing.T) {
	tmp := t.TempDir()

	t.Run("file missing", func(t *testing.T) {
		r := checkCodexConfig(filepath.Join(tmp, "does-not-exist.toml"), runShPath)
		if r.status != regNotFound {
			t.Fatalf("status = %v, want regNotFound", r.status)
		}
	})

	t.Run("already registered among other servers", func(t *testing.T) {
		path := filepath.Join(tmp, "registered.toml")
		content := `
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]

[mcp_servers.wp_ops]
command = "/some/path/run.sh"
args = []
`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkCodexConfig(path, runShPath)
		if r.status != regAlreadyRegistered {
			t.Fatalf("status = %v, want regAlreadyRegistered", r.status)
		}
	})

	t.Run("needs registration", func(t *testing.T) {
		path := filepath.Join(tmp, "other.toml")
		content := `
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]
`
		if err := os.WriteFile(path, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		r := checkCodexConfig(path, runShPath)
		if r.status != regNeedsRegistration {
			t.Fatalf("status = %v, want regNeedsRegistration", r.status)
		}
		if !strings.Contains(r.snippet, `[mcp_servers.wp_ops]`) || !strings.Contains(r.snippet, runShPath) {
			t.Errorf("snippet missing expected content: %q", r.snippet)
		}
	})
}

// TestPrintReportDoesNotPanic is a light smoke test over the four status
// branches — printReport's formatting isn't asserted character-for-character
// elsewhere, so this just guards against a panic (e.g. a nil parseErr
// dereference) regressing silently.
func TestPrintReportDoesNotPanic(t *testing.T) {
	reports := []regReport{
		{client: "X", path: "/x", status: regNotFound, snippet: "snippet"},
		{client: "X", path: "/x", status: regAlreadyRegistered},
		{client: "X", path: "/x", status: regNeedsRegistration, snippet: "snippet"},
		{client: "X", path: "/x", status: regParseError, parseErr: errors.New("boom")},
	}
	for _, r := range reports {
		captureStdout(t, func() { printReport(r) })
	}
}
