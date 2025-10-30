# Team Handoff Document - Cloudways Strapi Toolkit

**Date:** October 30, 2024
**Version:** 1.0.0
**Status:** Ready for GitHub publication and team usage

---

## 📦 What Is This?

The **Cloudways Strapi Toolkit** is a standalone collection of DevOps automation scripts designed specifically for managing Strapi applications across multiple environments:

- **Local Development** (macOS/Linux)
- **Legacy Servers** (self-hosted Linux)
- **Cloudways Production** (managed hosting)

This toolkit was extracted from the `gocomm-strapi` project to create a **reusable, shareable solution** that any team can use across multiple Strapi projects.

---

## 🎯 Key Design Decisions

### 1. Current Directory Installation

**Decision:** Install to `./strapi-toolkit/` (current directory) instead of `~/.strapi-toolkit` (home directory)

**Reason:** Cloudways uses a multi-tenant environment where app users are restricted to their own `~/public_html/` folder. They cannot access global directories outside their app folder.

**Impact:** Users must install the toolkit in each project directory. This is intentional and necessary for Cloudways compatibility.

### 2. Atomic Script Execution

**Decision:** No configuration files, profiles, or saved state

**Reason:** Cloudways environment requires on-the-fly script execution. Each script runs independently with all parameters provided at runtime.

**Impact:** Scripts are longer (include environment detection), but universally portable.

### 3. Interactive by Default

**Decision:** Scripts prompt for missing parameters instead of failing

**Reason:** Eliminates trial-and-error. Users can run scripts without remembering exact syntax.

**Impact:** Scripts work in both interactive (human) and non-interactive (CI/CD) modes.

### 4. Parent-Child Environment Inheritance

**Decision:** Child scripts detect if parent already loaded environment (NVM/Node)

**Reason:** Optimization - avoid duplicate NVM loading when scripts call other scripts

**Example:**
- `deploy/build-and-restart.sh` loads NVM once
- Calls `pm2/pm2-manager.sh` which detects NVM already loaded
- Skips redundant environment setup

### 5. Tab Completion Support

**Decision:** Support positional arguments (not just `--flag=value`)

**Reason:** Shell tab completion only works with positional arguments

**Example:**
```bash
# ✅ Tab completion works
bash sync-to-cloudways.sh ./[TAB]

# ❌ No tab completion
bash sync-to-cloudways.sh --file=./[TAB]
```

---

## 📁 Repository Structure

```
cw-strapi-toolkit/
├── .gitignore                    # Comprehensive ignore patterns
├── README.md                     # Quick start guide (user-facing)
├── FEATURES.md                   # Complete feature documentation
├── WORKFLOW_EXAMPLES.md          # Step-by-step usage examples
├── TEAM_HANDOFF.md              # This file (internal team docs)
│
├── install.sh                    # Main installer script
├── bootstrap-install.sh          # Alternative installer (for private repos)
│
├── backup/
│   ├── export.sh                 # Export Strapi data (DB + uploads)
│   └── import.sh                 # Restore from backup archive
│
├── cloudways/
│   ├── sync-to-cloudways.sh      # Upload files via rsync (SCP alternative)
│   ├── fix-permissions.sh        # Fix file permissions on Cloudways
│   └── check-ports.sh            # Check port usage
│
├── deploy/
│   └── build-and-restart.sh      # Full deployment workflow
│
├── pm2/
│   └── pm2-manager.sh            # Unified PM2 interface
│
└── setup/
    ├── generate-env-keys.sh      # Generate Strapi security keys
    └── setup-env-keys.sh         # Auto-update .env file
```

---

## 📚 Documentation Structure

### For End Users (Developers/DevOps)

1. **README.md** - Start here
   - Quick installation
   - Common use cases with copy-paste examples
   - Quick troubleshooting
   - Links to detailed docs

2. **FEATURES.md** - Comprehensive reference
   - Detailed feature descriptions
   - All parameters and options
   - Architecture diagrams
   - Advanced workflows
   - Complete troubleshooting guide
   - FAQ section

3. **WORKFLOW_EXAMPLES.md** - Step-by-step guides
   - Real-world scenarios
   - Complete command sequences
   - Environment-specific examples

### For Team/Maintainers

4. **TEAM_HANDOFF.md** - This document
   - Design decisions and rationale
   - Technical architecture
   - Maintenance guidelines
   - Future enhancements

---

## 🏗️ Technical Architecture

### Environment Detection Pattern

All scripts follow this pattern:

