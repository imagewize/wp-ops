# CLI Comparison: wp-ops vs trellis-cli

This document compares the CLI architectures and user experiences of **wp-ops** (this repository) and **trellis-cli** (Root's official CLI for Trellis), focusing on the key difference in how they handle the no-arguments case.

## Executive Summary

| Aspect | wp-ops | trellis-cli |
|--------|--------|-------------|
| **No-arguments behavior** | Launches full-screen interactive picker (Bubble Tea TUI) | Shows inline help text with all commands |
| **Terminal behavior** | Switches to alternate screen buffer (separate prompt) | Stays in current terminal window |
| **Framework** | Cobra + Bubble Tea | HashiCorp CLI |
| **Command discovery** | Dynamic from manifest files in repo | Static, defined in Go code |
| **Interactivity** | Rich TUI with filtering, preview, guided prompts | Standard command-line flags and args |

## Detailed Comparison

### 1. Entry Point and Framework

#### wp-ops

```go
// go/main.go
func main() {
    if err := cmd.Execute(); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
}
```

- **Framework**: [spf13/cobra](https://github.com/spf13/cobra) - A modern CLI framework for Go
- **Structure**: Single root command with dynamically registered subcommands
- **Pattern**: Commands are auto-discovered from manifest files embedded in the binary

#### trellis-cli

```go
// main.go
func main() {
    c := cli.NewCLI("trellis", version)
    c.Args = os.Args[1:]
    // ... setup UI, load config, register commands ...
    exitStatus, err := c.Run()
    // ... handle errors, updates ...
    os.Exit(exitStatus)
}
```

- **Framework**: [hashicorp/cli](https://github.com/hashicorp/cli) - HashiCorp's CLI library
- **Structure**: Static command registration via `map[string]cli.CommandFactory`
- **Pattern**: Commands are explicitly defined in code, not discovered

### 2. No-Arguments Behavior (The Key Difference)

#### wp-ops: Interactive Picker (Full-Screen TUI)

When `wp-ops` is run with no arguments:

```go
// go/cmd/root.go
func rootRunE(cc *cobra.Command, args []string) error {
    c := mustCatalog()
    if len(args) == 0 {
        if detect.IsTerminal(os.Stdin) && detect.IsTerminal(os.Stdout) {
            os.Exit(runInteractive(c))  // Launches Bubble Tea picker
            return nil
        }
        printCategorizedList(c)
        return nil
    }
    // ... handle arguments ...
}
```

The interactive picker is implemented using [Bubble Tea](https://github.com/charmbracelet/bubbletea):

```go
// go/internal/ui/picker.go
func RunPicker(c *catalog.Catalog) (Result, error) {
    m := New(c)
    p := tea.NewProgram(m, tea.WithAltScreen())  // <-- Key line
    final, err := p.Run()
    if err != nil {
        return Result{}, err
    }
    return final.(Model).result, nil
}
```

**`tea.WithAltScreen()`** is the crucial difference. This tells Bubble Tea to:
- Switch the terminal to an alternate screen buffer
- Clear the current terminal content
- Provide a clean, isolated UI experience
- Exit the alternate screen when the program finishes

This creates the "separate prompt" appearance shown in your screenshot.

The picker has multiple stages:
1. **Category selection** - Pick from organized categories (Monitoring, Backup, Content, etc.)
2. **Browse commands** - Filterable list with live preview pane
3. **Field prompting** - Guided argument collection for commands with @arg/@flag manifests

**Visual appearance:**
- Full-screen take-over
- Styled with lipgloss (colors, borders, cursor highlighting)
- Two-pane layout (command list + preview)
- Footer with keyboard hints

#### trellis-cli: Inline Help Text

When `trellis` is run with no arguments or `--help`:

```go
// main.go
c.HelpFunc = deprecatedCommandHelpFunc(deprecatedCommands, cli.BasicHelpFunc("trellis"))
// ...
exitStatus, err := c.Run()
```

The HashiCorp CLI library's `Run()` method handles this internally:
- Prints usage line: `Usage: trellis [--version] [--help] <command> [<args>]`
- Lists all available commands alphabetically
- Shows synopsis for each command
- Groups deprecated commands separately
- Stays in the same terminal window

**Visual appearance:**
- Standard terminal output
- No screen switching
- Simple text formatting (no borders, colors from fatih/color)
- Scrolls naturally with terminal buffer

### 3. Terminal Buffer Behavior

| Aspect | wp-ops (Bubble Tea) | trellis-cli (HashiCorp CLI) |
|--------|-------------------|----------------------------|
| **Alternate screen** | Yes (`tea.WithAltScreen()`) | No |
| **Terminal state** | Switches to alternate buffer, clears screen | Stays in primary buffer |
| **Scrollback** | Lost (alternate buffer doesn't preserve scrollback) | Preserved |
| **Exit behavior** | Returns to previous terminal state | Continues in same window |
| **Window title** | Can be set by Bubble Tea | Standard terminal title |

### 4. Command Organization

#### wp-ops: Dynamic Catalog

Commands are discovered from manifest files embedded in the binary:

```
wp-ops/
├── scripts/
│   ├── backup/
│   │   ├── db-backup.sh        (manifest: @category backup, @description ...)
│   │   └── files-backup.sh
├── trellis/
│   ├── backup/
│   │   └── database-backup.yml
└── wp-cli/
    ├── security/
    │   └── admin-user-create.sh
```

The catalog is built at compile time from these manifests, creating:
- Hidden commands for each full key (`scripts/backup/db-backup`)
- Visible commands for each category (`backup`, `trellis`, etc.)
- Display categories grouped by domain (Monitoring, Backup, Content, etc.)

#### trellis-cli: Static Registration

Commands are explicitly registered in `main.go`:

```go
c.Commands = map[string]cli.CommandFactory{
    "alias": func() (cli.Command, error) {
        return cmd.NewAliasCommand(ui, trellis), nil
    },
    "check": func() (cli.Command, error) {
        return &cmd.CheckCommand{UI: ui, Trellis: trellis}, nil
    },
    "db": func() (cli.Command, error) {
        return &cmd.NamespaceCommand{
            HelpText:     "Usage: trellis db <subcommand> [<args>]",
            SynopsisText: "Commands for database management",
        }, nil
    },
    // ... 40+ more commands
}
```

Namespace commands (like `db`, `vault`, `server`) use `NamespaceCommand` which just shows help:

```go
func (c *NamespaceCommand) Run(args []string) int {
    return cli.RunResultHelp  // Just shows help, doesn't execute
}
```

### 5. UI/UX Libraries

#### wp-ops Dependencies

```
github.com/charmbracelet/bubbles v1.0.0     // Text input, viewport, etc.
github.com/charmbracelet/bubbletea v1.3.10  // TUI framework
github.com/charmbracelet/lipgloss v1.1.0   // Styling
github.com/spf13/cobra v1.10.2             // CLI framework
```

#### trellis-cli Dependencies

```
github.com/hashicorp/cli v1.1.7          // CLI framework
github.com/fatih/color v1.19.0         // Terminal colors
```

### 6. Why the Different Approaches?

#### wp-ops: The Interactive Picker Rationale

The wp-ops CLI has **hundreds of commands** across many categories. The interactive picker solves:

1. **Discoverability** - With 70+ commands, a simple `--help` list would be overwhelming
2. **Organization** - Commands are grouped by domain (not directory), making it easier to find related functionality
3. **Guided workflow** - Commands with complex arguments get guided prompts
4. **Filtering** - Type to search across all commands
5. **Preview** - See command usage and description before selecting

The trade-off is the alternate screen, which some users find disruptive.

#### trellis-cli: The Simple Help Rationale

The trellis-cli has **~40 top-level commands** with some nested subcommands. The simple approach works because:

1. **Fewer commands** - The list fits comfortably on one screen
2. **Traditional CLI expectations** - Users of HashiCorp tools (Vagrant, Terraform) expect this pattern
3. **Composability** - Easy to pipe/grep the output
4. **No dependencies** - No need for TUI libraries

### 7. Strengths and Weaknesses

#### wp-ops Interactive Picker

**Strengths:**
- Excellent for large command catalogs
- Rich filtering and preview capabilities
- Guided prompts for complex commands
- Visually appealing and organized
- Stays consistent with the repo's evolution from bash scripts with fzf

**Weaknesses:**
- Requires terminal support for alternate screens (some SSH sessions, CI environments)
- Loses scrollback history
- Can feel "heavy" for simple use cases
- More complex codebase to maintain

#### trellis-cli Simple Help

**Strengths:**
- Lightweight and fast
- Works everywhere (SSH, CI, pipes, redirects)
- Familiar to CLI users
- Simple implementation
- Scrollback preserved

**Weaknesses:**
- Scales poorly with many commands
- No filtering or search
- No guided prompts
- Less visually organized

### 8. Recommendations

If you prefer the trellis-cli approach, you have several options:

#### Option A: Add a `--help` alias for wp-ops

Add a flag to skip the interactive picker:

```bash
wp-ops --help     # Show simple help (like trellis)
wp-ops            # Launch interactive picker (current behavior)
```

Implementation would add a flag check in `rootRunE`:

```go
var noPickerFlag bool

func init() {
    rootCmd.Flags().BoolVar(&noPickerFlag, "no-picker", false, "Show help instead of interactive picker")
}

func rootRunE(cc *cobra.Command, args []string) error {
    c := mustCatalog()
    if len(args) == 0 {
        if noPickerFlag || !detect.IsTerminal(os.Stdin) || !detect.IsTerminal(os.Stdout) {
            printCategorizedList(c)
            return nil
        }
        os.Exit(runInteractive(c))
        return nil
    }
    // ...
}
```

#### Option B: Environment Variable

```bash
WP_OPS_NO_PICKER=1 wp-ops    # Show simple help
wp-ops                        # Launch interactive picker
```

#### Option C: Detect and Adapt

Automatically use simple help when:
- Not a TTY
- Terminal width is too small
- `NO_COLOR` environment variable is set
- `TERM=dumb`

#### Option D: Make Simple Help the Default

Change the default behavior to show simple help, with a flag for the picker:

```bash
wp-ops            # Show simple help (new default)
wp-ops --interactive  # Launch picker (opt-in)
```

This would be a breaking change but aligns with trellis-cli's philosophy.

### 9. Code Architecture Comparison

| Aspect | wp-ops | trellis-cli |
|--------|--------|-------------|
| **Command discovery** | Dynamic from filesystem manifests | Static in code |
| **CLI framework** | Cobra | HashiCorp CLI |
| **TUI framework** | Bubble Tea | None |
| **Styling** | lipgloss | fatih/color |
| **Command registration** | Auto-generated at startup | Manual in main.go |
| **Argument parsing** | Delegated to underlying scripts | Handled by each command |
| **Help generation** | Custom (picker + text fallbacks) | HashiCorp CLI built-in |
| **Completions** | Cobra + custom logic | posener/complete |

### 10. Conclusion

The fundamental difference is **philosophical**:

- **wp-ops**: "So many commands, you need a GUI" - Optimized for discoverability in a large ecosystem
- **trellis-cli**: "Keep it simple" - Traditional CLI that trusts users to know what they want

Both approaches are valid. The wp-ops interactive picker is more "modern" and user-friendly for large command sets, while trellis-cli's simplicity is more "Unix-like" and composable.

If you want wp-ops to behave more like trellis-cli, **Option A** (adding a `--help` or `--no-picker` flag) would give you the best of both worlds without breaking existing user expectations.
