# Strapi DevOps Toolkit

A collection of battle-tested scripts for managing Strapi applications across different environments (local development, legacy servers, Cloudways production).

---

## Quick Install

### From Public Repository (if repo is public)

```bash
# One-line install
curl -fsSL https://raw.githubusercontent.com/your-org/gocomm-strapi/main/scripts/install.sh | bash

# Or download and run
wget https://raw.githubusercontent.com/your-org/gocomm-strapi/main/scripts/install.sh
bash install.sh
```

### From Private Repository

```bash
# Clone the repo
git clone git@github.com:your-org/gocomm-strapi.git
cd gocomm-strapi/scripts

# Or just download the scripts folder
```

### Manual Installation

```bash
# Download scripts folder
mkdir -p ~/.strapi-toolkit
cd ~/.strapi-toolkit
# Copy scripts folder here

# Make all scripts executable
find scripts -name "*.sh" -exec chmod +x {} \;
```

---

## What's Included

### 📁 Directory Structure

```
scripts/
├── install.sh              # Installer script
├── README.md               # This file
├── WORKFLOW_EXAMPLES.md    # Common workflow examples
│
├── deploy/                 # Deployment orchestration
│   └── build-and-restart.sh
│
├── pm2/                    # PM2 process management
│   └── pm2-manager.sh
│
├── backup/                 # Data backup/restore
│   ├── export.sh
│   └── import.sh
│
├── setup/                  # Environment setup
│   ├── generate-env-keys.sh
│   └── setup-env-keys.sh
│
└── cloudways/              # Cloudways-specific utilities
    ├── fix-permissions.sh
    ├── check-ports.sh
    └── sync-to-cloudways.sh
```

---

## Common Use Cases

### 1. Export Strapi Data

```bash
bash scripts/backup/export.sh --output ./backups
```

### 2. Import Strapi Data

```bash
bash scripts/backup/import.sh --file ./backup.tar.gz
```

### 3. Upload Files to Cloudways

```bash
# Interactive mode
bash scripts/cloudways/sync-to-cloudways.sh

# Direct command
bash scripts/cloudways/sync-to-cloudways.sh \
  ./backup.tar.gz \
  --target=user@host \
  --port=22000
```

### 4. Generate Strapi Security Keys

```bash
bash scripts/setup/generate-env-keys.sh
```

### 5. Manage PM2 Process

```bash
# Check status
bash scripts/pm2/pm2-manager.sh status

# Restart
bash scripts/pm2/pm2-manager.sh restart

# View logs
bash scripts/pm2/pm2-manager.sh logs 50
```

### 6. Deploy on Server

```bash
bash scripts/deploy/build-and-restart.sh
```

---

## Environment Compatibility

| Script | macOS | Linux | Cloudways |
|--------|-------|-------|-----------|
| `backup/export.sh` | ✅ | ✅ | ✅ |
| `backup/import.sh` | ✅ | ✅ | ✅ |
| `deploy/build-and-restart.sh` | ❌ | ✅ | ✅ |
| `pm2/pm2-manager.sh` | ✅ | ✅ | ✅ |
| `setup/generate-env-keys.sh` | ✅ | ✅ | ✅ |
| `setup/setup-env-keys.sh` | ✅ | ✅ | ✅ |
| `cloudways/sync-to-cloudways.sh` | ✅ | ✅ | ✅ |
| `cloudways/fix-permissions.sh` | ❌ | ❌ | ✅ |
| `cloudways/check-ports.sh` | ❌ | ✅ | ✅ |

---

## Workflow Examples

See [WORKFLOW_EXAMPLES.md](./WORKFLOW_EXAMPLES.md) for detailed step-by-step guides on:

1. Migrating data from legacy server to Cloudways
2. Local development with production data
3. Uploading local changes to Cloudways
4. Upgrading Strapi version
5. Emergency rollback

---

## Configuration

### No Configuration Needed!

Most scripts work **atomically** - just run them with the required parameters. No setup files or profiles needed.

### Optional: Add to PATH

For easier access, add to your shell profile:

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.strapi-toolkit/scripts:$PATH"

# Then you can run scripts directly
backup/export.sh
pm2/pm2-manager.sh status
```

---

## Requirements

### All Environments
- Bash 4.0+
- Node.js (for Strapi operations)
- Git (for installer only)

### For Deployment
- NVM (Node Version Manager)
- PM2 (Process Manager)

### For File Transfer
- rsync (pre-installed on most systems)
- SSH access to target server

---

## Architecture

### Design Principles

1. **Atomic Execution**: Each script runs independently
2. **No State**: No configuration files to manage
3. **Universal**: Works across different environments
4. **Interactive**: Falls back to prompts if parameters missing
5. **Single Responsibility**: Each script does one thing well

### Environment Detection

Scripts automatically detect:
- Operating system (macOS, Linux)
- NVM location (`$HOME/.nvm` or `/home/master/.nvm`)
- Node version (from `.nvmrc`)
- PM2 configuration file (`.js` or `.cjs`)

---

## Troubleshooting

### Script Not Found

```bash
# Make sure scripts are executable
chmod +x scripts/**/*.sh
```

### NVM Not Found

```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Reload shell
source ~/.bashrc
```

### rsync: command not found (macOS)

```bash
# Install modern rsync
brew install rsync
```

### Permission Denied (Cloudways)

```bash
# Fix permissions
bash scripts/cloudways/fix-permissions.sh
```

---

## Contributing

This toolkit is designed for internal use but can be shared. If you find bugs or want to add features:

1. Test on your local environment first
2. Test on a staging server
3. Document any new features in README and WORKFLOW_EXAMPLES
4. Commit with clear messages

---

## License

Internal use for Strapi project management. Modify as needed for your team.

---

## Support

For questions or issues:
- Check WORKFLOW_EXAMPLES.md for common scenarios
- Review script help: `bash script-name.sh --help`
- Contact the development team