```bash
# 1. Check if parent script already loaded environment
if [ -z "${NVM_DIR:-}" ] || ! command -v nvm &> /dev/null; then
    # 2. Standalone mode - Auto-detect NVM location
    if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        # Use existing NVM_DIR
        \. "$NVM_DIR/nvm.sh"
    elif [ -s "$HOME/.nvm/nvm.sh" ]; then
        # Standard location
        export NVM_DIR="$HOME/.nvm"
        \. "$NVM_DIR/nvm.sh"
    elif [ -s "/home/master/.nvm/nvm.sh" ]; then
        # Cloudways location
        export NVM_DIR="/home/master/.nvm"
        \. "$NVM_DIR/nvm.sh"
        # Additional Cloudways paths
        export PATH="/home/master/bin:${PATH}"
        export PM2_HOME="/home/master/.pm2"
    fi
fi

# 3. Load Node version from .nvmrc (if exists)
if [ -f .nvmrc ]; then
    nvm use
fi
```

**Priority:**
1. Inherit from parent (if already loaded)
2. Use `$NVM_DIR` if set and valid
3. Try `$HOME/.nvm/nvm.sh` (macOS/Linux standard)
4. Try `/home/master/.nvm/nvm.sh` (Cloudways)
5. Fall back to system Node/NPM

### Script Communication Pattern

**Parent → Child:**
- Parent loads environment once
- Child detects via `$NVM_DIR` + `command -v nvm` check
- Child skips setup if already configured

**Example Flow:**
```
deploy/build-and-restart.sh
    ↓ (exports NVM_DIR, loads nvm)
    ↓
pm2/pm2-manager.sh stop
    ↓ (detects NVM_DIR set + nvm exists)
    ↓ (skips environment setup)
    ↓ (uses inherited environment)
```

### rsync Compatibility

**Challenge:** macOS ships with ancient rsync 2.6.9 (from 2006)

**Solution:** Use only universally-supported flags
```bash
# ❌ Modern rsync only
rsync -az --info=progress2

# ✅ Compatible with old and new
rsync -az --progress
```

### Interactive Mode Pattern

All scripts follow this pattern:

```bash
# 1. Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --param) PARAM="$2"; shift 2 ;;
    --param=*) PARAM="${1#*=}"; shift ;;
    *) POSITIONAL_ARG="$1"; shift ;;
  esac
done

# 2. Prompt for missing required parameters
if [ -z "$PARAM" ]; then
  read -p "Enter value: " PARAM
fi

# 3. Validate
if [ -z "$PARAM" ]; then
  error_exit "Parameter is required"
fi
```

---

## 🚀 Publishing to GitHub

### Prerequisites

1. Create public GitHub repository:
   - Repository: `orange-soft/cw-strapi-toolkit`
   - Visibility: **Public**
   - Description: "DevOps toolkit for managing Strapi applications on Cloudways and other hosting platforms"

2. Verify install.sh has correct URL:
   ```bash
   REPO_URL="https://github.com/orange-soft/cw-strapi-toolkit.git"
   ```

### Git Initialization Commands

```bash
cd /Users/justinmoh/Projects/cw-strapi-toolkit

# Initialize repository
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: Cloudways Strapi Toolkit v1.0.0

Features:
- Backup/restore utilities (export.sh, import.sh)
- Deployment automation (build-and-restart.sh)
- PM2 process management (pm2-manager.sh)
- Environment setup tools (generate-env-keys.sh, setup-env-keys.sh)
- Cloudways utilities (sync-to-cloudways.sh, fix-permissions.sh, check-ports.sh)
- Universal environment auto-detection
- Interactive mode support
- Tab completion for file paths
- Complete documentation (README, FEATURES, WORKFLOW_EXAMPLES)

Design:
- Atomic script execution (no config files)
- Multi-tenant compatible (Cloudways)
- Environment agnostic (macOS, Linux, Cloudways)
- Parent-child optimization
- rsync compatibility (old and new versions)"

# Add GitHub remote
git remote add origin https://github.com/orange-soft/cw-strapi-toolkit.git

# Push to GitHub
git branch -M main
git push -u origin main
```

### Post-Publication Verification

Test the one-line installer:

```bash
# In a test directory
cd /tmp
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/main/install.sh | bash

# Verify installation
ls -la strapi-toolkit/
bash strapi-toolkit/setup/generate-env-keys.sh
```

---

## 🔄 Maintenance Guidelines

### Adding New Scripts

1. **Choose appropriate directory:**
   - `backup/` - Data operations
   - `cloudways/` - Hosting-specific utilities
   - `deploy/` - Build and deployment
   - `pm2/` - Process management
   - `setup/` - Configuration and setup
   - `utils/` - Shared utilities (future)

