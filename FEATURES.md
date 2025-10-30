# Cloudways Strapi Toolkit - Feature Documentation

## Overview

The Cloudways Strapi Toolkit is a comprehensive collection of battle-tested DevOps scripts designed specifically for managing Strapi applications across multiple environments: local development, legacy servers, and Cloudways production hosting.

### Design Philosophy

1. **Atomic Execution** - Each script runs independently without requiring configuration files or saved state
2. **Environment Agnostic** - Automatically detects and adapts to different environments (macOS, Linux, Cloudways)
3. **Interactive by Default** - Falls back to prompts if parameters are missing, eliminating trial-and-error
4. **Single Responsibility** - Each script does one thing well
5. **Multi-tenant Compatible** - Works within Cloudways' restricted app user environment

---

## Installation

### Quick Install

The toolkit installs to the **current working directory** (not a global location), making it compatible with Cloudways' multi-tenant environment where app users are restricted to their own folders.

```bash
# Navigate to your app directory
cd ~/public_html

# Install toolkit
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash

# This creates: ./strapi-toolkit/
```

### What Gets Installed

```
strapi-toolkit/
├── backup/          # Data backup and restore
├── cloudways/       # Cloudways-specific utilities
├── deploy/          # Deployment orchestration
├── pm2/             # PM2 process management
├── setup/           # Environment configuration
└── utils/           # Shared utilities (future)
```

### Update Existing Installation

The toolkit provides multiple update methods:

**Method 1: Update Script (Recommended)**
```bash
bash strapi-toolkit/update.sh
```

**Features:**
- Shows current and latest version
- Displays changelog before updating
- **Ensures exact match with repository** (removes deleted files, adds new files)
- Creates automatic backup (for non-git installations)
- Handles both git-tracked and standalone installations
- Uses `git reset --hard` + `git clean -fd` for git installations (removes local modifications)

**Method 2: Re-run Installer**
```bash
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash
```
The installer detects existing installation and prompts to update.

**Method 3: Manual Git Pull**
```bash
cd strapi-toolkit
git pull origin master
```
Only works if the toolkit was installed with git tracking intact.

### Update Behavior Details

**Git-tracked Installation:**
```bash
git fetch origin master
git reset --hard origin/master  # Ensures exact match
git clean -fd                    # Removes untracked files
```

This guarantees:
- ✅ Modified files are updated
- ✅ New files are added
- ✅ Deleted files are removed
- ✅ No extra files remain
- ✅ No local modifications persist

**Non-git Installation:**
```bash
rm -rf strapi-toolkit           # Complete removal
git clone --depth 1 [repo]      # Fresh download
rm -rf strapi-toolkit/.git      # Remove git metadata
```

This guarantees:
- ✅ Complete replacement with exact repository state
- ✅ Backup created before removal

**Why this matters:**
If a script is renamed or deleted in the repository (e.g., `old-script.sh` → `new-script.sh`), a simple `git pull` would leave both files, potentially causing confusion or using outdated scripts. Our update method ensures you always have exactly what's in the repository.

### Git Submodule Compatibility

**Important:** The toolkit **always removes the `.git` folder** after installation and updates.

**Why?**
```bash
# Your project structure:
my-strapi-app/              ← Your git repo
├── .git/                   ← Your repo's git
└── strapi-toolkit/
    └── .git/               ← ❌ Would cause submodule conflicts!
```

If `strapi-toolkit/.git` exists, git will treat it as a submodule, causing:
- ❌ `git status` shows "modified: strapi-toolkit" constantly
- ❌ `git add .` doesn't work as expected
- ❌ Deployment scripts get confused
- ❌ Team members see different states

**Our solution:**
- ✅ Remove `.git` after every install/update
- ✅ Toolkit becomes regular files in your repo
- ✅ No submodule conflicts
- ✅ Can commit toolkit with your project (optional)

**Update process:**
1. Use `.git` temporarily for smart updates (fetch, reset, clean)
2. Remove `.git` immediately after update
3. Next update detects no `.git`, does full replacement

This gives you the **best of both worlds**:
- Smart git-based updates when `.git` exists
- Clean file structure without submodule issues

---

## Feature Categories

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

**Purpose:** Complete deployment workflow - build Strapi and restart with PM2

**Key Features:**
- Orchestrates full deployment process
- NVM environment auto-detection
- Automatic Node version switching (from `.nvmrc`)
- PM2 configuration auto-detection (`.js` or `.cjs`)
- Graceful error handling with rollback capability

**Workflow:**
1. Load NVM and correct Node version
2. Stop PM2 process
3. Install dependencies (`npm install`)
4. Build Strapi admin panel (`npm run build`)
5. Restart PM2 process
6. Verify application is running

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

# Restart application (with automatic cleanup)
bash strapi-toolkit/pm2/pm2-manager.sh restart

