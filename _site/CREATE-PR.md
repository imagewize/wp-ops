# Create PR Script

An intelligent script (`create-pr.sh`) that creates GitHub pull requests with professional, AI-powered descriptions similar to GitHub Copilot.

## Features

- **Multi-AI Backend Support**: Choose between Claude CLI or Codex CLI for AI-powered descriptions
- **AI-Powered Descriptions**: Uses AI to analyze git diffs and generate intelligent summaries
- **Professional Formatting**: Creates descriptions with grouped sections, bold headings, and detailed bullet points
- **Clickable File Links**: Each file links directly to the changed version on GitHub for quick access
- **Smart Categorization**: Automatically detects change types (dependencies, documentation, styling, etc.)
- **Automatic PR Creation**: Uses GitHub CLI to create the actual pull request
- **Fallback Mode**: Works without AI when API key is not available
- **Interactive AI Selection**: Choose your preferred AI tool when both are available

## Token Usage Comparison

Understanding the cost/benefit of using AI vs no-AI mode:

### Option 1: Claude Code without this script (Manual PR)
**Token Usage**: ~2,000-10,000+ tokens per PR
- You ask Claude: "Create a PR for my changes"
- Claude reads multiple files to understand context
- Back-and-forth conversation to refine the description
- Claude runs git commands to analyze changes
- **Result**: Uses significant tokens, quality depends on conversation

### Option 2: This Script with AI (`--no-ai` NOT used)
**Token Usage**: ~500-1,500 tokens per PR
- Script pre-processes all git data (commits, files, diff stats)
- Sends only structured summary to Claude
- Single prompt, no back-and-forth needed
- Claude generates description in one response
- **Result**: 70-85% fewer tokens than manual, high-quality output

### Option 3: This Script without AI (`--no-ai` flag)
**Token Usage**: 0 tokens
- Script generates basic but professional description
- Lists all commits, files changed, and statistics
- No intelligent grouping or summarization
- **Result**: Free, but generic descriptions

### What You Get With Each Option

| Feature | Manual (Claude Code) | Script + AI | Script --no-ai |
|---------|---------------------|-------------|----------------|
| Token cost | High (2k-10k+) | Low (500-1.5k) | Zero |
| Intelligent summary | ✅ Good | ✅ Excellent | ❌ Generic |
| Grouped sections | ❌ Sometimes | ✅ Always | ❌ No |
| File links | ❌ No | ✅ Yes | ✅ Yes |
| Version numbers/metrics | ❌ Sometimes | ✅ Yes | ❌ No |
| Professional tone | ⚠️ Varies | ✅ Consistent | ✅ Basic |
| Time to create | Slow | Fast | Instant |

### Recommendation

**Use Script + AI** when:
- You want Copilot-quality descriptions
- You want to save 70-85% tokens vs manual
- The PR has complex changes that need explanation
- You want consistent, professional output

**Use Script --no-ai** when:
- The PR is simple (e.g., dependency update, single file change)
- You don't need intelligent summarization
- You want zero token usage
- You'll manually edit the description anyway

## Prerequisites

1. **GitHub CLI** (required)
   ```bash
   brew install gh
   gh auth login
   ```

2. **AI CLI** (optional, for AI descriptions)

   Choose one or both:

   **Claude CLI** (recommended)
   - If you're using Claude Code in VS Code, you already have this installed!
   - Otherwise, download from: https://claude.ai/download
   - The script will automatically use your existing Claude authentication

   **Codex CLI** (alternative)
   - Install via npm: `npm install -g @anthropic-ai/codex-cli`
   - Or download from your AI provider

   The script automatically detects which AI tools are available and lets you choose interactively.

## Installation

1. Make the script executable:
   ```bash
   chmod +x create-pr.sh
   ```

2. Optionally, add to your PATH or create an alias:
   ```bash
   # Add to ~/.zshrc or ~/.bashrc
   alias pr='/path/to/create-pr.sh'
   ```

## Usage

### Interactive Mode (Default)

Just run the script and answer the prompts:

```bash
./create-pr.sh

# You'll be prompted for:
# 1. Base branch (default: main)
# 2. PR title (default: auto-generated from branch name)
# 3. Use AI for description? (Y/n)
```