2. **Follow naming conventions:**
   - Use kebab-case: `my-script.sh`
   - Descriptive verb-based names
   - Avoid version numbers in filenames

3. **Include in script:**
   - Shebang: `#!/bin/bash`
   - Error handling: `set -e`
   - Usage function: `show_usage()`
   - Environment detection
   - Interactive mode support

4. **Update documentation:**
   - Add to `README.md` (common use cases)
   - Add to `FEATURES.md` (detailed docs)
   - Add to `WORKFLOW_EXAMPLES.md` (if applicable)
   - Update compatibility matrix

5. **Test on all environments:**
   - macOS (local development)
   - Linux server (legacy/staging)
   - Cloudways (production)

### Versioning

**Current approach:** No semantic versioning yet

**Future consideration:** Use git tags when major changes occur
```bash
git tag -a v1.0.0 -m "Initial stable release"
git push origin v1.0.0
```

### Breaking Changes

If a change would break existing usage:

1. Add deprecation warning to old approach
2. Support both old and new for at least one version
3. Document migration path in README
4. Announce in commit message and release notes

---

## 🧪 Testing Checklist

Before pushing changes to main:

### Local Testing (macOS)
- [ ] Script runs without errors
- [ ] Interactive mode works (no parameters)
- [ ] Direct mode works (all parameters)
- [ ] Tab completion works for file paths
- [ ] Help text is clear: `script.sh --help`

### Linux Testing (staging server)
- [ ] Environment detection works
- [ ] NVM loading works
- [ ] Node version switching works (.nvmrc)
- [ ] PM2 operations work (if applicable)

### Cloudways Testing (production)
- [ ] Script works in restricted app folder
- [ ] Paths don't require access outside `~/public_html/`
- [ ] Permissions are correct after execution
- [ ] rsync works with old rsync version

### Documentation Testing
- [ ] README examples are copy-paste ready
- [ ] FEATURES.md matches actual behavior
- [ ] WORKFLOW_EXAMPLES.md steps work end-to-end
- [ ] All links in documentation work

---

## 🎯 Future Enhancements

### Short Term (Next Version)

1. **PostgreSQL Support**
   - Currently: Only SQLite (`.tmp/data.db`)
   - Needed: `pg_dump` / `pg_restore` for PostgreSQL
   - Location: `backup/export.sh` and `backup/import.sh`

2. **MySQL Support**
   - Similar to PostgreSQL
   - Use `mysqldump` / `mysql` commands

3. **Selective Backup**
   - Option to backup only database OR only uploads
   - Faster for large file libraries

4. **Compression Options**
   - Currently: Uses default gzip
   - Add: Option for different compression (bzip2, xz)

5. **Backup Encryption**
   - Add GPG encryption option for sensitive data
   - Useful for backups stored in cloud

### Medium Term

6. **CI/CD Integration Scripts**
   - GitHub Actions workflow template
   - GitLab CI template
   - Environment-based deployment

7. **Health Check Script**
   - Verify all requirements (NVM, PM2, rsync, etc.)
   - Check Node version compatibility
   - Validate Strapi configuration

8. **Rollback Script**
   - Automated rollback to previous backup
   - Git rollback integration
   - Combined data + code rollback

9. **Multi-Environment Config**
   - Optional profiles (dev, staging, prod)
   - Still atomic, but convenience layer

### Long Term

10. **Web Dashboard**
    - Simple web UI for script execution
    - Backup browser
    - Log viewer

11. **Monitoring Integration**
    - Slack/Discord notifications
    - Error alerting
    - Backup completion notifications

12. **Backup Rotation**
    - Automatic cleanup of old backups
    - Configurable retention policy

---

## 🐛 Known Limitations

### 1. SQLite Only
**Limitation:** Backup scripts only support SQLite database

**Workaround:** Manual `pg_dump` or `mysqldump` for other databases

**Future:** Add database detection and use appropriate tools

### 2. No Automated Testing
**Limitation:** No automated test suite

**Workaround:** Manual testing checklist (see above)

**Future:** Add Bash testing framework (bats-core)

### 3. No Backup Verification
**Limitation:** Scripts don't verify backup integrity after creation

**Workaround:** Manual inspection or test restore

**Future:** Add checksum validation and test extraction

### 4. Single PM2 Config
**Limitation:** Assumes one ecosystem.config.js per project

**Workaround:** Manually specify config file (future parameter)

**Future:** Add `--config` parameter to PM2 scripts

### 5. No Windows Support
**Limitation:** Bash scripts don't run natively on Windows

