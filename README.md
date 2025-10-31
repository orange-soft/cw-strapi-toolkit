# Cloudways Strapi Toolkit

A comprehensive collection of battle-tested DevOps scripts for managing Strapi applications across different environments: local development, legacy servers, and Cloudways production hosting.

---

## Table of Contents

- [Quick Install](#quick-install)
- [Update Existing Installation](#update-existing-installation)
- [What's Included](#whats-included)
- [Common Use Cases](#common-use-cases)
- [Complete Feature Documentation](#complete-feature-documentation)
  - [Backup & Restore](#1-backup--restore)
  - [Deployment & Build](#2-deployment--build)
  - [Process Management](#3-process-management)
  - [Environment Setup](#4-environment-setup)
  - [Cloudways Utilities](#5-cloudways-specific-utilities)
- [Workflow Examples](#workflow-examples)
- [Design & Architecture](#design--architecture)
- [Environment Compatibility](#environment-compatibility)
- [Troubleshooting](#troubleshooting)
- [System Requirements](#system-requirements)
- [Contributing](#contributing)

---

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash
```

**Important:** Run this from your app directory (e.g., `~/public_html` on Cloudways). This creates `./strapi-toolkit/` in the current directory.

### Why Current Directory?

This toolkit installs to `./strapi-toolkit/` (current working directory) instead of a global location like `~/.strapi-toolkit`. This design ensures compatibility with **Cloudways' multi-tenant environment** where app users are restricted to their own folders (`~/public_html/`).

---

## Update Existing Installation

**Option 1: Use the update script (recommended)**
```bash
bash strapi-toolkit/update.sh
```

**Features:**
- Shows current and latest version
- Displays changelog before updating
- Ensures exact match with repository (removes deleted files, adds new files)
- Creates automatic backup (for non-git installations)
- Handles both git-tracked and standalone installations
- Uses `git reset --hard` + `git clean -fd` for git installations

**Option 2: Re-run the installer**
```bash
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash
# Will prompt to update
```

**Option 3: Manual git pull (if .git exists)**
```bash
cd strapi-toolkit
git pull origin master
```

### Update Behavior

**Why this matters:** If a script is renamed or deleted in the repository (e.g., `old-script.sh` → `new-script.sh`), a simple `git pull` would leave both files, potentially causing confusion. Our update method ensures you always have exactly what's in the repository.

**Git-tracked Installation:**
- Modified files are updated
- New files are added
- Deleted files are removed
- No extra files remain
- No local modifications persist

**Non-git Installation:**
- Complete replacement with exact repository state
- Backup created only if NOT tracked by git (prevents clutter)

---

## What's Included

```
strapi-toolkit/
├── backup/          # Data backup and restore utilities
│   ├── export.sh    # Export Strapi database + uploads
│   └── import.sh    # Restore from backup archive
│
├── cloudways/       # Cloudways-specific tools
│   ├── sync-to-cloudways.sh   # Upload files via rsync
│   ├── fix-permissions.sh     # Fix file permissions
│   └── check-ports.sh         # Check port usage
│
├── deploy/          # Deployment orchestration
│   └── build-and-restart.sh   # Full deployment workflow
│
├── pm2/             # PM2 process management
│   └── pm2-manager.sh         # Unified PM2 interface
│
└── setup/           # Environment configuration
    ├── generate-env-keys.sh   # Generate security keys
    └── setup-env-keys.sh      # Auto-update .env file
```

---

## Common Use Cases

### 1. Backup Strapi Data

```bash
# Interactive mode (prompts for output directory)
bash strapi-toolkit/backup/export.sh

# Direct mode
bash strapi-toolkit/backup/export.sh --output ./backups
```

### 2. Restore Strapi Data

```bash
# Interactive mode
bash strapi-toolkit/backup/import.sh

# Direct mode
bash strapi-toolkit/backup/import.sh --file ./backup.tar.gz
```

### 3. Upload Files to Cloudways

```bash
# Interactive mode (no trial-and-error!)
bash strapi-toolkit/cloudways/sync-to-cloudways.sh

# Direct mode with tab completion
bash strapi-toolkit/cloudways/sync-to-cloudways.sh \
  ./backup.tar.gz \
  --target user@host \
  --port 22000
```

**Pro tips:**
- Use positional file argument for tab completion:
  ```bash
  bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./[TAB] --target user@host
  ```
- For CI/CD or if using default port 22, no need to specify `--port` (it defaults to 22)
- Set `CLOUDWAYS_PORT` environment variable for custom default port across all operations

### 4. Manage PM2 Process

```bash
# Check status
bash strapi-toolkit/pm2/pm2-manager.sh status

# Restart application
bash strapi-toolkit/pm2/pm2-manager.sh restart

# View logs (current app only)
bash strapi-toolkit/pm2/pm2-manager.sh logs 50
```

### 5. Deploy Code Updates

```bash
# Full deployment: build + restart
bash strapi-toolkit/deploy/build-and-restart.sh
```

### 6. Generate Security Keys

```bash
# Generate all Strapi security keys
bash strapi-toolkit/setup/generate-env-keys.sh
```

---

## Complete Feature Documentation

## 1. Backup & Restore

### `backup/export.sh`

**Purpose:** Export complete Strapi application data (database + uploaded files)

**Key Features:**
- Automatic NVM/Node environment detection
- Auto-detects `.nvmrc` for correct Node version
- Creates timestamped backup archives
- Includes both SQLite database and `public/uploads/` files
- Works on any environment (local, server, Cloudways)

**Usage:**

```bash
# Interactive mode (prompts for output directory)
bash strapi-toolkit/backup/export.sh

# Direct mode with specific output directory
bash strapi-toolkit/backup/export.sh --output ./backups

# Creates file like: strapi-backup-20241030-153045.tar.gz
```

**What's Included in Backup:**
- `.tmp/data.db` (SQLite database)
- `public/uploads/*` (all uploaded media files)

**Use Cases:**
- Before major updates or migrations
- Creating development snapshots
- Disaster recovery preparation
- Moving data between environments

---

### `backup/import.sh`

**Purpose:** Restore Strapi data from a backup archive

**Key Features:**
- Validates backup file integrity before importing
- Automatically stops Strapi during import (if running)
- Backs up existing data before overwriting
- Restarts application after successful import
- Environment auto-detection

**Usage:**

```bash
# Interactive mode (prompts for backup file)
bash strapi-toolkit/backup/import.sh

# Direct mode with specific backup file
bash strapi-toolkit/backup/import.sh --file ./strapi-backup-20241030-153045.tar.gz
```

**Safety Features:**
- Creates backup of current data before import
- Validates archive structure
- Atomic operation (all-or-nothing)

**Use Cases:**
- Restoring production data to local development
- Rolling back to previous state
- Cloning data between servers
- Disaster recovery

---

## 2. Deployment & Build

### `deploy/build-and-restart.sh`

**Purpose:** Zero-downtime deployment workflow - build Strapi and restart with PM2

**Key Features:**
- **Zero-downtime deployment** - App stays running during build
- Orchestrates full deployment process
- NVM environment auto-detection
- Automatic Node version switching (from `.nvmrc`)
- PM2 configuration auto-detection (`.js` or `.cjs`)
- Graceful error handling (build failures don't stop running app)

**Workflow (Zero-Downtime):**
1. Load NVM and correct Node version
2. Install dependencies (`npm ci`) - **App still running**
3. Build Strapi admin panel (`npm run build`) - **App still running**
4. Restart PM2 with new build - **Only restart after successful build**
5. Verify application is running

**Downtime:**
- Previous approach: ~60-120s (entire build time)
- **New approach: ~2-5s (just PM2 graceful restart time)** ✅

**Usage:**

```bash
# Run from your Strapi project root
bash strapi-toolkit/deploy/build-and-restart.sh
```

**Environment Detection:**
- Checks `NVM_DIR` environment variable first (parent script inheritance)
- Falls back to `$HOME/.nvm/nvm.sh` (standard location)
- Falls back to `/home/master/.nvm/nvm.sh` (Cloudways location)
- Uses system Node/NPM as last resort

**PM2 Config Detection:**
- Looks for `ecosystem.config.js` first
- Falls back to `ecosystem.config.cjs`
- Exits with error if neither found

**Use Cases:**
- Deploying code updates to server
- Rebuilding after dependency changes
- Applying configuration changes
- Standard deployment workflow

---

## 3. Process Management

### `pm2/pm2-manager.sh`

**Purpose:** Unified PM2 process management interface

**Key Features:**
- Single script for all PM2 operations
- Environment inheritance from parent scripts
- Standalone mode with auto-detection
- Real-time status and log viewing
- Works with both `.js` and `.cjs` PM2 configs

**Commands:**

```bash
# Check application status
bash strapi-toolkit/pm2/pm2-manager.sh status

# Start application
bash strapi-toolkit/pm2/pm2-manager.sh start

# Stop application
bash strapi-toolkit/pm2/pm2-manager.sh stop

# Restart application (graceful)
bash strapi-toolkit/pm2/pm2-manager.sh restart

# Delete from PM2 (complete removal)
bash strapi-toolkit/pm2/pm2-manager.sh delete

# Clean up PM2 (affects ALL apps - requires confirmation)
bash strapi-toolkit/pm2/pm2-manager.sh cleanup

# View logs for current app only (last 50 lines by default)
bash strapi-toolkit/pm2/pm2-manager.sh logs

# View more log lines
bash strapi-toolkit/pm2/pm2-manager.sh logs 200

# Note: Only shows logs for the current app, not all PM2 processes
```

**Environment Detection Logic:**
1. If `NVM_DIR` is set and `nvm` command exists → Use inherited environment (called from parent script)
2. Otherwise → Standalone mode, auto-detect NVM location

**Use Cases:**
- Quick status checks
- Manual restarts after configuration changes
- Debugging via log viewing
- Starting/stopping for maintenance

---

## 4. Environment Setup

### `setup/generate-env-keys.sh`

**Purpose:** Generate cryptographically secure keys for Strapi `.env` file

**Key Features:**
- Generates proper length keys for each Strapi requirement
- Uses OpenSSL for cryptographic randomness
- Base64 encoding for compatibility
- Generates all required keys in one command

**Keys Generated:**
- `APP_KEYS` - 32 bytes (4 keys, comma-separated)
- `API_TOKEN_SALT` - 16 bytes
- `ADMIN_JWT_SECRET` - 32 bytes
- `TRANSFER_TOKEN_SALT` - 16 bytes
- `JWT_SECRET` - 32 bytes

**Usage:**

```bash
# Generate all keys
bash strapi-toolkit/setup/generate-env-keys.sh

# Output example:
APP_KEYS=key1,key2,key3,key4
API_TOKEN_SALT=randomstring
ADMIN_JWT_SECRET=randomstring
TRANSFER_TOKEN_SALT=randomstring
JWT_SECRET=randomstring
```

**Use Cases:**
- Setting up new Strapi instances
- Rotating security keys
- Creating environment-specific configurations
- Initial project setup

---

### `setup/setup-env-keys.sh`

**Purpose:** Automatically update `.env` file with generated keys

**Key Features:**
- Interactive key generation
- Automatic `.env` file updating
- Preserves other environment variables
- Creates backup before modification

**Usage:**

```bash
# Interactive mode (generates and prompts for confirmation)
bash strapi-toolkit/setup/setup-env-keys.sh

# The script will:
# 1. Generate new keys
# 2. Show you the keys
# 3. Ask for confirmation
# 4. Backup existing .env
# 5. Update .env with new keys
```

**Safety Features:**
- Backs up `.env` to `.env.backup` before changes
- Prompts for confirmation before applying
- Validates key format

**Use Cases:**
- First-time Strapi setup
- Security key rotation
- Environment cloning setup

---

## 5. Cloudways-Specific Utilities

### `cloudways/sync-to-cloudways.sh`

**Purpose:** Upload files/directories to Cloudways server using rsync (alternative to blocked SCP)

**Key Features:**
- Interactive mode with prompts (no trial-and-error)
- SSH-style `user@host` format support
- Tab completion for file paths via positional arguments
- Automatic `public_html/` prefix (Cloudways permission structure)
- Progress tracking and transfer statistics
- Compatible with old rsync versions (macOS 2.6.9+)

**Usage:**

```bash
# Interactive mode (prompts for all inputs)
bash strapi-toolkit/cloudways/sync-to-cloudways.sh

# With tab completion! (positional file argument)
bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./backup.tar.gz --target user@host --port 22000

# All these formats work:
bash strapi-toolkit/cloudways/sync-to-cloudways.sh --file ./path --target user@host
bash strapi-toolkit/cloudways/sync-to-cloudways.sh --file=./path --target=user@host
bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./path --target user@host

# Upload to subdirectory (auto-prefixed with public_html/)
bash strapi-toolkit/cloudways/sync-to-cloudways.sh backup.tar.gz --target user@host --dest backups/
# → Uploads to: public_html/backups/

# Upload directory with verbose output
bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./my-folder/ --target user@host --verbose
```

**Parameters:**

| Parameter | Format | Description | Required | Default |
|-----------|--------|-------------|----------|---------|
| File path | `./file` or `--file ./file` | File or directory to upload | Yes | - |
| Target | `--target user@host` | SSH connection string | Yes | - |
| Port | `--port 22000` | SSH port | No | 22 (or `CLOUDWAYS_PORT` env var) |
| Destination | `--dest backups/` | Path within public_html/ | No | public_html/ |
| Verbose | `--verbose` | Show detailed output | No | false |

**Environment Variables:**
- `CLOUDWAYS_PORT`: Set default SSH port for all operations (useful for CI/CD). Can be overridden with `--port` option.

**Why rsync Instead of SCP:**
Cloudways blocks SCP for security reasons. rsync works over SSH and provides better features:
- Resume interrupted transfers
- Progress tracking
- Compression during transfer
- Directory synchronization

**Tab Completion Support:**
Using positional arguments enables shell tab completion:
```bash
bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./[TAB]
# Shell will autocomplete file paths!
```

**Use Cases:**
- Uploading backup archives to production
- Transferring local changes to Cloudways
- Syncing assets or media files
- Deploying build artifacts

**CI/CD Integration:**
For GitHub Actions or other CI/CD pipelines, set the `CLOUDWAYS_PORT` environment variable:
```yaml
# GitHub Actions example
- name: Upload to Cloudways
  env:
    CLOUDWAYS_PORT: 22  # or 22000 for custom port
  run: |
    bash strapi-toolkit/cloudways/sync-to-cloudways.sh \
      ./backup.tar.gz \
      --target ${{ secrets.CLOUDWAYS_USER }}@${{ secrets.CLOUDWAYS_HOST }}
```

If your Cloudways uses the default SSH port 22, you don't need to set `CLOUDWAYS_PORT` at all - it will default to 22.

---

### `cloudways/fix-master-permissions.sh`

**Purpose:** Fix shared resource permissions in `/home/master/` directory (ONE-TIME SETUP)

**Key Features:**
- Fixes `.npm` cache directory (group write needed for npm ci)
- Fixes `.pm2` directory (group write needed for pm2 save)
- Fixes `.config` directory (group write needed for Strapi build)
- Ensures `www-data` group has write access to shared resources
- Creates directories if they don't exist

**Usage:**

```bash
# Run ONCE as master user to fix shared resources
sudo -u master bash strapi-toolkit/cloudways/fix-master-permissions.sh
```

**What It Fixes:**
- `/home/master/.npm` → `775` (drwxrwxr-x) with www-data group
- `/home/master/.pm2` → `775` (drwxrwxr-x) with www-data group
- `/home/master/.config` → `775` (drwxrwxr-x) with www-data group

**When to Use:**
- **ONCE per Cloudways server** when setting up the first Strapi app
- When you see permission errors related to npm cache, PM2, or Strapi config
- After master user environment changes

**Why This Matters:**
On Cloudways multi-tenant servers, all apps share `/home/master/` for NVM, npm cache, and PM2. The default permissions may prevent app users (in www-data group) from writing to these shared directories.

---

### `cloudways/init-app-permissions.sh`

**Purpose:** Initialize permissions for a new app directory (ONE-TIME PER APP)

**Key Features:**
- Sets app directory to `775` with www-data group
- Recursively fixes all files (664) and directories (775)
- Sets setgid bit (`g+s`) so new files inherit www-data group
- Creates standard directories (.cache, .strapi, .tmp, node_modules)
- Fast operation on empty directories (run BEFORE first deployment)

**Usage:**

```bash
# Run ONCE per app, BEFORE first deployment
cd ~/public_html/your-app
bash strapi-toolkit/cloudways/init-app-permissions.sh
```

**What It Fixes:**
- App root: `775` (drwxrwxr-x) + setgid bit
- All directories: `775` (drwxrwxr-x) + setgid bit
- All files: `664` (rw-rw-r--)
- Group: www-data on everything

**When to Use:**
- **ONCE per app** immediately after Cloudways creates the app directory
- BEFORE running your first deployment
- When you clone a new app from git

**Why This Matters:**
Cloudways creates `public_html/app-name` with potentially restrictive permissions. Running this script early (when the directory is mostly empty) ensures:
1. Fast execution (seconds, not minutes)
2. All future files inherit correct permissions via setgid bit
3. No permission errors during npm ci or PM2 operations

**Performance Note:**
Running this on a directory with thousands of files (after deployment) takes a long time. Always run BEFORE first deployment when the directory is empty or has minimal files.

---

### `cloudways/check-ports.sh`

**Purpose:** Verify which ports are in use and available

**Key Features:**
- Shows all listening ports
- Identifies process using each port
- Helps diagnose port conflicts
- Useful for multiple Node applications

**Usage:**

```bash
# Check all ports
bash strapi-toolkit/cloudways/check-ports.sh

# Output shows:
# - Port number
# - Process name
# - PID
```

**Use Cases:**
- Diagnosing "port already in use" errors
- Planning port allocation for multiple apps
- Verifying application is listening
- Troubleshooting deployment issues

---

## Workflow Examples

Complete step-by-step guides for common scenarios.

### Workflow 1: Migrate Production Data to Local Development

```bash
# 1. On production server - Export data
cd ~/public_html
bash strapi-toolkit/backup/export.sh --output .

# 2. Download backup to local machine
scp -P 22000 user@host:~/public_html/strapi-backup-*.tar.gz ./

# 3. On local machine - Import data
cd ~/projects/my-strapi-app
bash strapi-toolkit/backup/import.sh --file ./strapi-backup-*.tar.gz

# 4. Start local development
npm run develop
```

---

### Workflow 2: Deploy Code Updates to Cloudways

```bash
# 1. On local machine - Create backup first (safety)
bash strapi-toolkit/backup/export.sh --output ./backups

# 2. Upload backup to Cloudways (optional safety measure)
bash strapi-toolkit/cloudways/sync-to-cloudways.sh \
  ./backups/strapi-backup-*.tar.gz \
  --target user@host \
  --port 22000 \
  --dest backups/

# 3. On local - Push code changes
git add .
git commit -m "Update feature X"
git push origin master

# 4. On Cloudways - Pull and deploy
cd ~/public_html
git pull origin master
bash strapi-toolkit/deploy/build-and-restart.sh

# 5. Verify deployment
bash strapi-toolkit/pm2/pm2-manager.sh status
bash strapi-toolkit/pm2/pm2-manager.sh logs 50
```

---

### Workflow 3: Fresh Strapi Setup on New Server

```bash
# 1. Install toolkit
cd ~/public_html
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash

# 2. Clone your Strapi project
git clone git@github.com:your-org/your-strapi-app.git .

# 3. Generate security keys
bash strapi-toolkit/setup/generate-env-keys.sh > temp-keys.txt

# 4. Create .env file
cp .env.example .env
# Edit .env and add the generated keys from temp-keys.txt

# 5. Deploy application
bash strapi-toolkit/deploy/build-and-restart.sh

# 6. Verify
bash strapi-toolkit/pm2/pm2-manager.sh status
```

---

### Workflow 4: Upload Local Changes Without Git

```bash
# Scenario: You have local file changes you want to test on Cloudways
# without committing to git

# 1. Create archive of changes
tar -czf my-changes.tar.gz src/ config/ public/

# 2. Upload to Cloudways
bash strapi-toolkit/cloudways/sync-to-cloudways.sh \
  my-changes.tar.gz \
  --target user@host \
  --port 22000

# 3. On Cloudways - Extract and deploy
cd ~/public_html
tar -xzf my-changes.tar.gz
bash strapi-toolkit/deploy/build-and-restart.sh

# 4. Fix permissions (if needed)
bash strapi-toolkit/cloudways/fix-permissions.sh
```

---

### Workflow 5: Emergency Rollback

```bash
# Scenario: Deployment broke production, need to rollback

# 1. On Cloudways - Import last known good backup
cd ~/public_html
bash strapi-toolkit/backup/import.sh \
  --file ./backups/strapi-backup-20241029-*.tar.gz

# 2. Rollback code via git
git log --oneline  # Find last good commit
git reset --hard abc123  # Replace with actual commit hash

# 3. Rebuild and restart
bash strapi-toolkit/deploy/build-and-restart.sh

# 4. Verify recovery
bash strapi-toolkit/pm2/pm2-manager.sh status
bash strapi-toolkit/pm2/pm2-manager.sh logs 100
```

---

### Workflow 6: Complete Deployment Workflow

```bash
# 1. On local - Export data (safety backup)
bash strapi-toolkit/backup/export.sh --output ./backups

# 2. Upload backup to Cloudways
bash strapi-toolkit/cloudways/sync-to-cloudways.sh \
  ./backups/strapi-backup-*.tar.gz \
  --target user@host \
  --port 22000 \
  --dest backups/

# 3. On local - Commit and push code
git add .
git commit -m "Update feature X"
git push origin master

# 4. On Cloudways - Pull and deploy
cd ~/public_html
git pull origin master
bash strapi-toolkit/deploy/build-and-restart.sh

# 5. Verify deployment
bash strapi-toolkit/pm2/pm2-manager.sh status
bash strapi-toolkit/pm2/pm2-manager.sh logs 50
```

---

## Design & Architecture

### Design Principles

1. **Atomic Execution** - Each script runs independently without saved state
2. **Environment Agnostic** - Auto-detects macOS, Linux, and Cloudways environments
3. **Interactive by Default** - Prompts for missing parameters (no trial-and-error)
4. **Single Responsibility** - Each script does one thing well
5. **Multi-tenant Compatible** - Works in Cloudways' restricted environment

### Environment Auto-Detection

All scripts automatically detect:
- **NVM location** - `$HOME/.nvm` or `/home/master/.nvm` (Cloudways)
- **Node version** - Reads from `.nvmrc` file
- **PM2 config** - Supports both `.js` and `.cjs` formats
- **Operating system** - Adapts to macOS and Linux differences

### Architecture Diagrams

#### Deployment Workflow

```
build-and-restart.sh
    │
    ├─→ Detect NVM location
    ├─→ Load NVM + Node version
    ├─→ Call pm2-manager.sh stop
    │       └─→ Inherits environment (no re-detection)
    ├─→ npm install
    ├─→ npm run build
    └─→ Call pm2-manager.sh restart
            └─→ Inherits environment
```

#### Backup/Restore Workflow

```
export.sh                          import.sh
    │                                  │
    ├─→ Detect environment             ├─→ Validate backup file
    ├─→ Load NVM + Node                ├─→ Backup current data
    ├─→ Create temp directory          ├─→ Stop Strapi (pm2-manager.sh)
    ├─→ Copy database                  ├─→ Extract archive
    ├─→ Copy uploads/                  ├─→ Restore database
    ├─→ Create tar.gz                  ├─→ Restore uploads/
    └─→ Cleanup                        └─→ Restart Strapi
```

#### File Upload Workflow

```
sync-to-cloudways.sh
    │
    ├─→ Parse arguments (positional + flags)
    ├─→ Interactive prompts (if missing params)
    ├─→ Parse user@host format
    ├─→ Add public_html/ prefix
    ├─→ Confirm with user
    ├─→ rsync -az --progress -e "ssh -p PORT"
    └─→ Show summary statistics
```

### Key Technical Decisions

#### 1. Current Directory Installation

**Decision:** Install to `./strapi-toolkit/` instead of `~/.strapi-toolkit`

**Reason:** Cloudways uses a multi-tenant environment where app users are restricted to their own `~/public_html/` folder. They cannot access global directories.

**Impact:** Users must install the toolkit in each project directory. This is intentional and necessary for Cloudways compatibility.

#### 2. Atomic Script Execution

**Decision:** No configuration files, profiles, or saved state

**Reason:** Cloudways environment requires on-the-fly script execution. Each script runs independently with all parameters provided at runtime.

**Impact:** Scripts are longer (include environment detection), but universally portable.

#### 3. Parent-Child Environment Inheritance

**Decision:** Child scripts detect if parent already loaded environment (NVM/Node)

**Reason:** Optimization - avoid duplicate NVM loading when scripts call other scripts

**Example:**
- `deploy/build-and-restart.sh` loads NVM once
- Calls `pm2/pm2-manager.sh` which detects NVM already loaded
- Skips redundant environment setup

#### 4. Tab Completion Support

**Decision:** Support positional arguments (not just `--flag=value`)

**Reason:** Shell tab completion only works with positional arguments

**Example:**
```bash
# Tab completion works
bash sync-to-cloudways.sh ./[TAB]

# No tab completion
bash sync-to-cloudways.sh --file=./[TAB]
```

#### 5. Git Submodule Compatibility

**Important:** The toolkit always removes the `.git` folder after installation and updates.

**Why?** If `strapi-toolkit/.git` exists, git will treat it as a submodule, causing:
- `git status` shows "modified: strapi-toolkit" constantly
- `git add .` doesn't work as expected
- Deployment scripts get confused
- Team members see different states

**Our solution:**
- Remove `.git` after every install/update
- Toolkit becomes regular files in your repo
- No submodule conflicts
- Can commit toolkit with your project (optional)

---

## Environment Compatibility

| Script | macOS | Linux | Cloudways | Notes |
|--------|-------|-------|-----------|-------|
| `backup/export.sh` | ✅ | ✅ | ✅ | Universal |
| `backup/import.sh` | ✅ | ✅ | ✅ | Universal |
| `deploy/build-and-restart.sh` | ⚠️ | ✅ | ✅ | Requires PM2 |
| `pm2/pm2-manager.sh` | ✅ | ✅ | ✅ | Universal (if PM2 installed) |
| `setup/generate-env-keys.sh` | ✅ | ✅ | ✅ | Universal |
| `setup/setup-env-keys.sh` | ✅ | ✅ | ✅ | Universal |
| `cloudways/sync-to-cloudways.sh` | ✅ | ✅ | ✅ | Universal (requires rsync) |
| `cloudways/fix-permissions.sh` | ❌ | ❌ | ✅ | Cloudways only |
| `cloudways/check-ports.sh` | ⚠️ | ✅ | ✅ | Linux/Cloudways |

**Legend:** ✅ Fully supported | ⚠️ Partial support | ❌ Not applicable

---

## Troubleshooting

### Issue: "NVM not found"

**Symptoms:** Scripts can't find Node/NVM

**Solutions:**
```bash
# Check if NVM is installed
command -v nvm

# Install NVM if missing
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Or use system Node
which node npm
```

### Issue: "PM2 config not found"

**Symptoms:** `deploy/build-and-restart.sh` fails

**Solution:**
```bash
# Ensure you have a PM2 config file
ls ecosystem.config.*

# Create one if missing
npm install -g pm2
pm2 ecosystem  # Generates ecosystem.config.js
```

### Issue: "Permission denied" on Cloudways

**Symptoms:** Can't write files, execute scripts

**Solution:**
```bash
# Fix permissions
bash strapi-toolkit/cloudways/fix-permissions.sh

# Check ownership
ls -la

# Ensure you're the app user
whoami
```

### Issue: PM2 "invalid PID" errors

**Symptoms:**
```
PM2 | Error caught while calling pidusage
PM2 | TypeError: One of the pids provided is invalid
```

**Cause:** PM2 has stale process metadata from previous processes that no longer exist. Common on multi-tenant servers like Cloudways.

**Solution:**
```bash
# Option 1: Graceful restart (recommended - current app only)
bash strapi-toolkit/pm2/pm2-manager.sh restart

# Option 2: Delete and start fresh (current app only)
bash strapi-toolkit/pm2/pm2-manager.sh delete
bash strapi-toolkit/pm2/pm2-manager.sh start

# Option 3: Clean up all PM2 processes (affects ALL apps - requires confirmation)
bash strapi-toolkit/pm2/pm2-manager.sh cleanup
```

**Prevention:** The `restart` command uses graceful restart which handles stale processes automatically.

### Issue: "Port already in use"

**Symptoms:** Application won't start

**Solution:**
```bash
# Check what's using the port
bash strapi-toolkit/cloudways/check-ports.sh

# Kill conflicting process
pm2 list
pm2 delete all  # or specific app name

# Or change port in .env
PORT=1338  # Different port
```

### Issue: rsync version incompatibility

**Symptoms:** rsync fails with "unknown option"

**Solution:**
```bash
# Check rsync version
rsync --version

# On macOS, install modern rsync
brew install rsync

# Script already uses compatible flags for old versions
```

### Issue: Tab completion doesn't work

**Cause:** Using `--file=` format instead of positional argument

**Solution:**
```bash
# No tab completion
bash strapi-toolkit/cloudways/sync-to-cloudways.sh --file=./[TAB]

# Tab completion works
bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./[TAB]
```

### Issue: Script Not Found

```bash
# Make scripts executable
chmod +x strapi-toolkit/**/*.sh
```

---

## System Requirements

### All Environments
- Bash 4.0+
- Git (for installation only)
- Node.js (for Strapi operations)

### For Deployment Scripts
- NVM (Node Version Manager) - Recommended
- PM2 (Process Manager for Node.js)
- `.nvmrc` file in project root (optional but recommended)

### For File Transfer
- rsync (pre-installed on most Unix systems)
- SSH access to target server
- SSH key authentication configured

### Cloudways Specific
- App user access (restricted to `~/public_html/`)
- SSH port (usually custom, e.g., 22000)

---

## Security Considerations

### Generated Keys
- All keys use OpenSSL with cryptographic randomness
- 32-byte keys provide 256-bit security
- Keys are base64-encoded for environment file compatibility

### File Transfers
- Uses SSH for encrypted transfers
- Supports SSH key authentication (no password needed)
- Validates file paths before transfer
- Confirms with user before uploading

### Backup Files
- Contain sensitive database information
- Should be stored securely
- Add to `.gitignore` if in project directory
- Consider encrypting backup archives for long-term storage

### Environment Files
- Never commit `.env` files to git
- Rotate keys periodically (especially after team member changes)
- Use different keys per environment (dev/staging/production)

---

## Contributing

This toolkit is designed for team use. To add features:

1. Test on multiple environments (local, Linux server, Cloudways)
2. Follow existing patterns (atomic, interactive, auto-detection)
3. Update all documentation
4. Commit with clear messages

### Adding New Scripts

1. **Choose appropriate category folder:**
   - `backup/` - Data operations
   - `cloudways/` - Hosting-specific
   - `deploy/` - Build and deployment
   - `pm2/` - Process management
   - `setup/` - Configuration
   - `utils/` - Shared utilities

2. **Follow naming conventions:**
   - Use kebab-case: `my-new-script.sh`
   - Descriptive, verb-based names

3. **Script structure template:**
```bash
#!/bin/bash
set -e

# Script: My New Script
# Description: What it does
# Usage: ./my-new-script.sh [OPTIONS]

# Error handler
error_exit() {
  echo "Error: $1"
  exit 1
}

# Show usage
show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]
...
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) show_usage ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Main logic here
```

4. **Add documentation:**
   - Update this README.md with new features
   - Include usage examples
   - Add to workflow examples if applicable

### Contributing Guidelines

1. Test on multiple environments (local, Linux server, Cloudways)
2. Make scripts atomic (no dependencies on config files)
3. Add interactive mode for all required parameters
4. Include error handling and validation
5. Follow existing code style and patterns

---

## FAQ

**Q: Why install to current directory instead of `~/.strapi-toolkit`?**
A: Cloudways uses a multi-tenant environment where app users can't access locations outside their app folder (`~/public_html/`). Installing to the current directory ensures compatibility.

**Q: Can I use this toolkit with other hosting providers?**
A: Yes! Most scripts work universally. Only `cloudways/fix-permissions.sh` is Cloudways-specific. Other hosts might have different SSH ports or paths.

**Q: Do I need to install the toolkit on my local machine too?**
A: Yes, if you want to use backup/restore locally or upload files to servers. The toolkit works everywhere.

**Q: What if my project uses PostgreSQL instead of SQLite?**
A: You'll need to modify `backup/export.sh` and `backup/import.sh` to use `pg_dump` and `pg_restore` instead of copying `.tmp/data.db`. This is a planned enhancement.

**Q: Can I customize the scripts for my specific needs?**
A: Absolutely! Fork the repository and modify as needed. The scripts are designed to be readable and maintainable.

**Q: How do I update the toolkit after installation?**
A: Run `bash strapi-toolkit/update.sh` or re-run the installer.

**Q: Why use PM2 instead of systemd or other process managers?**
A: PM2 is the standard for Node.js applications and works across all environments. Cloudways uses PM2 by default.

**Q: Can these scripts run in CI/CD pipelines?**
A: Yes! Use non-interactive mode by providing all parameters via command-line arguments. The scripts won't prompt if all required params are supplied.

---

## Getting Help

### Quick Reference
- Run any script with `--help` for usage information
- Check the relevant section above for detailed documentation
- Review workflow examples for your use case

### Reporting Issues
- GitHub Issues: `https://github.com/orange-soft/cw-strapi-toolkit/issues`
- Include: Script name, error message, environment details (macOS/Linux/Cloudways)

---

## Key Features Highlights

- ✅ **Zero Configuration** - No config files or profiles needed
- ✅ **Interactive Mode** - Prompts for missing parameters
- ✅ **Tab Completion** - Supports shell autocomplete for file paths
- ✅ **Environment Detection** - Works everywhere automatically
- ✅ **Safety First** - Backs up before destructive operations
- ✅ **Cloudways Compatible** - Designed for multi-tenant restrictions
- ✅ **Comprehensive Docs** - Every feature fully documented
- ✅ **Zero Downtime** - Smart deployment process minimizes downtime

---

## License

Internal use for Strapi project management. Modify as needed for your team.

---

**Version:** 1.0.0
**Last Updated:** October 2024
**Compatibility:** Strapi v4+
**Repository:** https://github.com/orange-soft/cw-strapi-toolkit
