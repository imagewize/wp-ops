# Find and Replace Files Script

A utility script for finding and replacing multiple copies of a file across directory trees. Useful for updating shared scripts (like `create-pr.sh`) across multiple projects.

## Script Location

`scripts/find-and-replace-files.sh`

## Features

- **Find files** by name recursively through directory structure
- **Replace files** with an updated version in one operation
- **Dry-run mode** to preview changes before applying
- **List-only mode** to just see where files are located
- **Size display** to see file sizes and line counts
- **Configurable depth** to limit search scope
- **Permission preservation** - maintains executable flags

## Usage

### Basic Usage

```bash
# List all instances of a file
./scripts/find-and-replace-files.sh create-pr.sh

# List with file sizes and line counts
./scripts/find-and-replace-files.sh -l -s create-pr.sh

# List in a specific directory
./scripts/find-and-replace-files.sh -d ~/code -l create-pr.sh
```

### Replace Files

```bash
# Replace all create-pr.sh files with updated version
./scripts/find-and-replace-files.sh create-pr.sh /path/to/updated/create-pr.sh

# Dry run first to see what would be replaced
./scripts/find-and-replace-files.sh -n -d ~/code create-pr.sh /path/to/updated/create-pr.sh

# Then run for real
./scripts/find-and-replace-files.sh -d ~/code create-pr.sh /path/to/updated/create-pr.sh
```

### Control Search Depth

```bash
# Search only immediate subdirectories (depth 2)
./scripts/find-and-replace-files.sh -m 2 -d ~/code create-pr.sh

# Search deeper (depth 10)
./scripts/find-and-replace-files.sh -m 10 -d /path/to/search create-pr.sh
```

## Options

| Option | Short | Description |
|--------|-------|-------------|
| `--directory <dir>` | `-d <dir>` | Search directory (default: current directory) |
| `--maxdepth <n>` | `-m <n>` | Maximum search depth (default: 5) |
| `--dry-run` | `-n` | Show what would be done without making changes |
| `--list` | `-l` | List found files without replacing |
| `--size` | `-s` | Show file sizes and line counts in listing |
| `--help` | `-h` | Show help message |

## Examples

### Example 1: Find all create-pr.sh files in ~/code

```bash
./scripts/find-and-replace-files.sh -d ~/code -l -s create-pr.sh
```

Output:
```
Searching for 'create-pr.sh' in /Users/jasperfrumau/code (max depth: 5)...

    670 lines |    21 KB | /Users/jasperfrumau/code/wp-ops/scripts/create-pr.sh
    670 lines |    21 KB | /Users/jasperfrumau/code/elayne/create-pr.sh
    639 lines |    21 KB | /Users/jasperfrumau/code/mistral-agents/create-pr.sh
    ...

Found 26 file(s).
```

### Example 2: Update all create-pr.sh files (dry run first)

```bash
# First, dry run to see what would change
./scripts/find-and-replace-files.sh -n -d ~/code create-pr.sh ~/wp-ops/scripts/create-pr.sh

# Output shows all files that would be replaced
# [DRY RUN] Would copy: /path/to/source -> /path/to/destination
# [DRY RUN] Would copy: /path/to/source -> /path/to/another/destination
# ...
# Dry run complete. No files were modified.

# Then run for real
./scripts/find-and-replace-files.sh -d ~/code create-pr.sh ~/wp-ops/scripts/create-pr.sh

# Output shows actual copies
# /path/to/source -> /path/to/destination
# /path/to/source -> /path/to/another/destination
# ...
# Updated 26 file(s).
```

### Example 3: Quick check for outdated files

```bash
# See which files are outdated (different sizes)
./scripts/find-and-replace-files.sh -d ~/code -m 4 -s create-pr.sh | grep -v " 670 lines"
```

## Use Cases

1. **Updating shared scripts** - When you improve `create-pr.sh`, use this to update all copies across your projects
2. **Syncing configuration files** - Keep `.editorconfig`, `.gitignore` templates in sync
3. **Batch script updates** - Update multiple instances of utility scripts
4. **Finding duplicate files** - Locate all copies of a file to clean up
5. **Auditing file versions** - Check which projects have outdated versions

## Notes

- The script preserves file permissions (if source is executable, destination will be too)
- Uses null-terminated output from `find` for safe handling of filenames with spaces
- Default max depth of 5 balances thoroughness with performance
- Dry-run mode is highly recommended before bulk replacements