**Example interaction:**
```
🚀 Create Pull Request
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current branch: feature/user-auth

Base branch (default: main):
PR title (default: Feature User Auth): Add user authentication
Use AI to generate description? (Y/n): y

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Non-Interactive Mode

Provide arguments to skip prompts:

```bash
# With all arguments
./create-pr.sh main "Add authentication feature"

# Just base branch (title auto-generated)
./create-pr.sh develop

# Skip all prompts, use defaults
./create-pr.sh --no-interactive
```

### Options

```bash
# Choose AI backend (claude or codex)
./create-pr.sh --ai=claude
./create-pr.sh --ai=codex

# Skip AI generation (0 tokens, basic description)
./create-pr.sh --no-ai

# Skip all prompts, use arguments/defaults
./create-pr.sh --no-interactive

# Combine options
./create-pr.sh main "Feature update" --ai=codex --no-interactive
./create-pr.sh main "Feature update" --no-ai --no-interactive

# Update existing PR with fresh AI-generated description
./create-pr.sh --update
./create-pr.sh --update --ai=codex
```

## Example Output Comparison

Let's say you have a PR with 10 files changed (3 added, 7 modified), 5 commits, updating a dependency and adding a new feature.

### With AI Mode (Script + Claude)
**Token usage: ~800 tokens** | **Quality: Copilot-level**

```markdown
This pull request adds user authentication functionality and updates the Express dependency to v4.18.2. The changes introduce JWT-based authentication with secure password hashing, role-based access control, and comprehensive error handling. This provides a foundation for protected API endpoints and user session management.

**Authentication implementation:**

* Added JWT token generation and validation middleware in `middleware/auth.js`
* Implemented bcrypt password hashing with salt rounds configured for security
* Created user login and registration endpoints with input validation

**Security enhancements:**

* Added role-based access control (RBAC) supporting admin and user roles
* Implemented rate limiting on authentication endpoints to prevent brute force attacks
* Added secure cookie handling for refresh tokens with HTTP-only and secure flags

**Dependency updates:**

* Upgraded Express from v4.17.1 to v4.18.2 for security patches
* Added jsonwebtoken v9.0.0 and bcryptjs v2.4.3 for authentication

**Files Changed:**