**Workaround:** Use WSL2 (Windows Subsystem for Linux)

**Future:** Consider PowerShell equivalents (low priority)

---

## 📞 Team Contact & Handoff

### Current Status
✅ Toolkit is complete and ready for use
✅ All scripts tested and functional
✅ Documentation is comprehensive
✅ Ready for GitHub publication

### Handoff Checklist

- [ ] GitHub repository created: `orange-soft/cw-strapi-toolkit`
- [ ] Repository set to **Public**
- [ ] Initial commit pushed to `main` branch
- [ ] One-line installer tested and working
- [ ] Team members notified of new toolkit
- [ ] Added to team documentation/wiki
- [ ] Training session scheduled (optional)

### Questions to Address During Handoff

1. **Who will maintain this toolkit?**
   - Assign primary maintainer
   - Define contribution process

2. **How to handle feature requests?**
   - GitHub Issues?
   - Internal request system?

3. **Versioning strategy?**
   - Git tags only?
   - Semantic versioning?
   - Release notes?

4. **Testing requirements?**
   - Manual testing checklist?
   - Automated tests in future?

5. **Documentation updates?**
   - Who reviews documentation PRs?
   - How often to update?

### Key Contacts

**Original Developer:** [Your name/team]
**Current Maintainer:** [To be assigned]
**Repository:** https://github.com/orange-soft/cw-strapi-toolkit
**Issues:** https://github.com/orange-soft/cw-strapi-toolkit/issues

---

## 📖 Related Resources

### Internal Documentation
- Cloudways hosting setup guide
- Strapi deployment procedures
- Team DevOps standards

### External Resources
- [NVM (Node Version Manager)](https://github.com/nvm-sh/nvm)
- [PM2 Documentation](https://pm2.keymetrics.io/)
- [rsync Manual](https://linux.die.net/man/1/rsync)
- [Strapi Documentation](https://docs.strapi.io/)
- [Cloudways Documentation](https://support.cloudways.com/)

---

## 🎓 Training Notes

### For New Team Members

**Essential Knowledge:**
1. Basic Bash scripting
2. SSH and rsync usage
3. Node.js and NVM concepts
4. PM2 process management
5. Strapi application structure

**Learning Path:**
1. Read README.md (30 minutes)
2. Try common use cases locally (1 hour)
3. Read FEATURES.md for deep understanding (1 hour)
4. Practice workflows on staging server (2 hours)
5. Deploy to production with supervision (supervised)

**Common Mistakes to Avoid:**
1. Running scripts outside app directory on Cloudways
2. Forgetting `--port` parameter for Cloudways SSH
3. Not testing backups before major operations
4. Using `--file=path` format (breaks tab completion)
5. Assuming scripts need sudo (they don't!)

---

## ✅ Final Pre-Publication Checklist

### Code Quality
- [x] All scripts have execute permissions
- [x] All scripts include error handling (`set -e`)
- [x] All scripts have usage documentation
- [x] Environment detection works universally
- [x] No hardcoded paths or credentials

### Documentation
- [x] README.md is user-friendly and concise
- [x] FEATURES.md covers all features comprehensively
- [x] WORKFLOW_EXAMPLES.md has real-world examples
- [x] TEAM_HANDOFF.md explains design decisions
- [x] All examples are tested and copy-paste ready

### Testing
- [x] Tested on macOS (local development)
- [x] Tested on Linux (if available)
- [x] Verified Cloudways compatibility
- [x] Tab completion works for file paths
- [x] Interactive mode works for all scripts

### Repository Setup
- [x] .gitignore includes comprehensive patterns
- [x] install.sh has correct repository URL
- [x] All path references use current directory
- [x] No references to `gocomm-strapi` project
- [x] Bootstrap installer works (if needed)

### Publication
- [ ] GitHub repository created and public
- [ ] Initial commit prepared with detailed message
- [ ] One-line installer URL is correct
- [ ] Repository has proper description
- [ ] Team has been notified

---

**Document Version:** 1.0
**Last Updated:** October 30, 2024
**Status:** Ready for team handoff and GitHub publication

---

## 🎉 Congratulations!

You now have a complete, production-ready DevOps toolkit that your team can use across all Strapi projects. The toolkit is:

✅ **Universal** - Works on macOS, Linux, and Cloudways
✅ **Atomic** - No configuration files to manage
✅ **Interactive** - User-friendly with helpful prompts
✅ **Well-Documented** - Comprehensive documentation for users and maintainers
✅ **Production-Ready** - Battle-tested and reliable

**Next step:** Push to GitHub and share with your team! 🚀
