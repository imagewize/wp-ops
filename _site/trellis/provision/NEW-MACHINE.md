# New Machine Setup for Trellis Development

Complete guide for setting up a Mac for [Roots Trellis](https://roots.io/trellis/) WordPress development.

**Purpose:** This guide covers installing the tools and understanding the architecture needed for Trellis development on macOS. For setting up an existing Trellis project after your machine is configured, see [PROJECT-SETUP.md](PROJECT-SETUP.md).

## Table of Contents

- [Understanding Trellis Architecture](#understanding-trellis-architecture)
- [Required Tools Installation](#required-tools-installation)
- [SSH Key Setup](#ssh-key-setup)
- [Verification](#verification)
- [Next Steps](#next-steps)

## Understanding Trellis Architecture

### The Two Environments

**Important distinction:**

- **Host Machine (macOS):** Your local Mac where you edit code and run development tools
- **Trellis VM (Lima/Ubuntu):** Virtual machine that runs the WordPress LEMP stack

### What Runs Where

| Tool | Host Machine | Trellis VM | Purpose |
|------|-------------|------------|---------|
| Trellis CLI | ✅ Required | ❌ | Manages the VM |
| Composer | ✅ Required | ✅ Included | Installs PHP dependencies locally |
| PHP | ✅ Required | ✅ Included | Runs Composer on host; runs WordPress in VM |
| Node.js/npm | ✅ Required | ❌ | Runs Vite dev server on host |
| pnpm | ✅ Optional | ❌ | Faster npm alternative for host |
| MySQL/MariaDB | ❌ Conflicts! | ✅ Included | WordPress database in VM only |
| Nginx | ❌ Conflicts! | ✅ Included | Web server in VM only |
| PHP-FPM | ❌ Conflicts! | ✅ Included | WordPress PHP runtime in VM only |
| WP-CLI | ❌ Optional | ✅ Included | WordPress CLI (run via `trellis vm shell`) |

### Key Points

- **Host tools** are for development workflow (building assets, installing dependencies)
- **VM tools** are for running WordPress (web server, database, PHP runtime)
- Files are synced bidirectionally between host and VM via Lima
- You edit code on your host Mac, but WordPress runs inside the VM

### Compatibility Note: Laravel Valet Users

If you use Laravel Valet, you already have PHP/Composer/MySQL on your host:
- This is fine! Trellis VM uses its own isolated environment
- No need to reinstall PHP/Composer - your existing versions work
- Just be aware that local MySQL on port 3306 may conflict with some Ansible commands
- Solution: Run WP-CLI commands inside the VM via `trellis vm shell`

## Required Tools Installation

Install these tools on your Mac via Homebrew:

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Trellis CLI (required - manages the VM)
brew install roots/tap/trellis-cli

# Install Composer (required - installs PHP dependencies)
brew install composer

# Install PHP (required - runs Composer)
brew install php

# Install Node.js (required - runs Vite dev server for theme assets)
# Option 1: Via fnm (Fast Node Manager, recommended)
brew install fnm
fnm install 24  # Install Node.js 24 LTS
fnm use 24

# Option 2: Direct installation via Homebrew
# brew install node

# Install pnpm (optional but recommended - faster npm alternative)
npm install -g pnpm
```

### Notes for Laravel Valet Users

- You likely already have PHP, Composer, and MySQL installed
- No need to reinstall - your existing versions work fine
- Trellis VM runs its own isolated LEMP stack
- Only potential conflict: Local MySQL on port 3306 (see Troubleshooting section)

## SSH Key Setup

### Generate SSH Key

If you don't already have an SSH key:

```bash
# Generate new SSH key (use your email)
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Copy public key to clipboard
cat ~/.ssh/id_ed25519.pub | pbcopy
```

### Add to GitHub

1. Go to https://github.com/settings/keys
2. Click "New SSH key"
3. Paste your public key
4. Test: `ssh -T git@github.com`

### Add to Production Server (Optional)

This step can be done later when you need production access. See the project-specific setup guide for details on adding your key to production servers.

## Verification

Check that all tools are installed correctly:

```bash
trellis --version    # Should show 1.17.0+
composer --version   # Should show 2.9.0+
php --version        # Should show 8.3.0+
node --version       # Should show v24.0.0+
npm --version        # Should show 11.0.0+
pnpm --version       # Should show 10.0.0+ (if installed)
ssh -T git@github.com # Should show successful GitHub authentication
```

## How Trellis Development Works

### Development Workflow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ HOST MACHINE (macOS)                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Your Code Editor (VS Code, PHPStorm, etc.)                │
│  ↓                                                          │
│  ~/code/your-project/                                       │
│  ├── site/                                                  │
│  │   ├── composer.json     ← Composer installs here       │
│  │   └── web/app/themes/your-theme/                        │
│  │       ├── package.json  ← npm/pnpm installs here       │
│  │       ├── resources/    ← You edit CSS/JS here         │
│  │       └── public/       ← Vite builds assets here      │
│  └── trellis/              ← Trellis CLI runs here         │
│                                                             │
│  Terminal Commands:                                         │
│  • npm run dev          (Vite dev server, HMR)             │
│  • composer install     (Install PHP dependencies)         │
│  • trellis vm start     (Start VM)                         │
│  • trellis provision    (Provision VM)                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                           ↕ ↕ ↕
            Lima syncs files bidirectionally
                           ↕ ↕ ↕
┌─────────────────────────────────────────────────────────────┐
│ TRELLIS VM (Lima/Ubuntu)                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  /srv/www/your-project.test/current/    ← Synced from host │
│                                                             │
│  LEMP Stack (runs WordPress):                               │
│  • Nginx (port 80/443)      → Web server                   │
│  • PHP-FPM 8.3              → Executes WordPress PHP       │
│  • MySQL 8.0                → WordPress database           │
│  • WP-CLI                   → WordPress management         │
│                                                             │
│  Access via:                                                │
│  • trellis vm shell         (Interactive shell)            │
│  • https://your-project.test   (Web browser)               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Why Two Environments?

**Host Machine handles:**
- **Code editing:** You edit files on your Mac with your preferred editor
- **Asset building:** Vite compiles CSS/JS with HMR for instant feedback
- **Dependency management:** Composer and npm download packages locally
- **Version control:** Git operations happen on your Mac

**Trellis VM handles:**
- **WordPress runtime:** Nginx serves PHP files through PHP-FPM
- **Database:** MySQL stores WordPress content
- **WordPress core:** All WordPress PHP execution happens here
- **Production parity:** VM matches production server configuration

**Benefits:**
- **Isolated environment:** VM can't conflict with your Laravel Valet setup
- **Production parity:** VM matches production Ubuntu/Nginx/PHP versions
- **Fast development:** Edit files on Mac, see changes instantly via file sync
- **No containers:** Lima is lighter than Docker, faster than Vagrant

### Common Confusion: Do I Need Duplicate Tools?

**No!** Here's why you need each tool on the host:

- **Composer on host:** Downloads dependencies to `vendor/` which syncs to VM
  - VM also has Composer, but you run it on host for speed

- **Node.js on host:** Runs Vite dev server for HMR (hot reload)
  - VM doesn't need Node.js - it just serves the compiled assets

- **PHP on host:** Only needed to run Composer
  - WordPress doesn't run on host PHP - it runs in VM's PHP-FPM

- **No MySQL on host:** Would conflict with VM's MySQL on port 3306
  - If you have MySQL from Valet, stop it or run WP-CLI in VM

**Real-world example:**
```bash
# On HOST: Install dependencies and build assets
cd ~/code/your-project/site/web/app/themes/your-theme
pnpm install        # Host Node.js downloads packages
pnpm run dev        # Host Node.js runs Vite dev server

# Files auto-sync to VM via Lima
# WordPress in VM serves your site with the built assets

# On VM: Run WordPress commands
trellis vm shell    # Enter VM
wp cache flush      # VM's WP-CLI talks to VM's MySQL
```

## Troubleshooting

### Port 3306 Conflict (Local Database)

**Symptom:** Ansible playbooks fail with SSH connection errors

**Cause:** Local MariaDB/MySQL running on port 3306 conflicts with Trellis VM

**Solution:** Run WP-CLI commands inside Trellis VM instead:

```bash
# Instead of Ansible playbooks, use direct VM commands
trellis vm shell --workdir /srv/www/your-project.test/current

# Now run WP-CLI commands
wp db export /tmp/backup.sql.gz --path=web/wp
wp cache flush --path=web/wp
```

### VM Won't Start

**Symptom:** `trellis vm start` fails or hangs

**Solution:**

```bash
# Check Lima VM status
limactl list

# Stop and delete VM
trellis vm delete

# Start fresh
trellis vm start
trellis provision development
```

### Composer Memory Errors

**Symptom:** `composer install` fails with "Allowed memory size exhausted"

**Solution:**

```bash
# Run Composer with unlimited memory
php -d memory_limit=-1 $(which composer) install
```

## Next Steps

Now that your machine is set up for Trellis development:

1. **Clone a Trellis project:** See [PROJECT-SETUP.md](PROJECT-SETUP.md) for setting up an existing project
2. **Start a new Trellis project:** Follow the [Trellis documentation](https://roots.io/trellis/docs/installation/)
3. **Learn Trellis workflows:** Review [README.md](README.md) in the provision directory for common commands

## Resources

- **Trellis Docs:** https://roots.io/trellis/docs/
- **Trellis VM Docs:** https://roots.io/trellis/docs/trellis-vm/
- **Bedrock Docs:** https://roots.io/bedrock/docs/
- **Sage Docs:** https://roots.io/sage/docs/

## Quick Reference

```bash
# VM Management
trellis vm start                      # Start the VM
trellis vm stop                       # Stop the VM
trellis vm shell                      # SSH into VM
trellis vm delete                     # Delete VM completely
limactl list                          # List all Lima VMs

# Provisioning
trellis provision development         # Provision development environment
trellis provision --tags nginx production  # Provision specific tags

# Deployment
trellis deploy staging                # Deploy to staging
trellis deploy production             # Deploy to production

# WP-CLI via VM
trellis vm shell -- wp cli info --path=/srv/www/SITE/current/web/wp
trellis vm shell -- wp cache flush --path=/srv/www/SITE/current/web/wp
```