# Clean up PM2 (fixes "invalid PID" errors)
bash strapi-toolkit/pm2/pm2-manager.sh cleanup

# Delete from PM2 (complete removal)
bash strapi-toolkit/pm2/pm2-manager.sh delete

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

**Design Note:**
Extracted from `build-and-restart.sh` following Single Responsibility Principle. Can be called independently or as a child process from deployment scripts.

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

### `cloudways/fix-permissions.sh`

**Purpose:** Fix file permissions for Cloudways environment

**Key Features:**
- Sets correct ownership for app user
- Fixes directory permissions (755)
- Fixes file permissions (644)
- Makes specific scripts executable

**Usage:**

```bash
# Run from app root directory on Cloudways server
bash strapi-toolkit/cloudways/fix-permissions.sh
```

**What It Fixes:**
- Directory permissions: `755` (rwxr-xr-x)
- File permissions: `644` (rw-r--r--)
- Script files: `755` (executable)
- Ownership: App user and group

**When to Use:**
- After uploading files via rsync/SFTP
- After git pull operations
- When encountering permission errors
- After extracting archives

**Cloudways Specific:**
Only works on Cloudways servers where the app user has proper permissions. Not applicable for local development or other hosting environments.

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

## 6. Advanced Features

### Environment Auto-Detection

All scripts automatically detect the execution environment:

**NVM Detection Priority:**
1. Inherit from parent (if `NVM_DIR` set and `nvm` command exists)
2. Standard location: `$HOME/.nvm/nvm.sh`
3. Cloudways location: `/home/master/.nvm/nvm.sh`
4. Fallback to system Node/NPM

**Node Version Selection:**
- Reads `.nvmrc` if present
- Uses specified version via `nvm use`
- Falls back to system default if `.nvmrc` missing

**PM2 Configuration Detection:**
- Checks for `ecosystem.config.js`
- Falls back to `ecosystem.config.cjs`
- Reports error if neither found

### Parent-Child Script Optimization

Scripts are designed to work both **standalone** and as **child processes**:

**Example:**
```bash
# deploy/build-and-restart.sh loads NVM once
# Then calls: pm2/pm2-manager.sh

# pm2-manager.sh detects NVM already loaded
# Skips redundant environment setup
```

This prevents duplicate environment setup and improves performance.

---

## Architecture Diagrams

### Deployment Workflow

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

### Backup/Restore Workflow

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

### File Upload Workflow

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

---

## Environment Compatibility Matrix

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
| `cloudways/check-ports.sh` | ⚠️ | ✅ | ✅ | Linux/Cloudways only |

**Legend:**
- ✅ Fully supported
- ⚠️ Partial support or specific requirements
- ❌ Not applicable

---

## Common Workflows

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
# Option 1: Automatic cleanup (recommended)
bash strapi-toolkit/pm2/pm2-manager.sh restart
# This now includes automatic cleanup

# Option 2: Manual cleanup
bash strapi-toolkit/pm2/pm2-manager.sh cleanup
# Then start your app
bash strapi-toolkit/pm2/pm2-manager.sh start
```

**Prevention:** The `restart` command now automatically cleans up stale processes before starting fresh.

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
# ❌ No tab completion
bash strapi-toolkit/cloudways/sync-to-cloudways.sh --file=./[TAB]

# ✅ Tab completion works
bash strapi-toolkit/cloudways/sync-to-cloudways.sh ./[TAB]
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

## Extending the Toolkit

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
   - Update `README.md`
   - Add to `FEATURES.md` (this file)
   - Include in `WORKFLOW_EXAMPLES.md` if applicable

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
A: Run the installer again, or `cd strapi-toolkit && git pull origin master`

**Q: Why use PM2 instead of systemd or other process managers?**
A: PM2 is the standard for Node.js applications and works across all environments. Cloudways uses PM2 by default.

**Q: Can these scripts run in CI/CD pipelines?**
A: Yes! Use non-interactive mode by providing all parameters via command-line arguments. The scripts won't prompt if all required params are supplied.

---

## Support and Resources

### Documentation
- **README.md** - Quick start and installation
- **FEATURES.md** - This comprehensive feature guide
- **WORKFLOW_EXAMPLES.md** - Step-by-step workflow examples

### Getting Help
- Check script help: `bash script-name.sh --help`
- Review workflow examples for your use case
- Check troubleshooting section above

### Reporting Issues
- GitHub Issues: `https://github.com/orange-soft/cw-strapi-toolkit/issues`
- Include: Script name, error message, environment details

### Version Information
- Current Version: 1.0.0
- Last Updated: October 2024
- Compatibility: Strapi v4+

---

## License

Internal use for Strapi project management. Modify as needed for your team.

---

## Credits

Developed for managing Strapi applications across development, staging, and production environments with a focus on Cloudways hosting platform compatibility.