- [`package.json`](https://github.com/user/repo/blob/feature/auth/package.json) (Modified)
- [`src/middleware/auth.js`](https://github.com/user/repo/blob/feature/auth/src/middleware/auth.js) (Added)
- [`src/routes/auth.js`](https://github.com/user/repo/blob/feature/auth/src/routes/auth.js) (Added)
- [`src/controllers/user.js`](https://github.com/user/repo/blob/feature/auth/src/controllers/user.js) (Modified)
...
```

### Without AI Mode (`--no-ai`)
**Token usage: 0 tokens** | **Quality: Basic but professional**

```markdown
## Summary

This pull request introduces changes from the `feature/auth` branch into `main`. The changes include 5 commit(s) affecting 3 added, 7 modified file(s).

## Changes

10 files changed, 234 insertions(+), 89 deletions(-)

### Commits

- Add JWT authentication middleware (a1b2c3d)
- Implement user login endpoint (e4f5g6h)
- Add password hashing with bcrypt (i7j8k9l)
- Update Express to v4.18.2 (m1n2o3p)
- Add role-based access control (q4r5s6t)

### Files Changed

- [`package.json`](https://github.com/user/repo/blob/feature/auth/package.json) (Modified)
- [`package-lock.json`](https://github.com/user/repo/blob/feature/auth/package-lock.json) (Modified)
- [`src/middleware/auth.js`](https://github.com/user/repo/blob/feature/auth/src/middleware/auth.js) (Added)
- [`src/routes/auth.js`](https://github.com/user/repo/blob/feature/auth/src/routes/auth.js) (Added)
- [`src/controllers/user.js`](https://github.com/user/repo/blob/feature/auth/src/controllers/user.js) (Modified)
- [`src/config/auth.js`](https://github.com/user/repo/blob/feature/auth/src/config/auth.js) (Added)
...
```

### Summary of Differences

**AI Mode advantages:**
- Explains WHY changes were made, not just WHAT
- Groups related changes with meaningful headings
- Extracts specific details (version numbers, security features)
- Provides context for reviewers
- Looks like a senior developer wrote it

**No-AI Mode advantages:**
- Zero token cost
- Instant generation
- Still includes all file links and commit messages
- Good for simple PRs or when you'll edit manually
- Professional structure, just less intelligent

## How It Works

1. **Branch Detection**: Automatically detects current branch and ensures it's pushed to remote
2. **Change Analysis**: Collects commits, file changes, and diff statistics
3. **Category Detection**: Identifies change types based on file patterns
4. **AI Generation** (if enabled): Sends context to Claude API for intelligent summary
5. **PR Creation**: Uses `gh pr create` to create the actual GitHub pull request

## AI Description Generation

When an AI CLI is available (Claude or Codex), the script:

1. Analyzes commit messages, changed files, and categories
2. Sends a structured prompt to your chosen AI tool using your existing authentication
3. Receives a professional description with:
   - Concise introductory paragraph
   - Grouped sections with bold headings
   - Detailed bullet points
   - Specific metrics and version numbers

The AI is instructed to write like a senior developer - no emoticons, professional tone, focusing on what changed and why.

### Choosing Your AI Backend

The script supports multiple AI backends:

**Automatic Detection**: If you don't specify `--ai=`, the script will:
1. Check for both Claude and Codex CLIs
2. If both are available, ask you to choose
3. If only one is available, use that automatically
4. If none are available, offer no-AI mode

**Manual Selection**: Use `--ai=claude` or `--ai=codex` to force a specific backend

**Interactive Selection**: When both are available and you're in interactive mode:
```
Available AI tools: claude codex
Choose AI tool [default: claude]: codex
```

### Environment Variables

For advanced users, you can customize the CLI commands and arguments:

```bash
# Use custom Claude command name
export CLAUDE_COMMAND="claude-custom"

# Use custom Codex command name
export CODEX_COMMAND="my-codex"

# Pass custom arguments to Claude CLI
export CLAUDE_CLI_ARGS="--model=opus --timeout=30"

# Pass custom arguments to Codex CLI
export CODEX_CLI_ARGS="--verbose"

./create-pr.sh
```

**Note**: If you're using Claude Code in VS Code, the Claude CLI works automatically with no additional setup!

## Troubleshooting

### "No AI CLI found"

The script checks for both `claude` and `codex` commands. If neither is found:

**For Claude CLI:**
- If you're using Claude Code in VS Code, make sure the `claude` command is in your PATH:
  ```bash
  which claude
  # Should output: /Users/yourname/.volta/bin/claude
  ```
- Restart your terminal after installing Claude Code
- Download Claude CLI from: https://claude.ai/download

**For Codex CLI:**
- Install via npm: `npm install -g @anthropic-ai/codex-cli`
- Or check your AI provider's installation instructions

**Workaround:**
- Run with `--no-ai` flag to skip AI generation and use basic descriptions

### "AI tool 'codex' not found"

If you specified `--ai=codex` but don't have it installed:
- Remove the `--ai=codex` flag to use Claude (if available)
- Install Codex CLI
- Or use `--no-ai` for basic descriptions

### "gh is not installed"

Install with: `brew install gh` and authenticate with `gh auth login`

### PR creation fails

Make sure:
- You're on a feature branch (not main/master)
- Your branch is pushed to remote
- You're authenticated with GitHub CLI

## Comparison with GitHub Copilot

This script provides similar functionality to GitHub Copilot's PR descriptions:

| Feature | This Script | GitHub Copilot |
|---------|-------------|----------------|
| AI-powered summaries | ✅ | ✅ |
| Grouped sections | ✅ | ✅ |
| File reference links | ✅ | ✅ |
| Clickable file links | ✅ | ✅ |
| Professional tone | ✅ | ✅ |
| Works offline | ✅ (with --no-ai) | ❌ |
| Free (with your own API key) | ✅ | ❌ |
| Customizable prompts | ✅ | ❌ |

## Customization

You can modify the AI prompt in the script to match your team's preferences:

```bash
# Edit the prompt in generate_ai_description() function
# Located around line 202 in the script
```

## License

MIT
