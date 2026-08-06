# Third-Party Extensions for wp-ops

This document outlines strategies for allowing third parties to add new scripts or Ansible playbooks to wp-ops while preventing duplicates, ensuring testability, and enabling easy drop-in functionality.

## Table of Contents

- [Current Architecture Overview](#current-architecture-overview)
- [Proposed Extension Strategies](#proposed-extension-strategies)
  - [Option A: External Commands Directory](#option-a-external-commands-directory)
  - [Option B: Configuration-Driven Plugins](#option-b-configuration-driven-plugins)
  - [Option C: Git Submodules Approach](#option-c-git-submodules-approach)
  - [Option D: Package Manager Style](#option-d-package-manager-style)
- [Duplicate Prevention](#duplicate-prevention)
- [Testing Framework](#testing-framework)
- [Drop-in Installation](#drop-in-installation)
- [Metadata Standards](#metadata-standards)
- [Security Considerations](#security-considerations)
- [Recommended Implementation](#recommended-implementation)
- [Example Workflow](#example-workflow)

---

## Current Architecture Overview

wp-ops currently uses a **manifest-based catalog system** where:

1. Each script/playbook contains metadata in comments (YAML frontmatter for playbooks)
2. The `gen` tool scans the repository at build time and generates `catalog.json`
3. The Go binary embeds this catalog and provides CLI discovery, help, and execution
4. Commands are organized by category and platform

### Existing Metadata Schema

**For Bash scripts (in comments):**
```bash
# @desc     Short description of what the script does
# @category backup|monitoring|git|migration|diagnostics|security|release|misc
# @platform any|wordpress|trellis
# @runs     local|server|either
# @requires dependency1 dependency2
# @arg      name  required/optional  {default}  Description
# @flag     --flag-name  optional/required  {default}  Description
# @example  wp-ops command arg1 arg2
# @doc      path/to/documentation.md
```

**For Ansible playbooks (in YAML comments):**
```yaml
# @desc     Short description
# @category backup|monitoring|provision|security|updater
# @platform trellis
# @runs     local|server
# @requires ansible-playbook
# @arg      site  required  {example.com}  Site name
# @arg      env   required  {production}  Environment
# @example  wp-ops playbook-name site.com production
# @doc      trellis/category/README.md
```

---

## Proposed Extension Strategies

### Option A: External Commands Directory

**Concept:** Allow users to specify external directories containing additional scripts/playbooks that wp-ops will discover and include in its catalog.

**Implementation:**
```go
// In configuration
type Config struct {
    ExtraCommandPaths []string `yaml:"extra_command_paths"`
}
```

**Usage:**
```yaml
# ~/.config/wp-ops/config.yml
extra_command_paths:
  - ~/my-wp-ops-extensions/scripts
  - /opt/wp-ops-plugins
```

**Pros:**
- Simple to implement
- Familiar pattern (similar to PATH environment variable)
- Easy for users to organize their own extensions
- No changes to core wp-ops needed for basic functionality

**Cons:**
- Need runtime filesystem scanning (current system is build-time only)
- Potential performance impact with many external paths
- Need to handle duplicate command names

### Option B: Configuration-Driven Plugins

**Concept:** Use a configuration file to register external commands with their metadata, similar to how trellis-cli handles plugins.

**Implementation:**
```yaml
# ~/.config/wp-ops/plugins.yml
plugins:
  my-backup-tool:
    path: /path/to/backup-script.sh
    desc: "Custom backup solution for special hosting"
    category: backup
    platform: any
    runs: local
    requires: [curl, aws]
    args:
      - name: site
        required: true
        description: "Site URL to backup"
    examples:
      - "wp-ops my-backup-tool https://example.com"

  custom-monitor:
    path: /path/to/monitor.yml
    type: ansible
    desc: "Custom monitoring playbook"
    category: monitoring
    platform: trellis
    runs: local
    requires: [ansible-playbook]
    args:
      - name: site
        required: true
      - name: env
        required: true
```

**Pros:**
- Explicit registration prevents ambiguity
- Full control over metadata
- Can validate inputs before execution
- Easy to enable/disable plugins

**Cons:**
- Requires maintaining a separate configuration file
- More complex setup for simple scripts

### Option C: Git Submodules Approach

**Concept:** Allow extensions to be added as Git submodules in a designated directory.

**Structure:**
```
wp-ops/
├── extensions/
│   ├── my-company-extensions/  (git submodule)
│   │   ├── scripts/
│   │   │   └── custom-tool.sh
│   │   ├── playbooks/
│   │   │   └── custom-playbook.yml
│   │   └── README.md
│   └── community-plugins/     (git submodule)
│       └── ...
```

**Pros:**
- Version-controlled extensions
- Easy to share and distribute
- Can be updated independently
- Built-in dependency management

**Cons:**
- Requires Git knowledge
- Can bloat the main repository
- Need to handle submodule initialization

### Option D: Package Manager Style

**Concept:** Create a simple package manager for wp-ops extensions.

**Implementation:**
```bash
# Install an extension
wp-ops plugin install github.com/user/wp-ops-custom-backup

# List installed extensions
wp-ops plugin list

# Update all extensions
wp-ops plugin update

# Remove an extension
wp-ops plugin remove custom-backup
```

**Extension manifest format:**
```yaml
# .wp-ops-extensions/manifest.yml
name: custom-backup
description: "Custom backup solution"
version: 1.0.0
author: "Your Name"
repository: github.com/user/wp-ops-custom-backup
commands:
  - path: scripts/backup.sh
    category: backup
    platform: any
    # ... other metadata
```

**Pros:**
- Professional plugin ecosystem
- Easy discovery and installation
- Version management
- Dependency resolution

**Cons:**
- Significant implementation effort
- Need to host extension registry
- More complex infrastructure

---

## Duplicate Prevention

### Strategy 1: Namespace Prefixing

Require all third-party commands to use a namespace prefix to prevent conflicts with core commands.

```bash
# Third-party commands must use vendor:command-name format
wp-ops acme:backup
wp-ops mycompany:migrate
```

**Implementation:**
- Validate command names during registration
- Reject commands that don't follow the naming convention
- Automatically prefix discovered commands from external sources

### Strategy 2: Priority System

Implement a priority system where core commands take precedence over third-party ones.

```go
type CommandSource int

const (
    CoreCommand CommandSource = iota
    BuiltinExtension
    UserExtension
    ThirdPartyExtension
)

// When duplicate is found, higher priority wins
func resolveDuplicate(existing, new CommandEntry) CommandEntry {
    if existing.Priority >= new.Priority {
        return existing
    }
    return new
}
```

### Strategy 3: Explicit Override Configuration

Allow users to explicitly override or disable conflicting commands.

```yaml
# ~/.config/wp-ops/config.yml
command_overrides:
  # Disable core command in favor of plugin
  disable:
    - backup
    - migration/export
  
  # Alias third-party command to simpler name
  aliases:
    my-backup: acme:backup-tool
```

### Strategy 4: Duplicate Detection and Warning

Implement detection and warning system:

```go
func checkDuplicates(catalog *Catalog) []Conflict {
    nameCount := make(map[string][]string)
    
    for _, entry := range catalog.Entries {
        nameCount[entry.Name] = append(nameCount[entry.Name], entry.Source)
    }
    
    var conflicts []Conflict
    for name, sources := range nameCount {
        if len(sources) > 1 {
            conflicts = append(conflicts, Conflict{
                Name:    name,
                Sources: sources,
            })
        }
    }
    return conflicts
}
```

**CLI Output:**
```
Warning: Command 'backup' is defined in multiple locations:
  - Core: scripts/backup/db-backup.sh
  - Plugin: ~/extensions/my-backup/backup.sh
  
Using core version. To use the plugin version, add to config:
  command_overrides:
    disable:
      - backup
```

---

## Testing Framework

### Test Command Structure

Create a standardized way to test scripts/playbooks:

```bash
# Directory structure for extensions with tests
my-extension/
├── scripts/
│   └── custom-tool.sh
├── playbooks/
│   └── custom-playbook.yml
└── tests/
    ├── custom-tool_test.sh      # Test script
    ├── custom-tool_test.yml     # Test playbook
    └── fixtures/                 # Test data
        └── test-site/
```

### Test Metadata

Add testing metadata to command annotations:

```bash
# @test       path/to/test-script.sh
# @test-data  path/to/fixtures
# @test-cmd   ./test-script.sh
# @test-args  --site test-site
```

### Test Runner

Implement a test runner that can:

1. **Syntax validation:** Check scripts for syntax errors
   ```bash
   wp-ops test validate my-extension/
   ```

2. **Unit testing:** Run test scripts in isolation
   ```bash
   wp-ops test run my-extension/tests/custom-tool_test.sh
   ```

3. **Integration testing:** Test with actual dependencies (optional)
   ```bash
   wp-ops test integrate my-extension/ --with-ansible --with-wp-cli
   ```

4. **Continuous integration:** Generate GitHub Actions workflows
   ```bash
   wp-ops test generate-ci > .github/workflows/test.yml
   ```

### Test Script Template

```bash
#!/bin/bash
# test-custom-tool.sh - Test script for custom-tool

set -euo pipefail

# Test helper functions
source "$(wp-ops test-helpers)"

setup() {
    # Create temporary directory
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Set up test environment
    mkdir -p test-site/wp-content
    echo "test" > test-site/wp-content/test.txt
}

teardown() {
    rm -rf "$TEST_DIR"
}

test_basic_functionality() {
    # Run the script with test arguments
    output=$("${EXTENSION_DIR}/scripts/custom-tool.sh" --site "$TEST_DIR/test-site")
    
    # Assertions
    assert_contains "$output" "Success"
    assert_file_exists "$TEST_DIR/test-site/wp-content/output.txt"
}

test_error_handling() {
    # Test error conditions
    assert_throws "${EXTENSION_DIR}/scripts/custom-tool.sh" --invalid-arg
}

# Run tests
main() {
    setup
    
    run_test test_basic_functionality "Basic functionality test"
    run_test test_error_handling "Error handling test"
    
    teardown
    echo "All tests passed!"
}

main "$@"
```

---

## Drop-in Installation

### Single File Installation

For simple scripts, allow installation via a single file:

```bash
# Install a single script
wp-ops install-script https://gist.githubusercontent.com/user/123456/custom-tool.sh

# This will:
# 1. Download the script
# 2. Extract metadata from annotations
# 3. Place it in ~/.wp-ops-extensions/scripts/
# 4. Update the catalog cache
```

### Directory Installation

For collections of scripts/playbooks:

```bash
# Install from a Git repository
wp-ops install-extension https://github.com/user/wp-ops-custom-tools

# Install from a local directory
wp-ops install-extension /path/to/my-tools
```

### Installation Process

```
1. Validate the source (Git repo, URL, or local path)
2. Clone/download to ~/.wp-ops-extensions/<name>/
3. Scan for scripts and playbooks with valid metadata
4. Validate metadata and command names
5. Check for duplicates and warn user
6. Update catalog cache
7. Verify installation
```

### Installation Locations

```
# Default locations (configurable)
Extensions directory: ~/.wp-ops-extensions/
Catalog cache:        ~/.cache/wp-ops/catalog.json
Config file:         ~/.config/wp-ops/config.yml
Plugins directory:   ~/.local/share/wp-ops/plugins/
```

---

## Metadata Standards

### Required Metadata

Every third-party command MUST include:

- **@desc**: Clear description of what the command does
- **@category**: Primary category (must be existing or new reasonable category)
- **@platform**: Target platform (any, wordpress, trellis)
- **@runs**: Execution location (local, server)

### Recommended Metadata

- **@requires**: List of dependencies
- **@arg**: Argument definitions
- **@flag**: Flag definitions
- **@example**: Usage examples
- **@doc**: Documentation path
- **@author**: Author information
- **@version**: Command version
- **@license**: License information

### Metadata Validation

```go
func validateMetadata(entry CommandEntry) error {
    // Required fields
    if entry.Desc == "" {
        return errors.New("missing @desc")
    }
    if entry.Category == "" {
        return errors.New("missing @category")
    }
    if entry.Platform == "" {
        return errors.New("missing @platform")
    }
    if entry.Runs == "" {
        return errors.New("missing @runs")
    }
    
    // Validate enumerated values
    validPlatforms := []string{"any", "wordpress", "trellis"}
    if !contains(validPlatforms, entry.Platform) {
        return fmt.Errorf("invalid @platform: %s, must be one of %v", 
            entry.Platform, validPlatforms)
    }
    
    validRuns := []string{"local", "server", "either"}
    if !contains(validRuns, entry.Runs) {
        return fmt.Errorf("invalid @runs: %s, must be one of %v", 
            entry.Runs, validRuns)
    }
    
    return nil
}
```

---

## Security Considerations

### Sandboxing

1. **Read-only mode:** Commands can be marked as read-only
2. **Confirmation prompts:** Require confirmation for destructive operations
3. **Dry-run support:** All commands should support --dry-run flag

### Permission Model

```yaml
# In extension manifest
permissions:
  filesystem:
    read: ["/path/patterns"]
    write: []  # Empty means no write access
  network:
    allowed_hosts: ["api.example.com", "github.com"]
  commands:
    allowed: ["wp", "git", "rsync"]
    blocked: ["rm", "chmod", "chown"]
```

### Code Review

1. **Signature verification:** Allow signed extensions
2. **Source review:** Maintain a curated list of trusted sources
3. **Sandbox execution:** Run untrusted commands in containers

### Safe Defaults

```bash
# Always run with safe defaults
set -euo pipefail

# Validate inputs
validate_input "$1" "site" "required"

# Use dry-run by default for destructive operations
DRY_RUN=${DRY_RUN:-true}
if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY RUN] Would perform: $ACTION"
    return 0
fi
```

---

## Recommended Implementation

Based on analysis of the current architecture and requirements, **Option A (External Commands Directory)** with enhancements from other options provides the best balance:

### Phase 1: External Paths Support

1. **Add configuration support for external paths**
   ```yaml
   # ~/.config/wp-ops/config.yml
   extra_command_paths:
     - ~/my-extensions
     - /opt/wp-ops-plugins
   ```

2. **Modify catalog loading to include external paths**
   - Scan external paths at startup (not just build-time)
   - Merge with embedded catalog
   - Handle duplicates with priority system

3. **Add CLI commands for extension management**
   ```bash
   wp-ops extension path add ~/my-extensions
   wp-ops extension path remove ~/my-extensions
   wp-ops extension list
   wp-ops extension validate
   ```

### Phase 2: Plugin System

1. **Implement plugin manifest format**
   - Simple YAML files describing extensions
   - Support for versioning and dependencies

2. **Add plugin installation commands**
   ```bash
   wp-ops plugin install github.com/user/my-plugin
   wp-ops plugin remove my-plugin
   wp-ops plugin update
   wp-ops plugin search
   ```

### Phase 3: Testing Framework

1. **Add test command**
   ```bash
   wp-ops test validate my-extension/
   wp-ops test run my-extension/tests/
   ```

2. **Create test helpers library**
   - Common assertion functions
   - Mock utilities
   - Test fixtures management

---

## Example Workflow

### For Extension Developers

1. **Create extension structure**
   ```bash
   mkdir my-wp-ops-extension
   cd my-wp-ops-extension
   mkdir -p scripts playbooks tests
   ```

2. **Add a script with proper metadata**
   ```bash
   #!/bin/bash
   #
   # @desc     Custom backup for special hosting
   # @category backup
   # @platform any
   # @runs     local
   # @requires curl aws
   # @arg      site  required  {example.com}  Site URL
   # @arg      dest  optional  {s3://backups/}  Destination
   # @example  wp-ops custom-backup https://example.com
   # @author   Your Name <you@example.com>
   # @version  1.0.0
   # @license  MIT
   ```

3. **Add tests**
   ```bash
   #!/bin/bash
   # tests/custom-backup_test.sh
   
   source "$(wp-ops test-helpers)"
   
   test_backup_creation() {
       # ... test logic
   }
   ```

4. **Create extension manifest**
   ```yaml
   # extension.yml
   name: custom-backup
   description: "Custom backup solution"
   version: 1.0.0
   author: "Your Name"
   commands:
     - scripts/custom-backup.sh
   ```

5. **Package and distribute**
   ```bash
   git init
   git add .
   git commit -m "Initial version"
   git tag v1.0.0
   git push origin main
   ```

### For Users

1. **Install extension**
   ```bash
   wp-ops extension install github.com/yourname/my-wp-ops-extension
   ```

2. **Use the new command**
   ```bash
   wp-ops custom-backup https://example.com
   ```

3. **List installed extensions**
   ```bash
   wp-ops extension list
   ```

4. **Test an extension**
   ```bash
   wp-ops test validate my-wp-ops-extension
   wp-ops test run my-wp-ops-extension/tests/
   ```

---

## Migration Path

For existing wp-ops users wanting to add custom scripts:

1. **Before (manual):**
   - Add scripts to wp-ops repository
   - Modify catalog manually
   - Rebuild wp-ops binary
   - Handle merge conflicts

2. **After (with extensions):**
   - Create separate extension repository
   - Install via `wp-ops extension install`
   - No need to modify core wp-ops
   - Easy to share with team

---

## Conclusion

The recommended approach combines external command directory scanning with a simple plugin system. This provides:

- **Easy drop-in:** Just add scripts to configured directories
- **No duplicates:** Priority system and namespace support
- **Testability:** Built-in test framework
- **Flexibility:** Works with simple scripts or complex plugin collections
- **Security:** Sandboxing and permission controls
- **Maintainability:** No changes to core wp-ops needed

This approach allows third parties to extend wp-ops while maintaining the existing architecture's simplicity and performance.
