// mcp-register: detect + print. Checks whether the MCP client configs wp-ops
// knows how to register with (Claude Code, Mistral Vibe, OpenAI Codex CLI)
// already have a wp-ops stdio entry, and for each one that's missing it,
// prints the exact block to add — using the real, resolved path to
// mcp-server/run.sh (via repoRoot(), the same dev-checkout-or-extracted-
// assets resolution every other command already uses).
//
// Deliberately read-only: it never writes to a config file it doesn't own.
// Claude's ~/.claude.json in particular can carry a lot of unrelated state
// (per-project settings, etc.) that a naive rewrite could clobber; printing
// the snippet and letting the user paste it is the safe default. Auto-write
// is a reasonable follow-up once this is something run often enough (a
// second machine, a teammate) to justify that risk — see the discussion in
// mcp-server/README.md's registration sections.
package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/spf13/cobra"
)

var mcpRegisterCmd = &cobra.Command{
	Use:   "mcp-register",
	Short: "Show MCP registration snippets for Claude Code, Mistral Vibe, and Codex CLI",
	Long: `mcp-register checks whether ~/.claude.json, ~/.vibe/config.toml, and
~/.codex/config.toml already have a wp-ops MCP entry, and for each one
missing it, prints the exact stdio block to add — using the real, resolved
path to mcp-server/run.sh.

Read-only: never writes to a config file it doesn't own.`,
	RunE: func(cc *cobra.Command, args []string) error {
		os.Exit(runMCPRegister())
		return nil
	},
}

func init() {
	rootCmd.AddCommand(mcpRegisterCmd)
}

type regStatus int

const (
	regNotFound regStatus = iota
	regAlreadyRegistered
	regNeedsRegistration
	regParseError
)

type regReport struct {
	client   string
	path     string
	status   regStatus
	snippet  string // set for regNeedsRegistration and regNotFound
	parseErr error  // set for regParseError
}

func runMCPRegister() int {
	root, err := repoRoot()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mcp-register: %v\n", err)
		return 1
	}
	runSh := filepath.Join(root, "mcp-server", "run.sh")
	if info, statErr := os.Stat(runSh); statErr != nil || info.IsDir() {
		fmt.Fprintf(os.Stderr, "mcp-register: expected %s to exist — is your wp-ops checkout/extraction intact?\n", runSh)
		return 1
	}

	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mcp-register: %v\n", err)
		return 1
	}

	reports := []regReport{
		checkClaudeConfig(filepath.Join(home, ".claude.json"), runSh),
		checkVibeConfig(filepath.Join(home, ".vibe", "config.toml"), runSh),
		checkCodexConfig(filepath.Join(home, ".codex", "config.toml"), runSh),
	}
	for i, r := range reports {
		if i > 0 {
			fmt.Println()
		}
		printReport(r)
	}
	return 0
}

func printReport(r regReport) {
	fmt.Printf("%s (%s):\n", r.client, r.path)
	switch r.status {
	case regNotFound:
		fmt.Println("  not found — this client doesn't appear to be set up on this machine yet.")
		fmt.Println("  To register wp-ops once it is, create that file with:")
		fmt.Println()
		fmt.Println(indent(r.snippet))
	case regAlreadyRegistered:
		fmt.Println("  already registered.")
	case regNeedsRegistration:
		fmt.Println("  no wp-ops entry found. Add this block:")
		fmt.Println()
		fmt.Println(indent(r.snippet))
	case regParseError:
		fmt.Printf("  found but couldn't parse (%v) — check it by hand; see mcp-server/README.md for the manual snippet.\n", r.parseErr)
	}
}

func indent(s string) string {
	out := "  "
	for _, r := range s {
		out += string(r)
		if r == '\n' {
			out += "  "
		}
	}
	return out
}

// --- Claude Code (~/.claude.json, JSON) ---

type claudeConfig struct {
	McpServers map[string]any `json:"mcpServers"`
}

func checkClaudeConfig(path, runSh string) regReport {
	r := regReport{client: "Claude Code", path: path}

	snippet := fmt.Sprintf(`{
  "mcpServers": {
    "wp-ops": {
      "command": %q,
      "args": []
    }
  }
}`, runSh)

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		r.status = regNotFound
		r.snippet = snippet
		return r
	}
	if err != nil {
		r.status = regParseError
		r.parseErr = err
		return r
	}

	var cfg claudeConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		r.status = regParseError
		r.parseErr = err
		return r
	}
	if _, ok := cfg.McpServers["wp-ops"]; ok {
		r.status = regAlreadyRegistered
		return r
	}
	r.status = regNeedsRegistration
	// Only the entry to merge in, not the whole file — ~/.claude.json
	// already exists and almost certainly has other settings alongside it.
	r.snippet = fmt.Sprintf(`"wp-ops": {
  "command": %q,
  "args": []
}`, runSh)
	return r
}

// --- Mistral Vibe (~/.vibe/config.toml, [[mcp_servers]] array of tables) ---

type vibeConfig struct {
	McpServers []struct {
		Name string `toml:"name"`
	} `toml:"mcp_servers"`
}

func checkVibeConfig(path, runSh string) regReport {
	r := regReport{client: "Mistral Vibe", path: path}

	snippet := fmt.Sprintf(`[[mcp_servers]]
name = "wp_ops"
transport = "stdio"
command = %q
args = []`, runSh)

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		r.status = regNotFound
		r.snippet = snippet
		return r
	}
	if err != nil {
		r.status = regParseError
		r.parseErr = err
		return r
	}

	var cfg vibeConfig
	if err := toml.Unmarshal(data, &cfg); err != nil {
		r.status = regParseError
		r.parseErr = err
		return r
	}
	for _, s := range cfg.McpServers {
		if s.Name == "wp_ops" {
			r.status = regAlreadyRegistered
			return r
		}
	}
	r.status = regNeedsRegistration
	r.snippet = snippet
	return r
}

// --- OpenAI Codex CLI (~/.codex/config.toml, [mcp_servers.<name>] keyed table) ---

type codexConfig struct {
	McpServers map[string]any `toml:"mcp_servers"`
}

func checkCodexConfig(path, runSh string) regReport {
	r := regReport{client: "OpenAI Codex CLI", path: path}

	snippet := fmt.Sprintf(`[mcp_servers.wp_ops]
command = %q
args = []`, runSh)

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		r.status = regNotFound
		r.snippet = snippet
		return r
	}
	if err != nil {
		r.status = regParseError
		r.parseErr = err
		return r
	}

	var cfg codexConfig
	if err := toml.Unmarshal(data, &cfg); err != nil {
		r.status = regParseError
		r.parseErr = err
		return r
	}
	if _, ok := cfg.McpServers["wp_ops"]; ok {
		r.status = regAlreadyRegistered
		return r
	}
	r.status = regNeedsRegistration
	r.snippet = snippet
	return r
}
