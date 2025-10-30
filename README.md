# Cloudways Strapi Toolkit

A comprehensive collection of battle-tested DevOps scripts for managing Strapi applications across different environments: local development, legacy servers, and Cloudways production hosting.

## 🚀 Quick Install

```bash
# Navigate to your app directory (important for Cloudways!)
cd ~/public_html

# Install toolkit to current directory
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash

# This creates: ./strapi-toolkit/
```

### Why Current Directory?

This toolkit installs to `./strapi-toolkit/` (current working directory) instead of a global location like `~/.strapi-toolkit`. This design ensures compatibility with **Cloudways' multi-tenant environment** where app users are restricted to their own folders (`~/public_html/`).

### Update Existing Installation

```bash
cd strapi-toolkit
git pull origin master
```

---

## 📚 Documentation

- **[README.md](./README.md)** - This quick start guide
- **[FEATURES.md](./FEATURES.md)** - Comprehensive feature documentation (START HERE for detailed info)
- **[WORKFLOW_EXAMPLES.md](./WORKFLOW_EXAMPLES.md)** - Step-by-step workflow examples

---

## 📁 What's Included

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

## 🎯 Common Use Cases

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

# View logs
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

## 🌍 Environment Compatibility

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

## 📖 Complete Workflows

See **[WORKFLOW_EXAMPLES.md](./WORKFLOW_EXAMPLES.md)** for detailed step-by-step guides:

1. **Migrate production data to local development**
2. **Deploy code updates to Cloudways**
3. **Fresh Strapi setup on new server**
4. **Upload local changes without git**
5. **Emergency rollback procedure**

---

## ⚙️ Design Principles

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

---

## 🔧 System Requirements

### All Environments
- Bash 4.0+
- Git (for installation only)
- Node.js (for Strapi operations)

### For Deployment Scripts
- NVM (Node Version Manager) - Recommended
- PM2 (Process Manager for Node.js)
- `.nvmrc` file in project root (optional)

### For File Transfer
- rsync (pre-installed on most systems)
- SSH access to target server
- SSH key authentication configured

---

## 🚨 Troubleshooting

### Script Not Found
```bash
# Make scripts executable
chmod +x strapi-toolkit/**/*.sh
```

### NVM Not Found
```bash
# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
```

### Permission Denied (Cloudways)
```bash
# Fix file permissions
bash strapi-toolkit/cloudways/fix-permissions.sh
```

### Port Already in Use
```bash
# Check what's using ports
bash strapi-toolkit/cloudways/check-ports.sh

# Stop conflicting process
bash strapi-toolkit/pm2/pm2-manager.sh stop
```

### rsync Not Found (macOS)
```bash
# Install modern rsync
brew install rsync
```

**More troubleshooting?** See **[FEATURES.md](./FEATURES.md#troubleshooting)** for comprehensive solutions.

---

## 📝 Example: Complete Deployment Workflow

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

## 🎓 Getting Help

### Quick Reference
- Run any script with `--help` for usage information
- Check **[FEATURES.md](./FEATURES.md)** for detailed feature documentation
- Review **[WORKFLOW_EXAMPLES.md](./WORKFLOW_EXAMPLES.md)** for step-by-step guides

### Key Sections in FEATURES.md
- Backup & Restore - Complete guide to data operations
- Deployment - Build and deployment workflows
- Process Management - PM2 operations
- Environment Setup - Security key generation
- Cloudways Utilities - File uploads and permissions
- Architecture Diagrams - Visual workflow explanations
- Common Workflows - Real-world usage scenarios
- FAQ - Frequently asked questions

### Reporting Issues
- GitHub Issues: `https://github.com/orange-soft/cw-strapi-toolkit/issues`
- Include: Script name, error message, environment details (macOS/Linux/Cloudways)

---

## 🤝 Contributing

This toolkit is designed for team use. To add features:

1. Test on multiple environments (local, Linux server, Cloudways)
2. Follow existing patterns (atomic, interactive, auto-detection)
3. Update all documentation (README, FEATURES, WORKFLOW_EXAMPLES)
4. Commit with clear messages

See **[FEATURES.md#extending-the-toolkit](./FEATURES.md#extending-the-toolkit)** for detailed guidelines.

---

## 📄 License

Internal use for Strapi project management. Modify as needed for your team.

---

## 🏆 Key Features Highlights

- ✅ **Zero Configuration** - No config files or profiles needed
- ✅ **Interactive Mode** - Prompts for missing parameters
- ✅ **Tab Completion** - Supports shell autocomplete for file paths
- ✅ **Environment Detection** - Works everywhere automatically
- ✅ **Safety First** - Backs up before destructive operations
- ✅ **Cloudways Compatible** - Designed for multi-tenant restrictions
- ✅ **Comprehensive Docs** - Every feature fully documented

---

**Version:** 1.0.0
**Last Updated:** October 2024
**Compatibility:** Strapi v4+

For detailed feature documentation, see **[FEATURES.md](./FEATURES.md)**
