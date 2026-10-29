# Cloudways Strapi Toolkit

A comprehensive collection of battle-tested DevOps scripts for managing Strapi applications across different environments: local development, cPanel servers, and Cloudways production hosting.

### Supported Servers

The same scripts run on both server types. Nothing is configured per server: the scripts detect it from the app path. To force a type (e.g. for a host whose paths look different), set `DEPLOY_SERVER_TYPE=cpanel` or `DEPLOY_SERVER_TYPE=cloudways` in the environment; the boilerplate's deploy workflow passes its `DEPLOY_SERVER_TYPE` GitHub variable through. When running scripts by hand on such a host, prefix them the same way, e.g. `DEPLOY_SERVER_TYPE=cpanel bash strapi-toolkit/pm2/pm2-manager.sh status`.

| | cPanel | Cloudways |
|---|---|---|
| Detected by (unless `DEPLOY_SERVER_TYPE` is set) | anything else | app path contains `/applications/` or `.cloudwaysapps.com/` |
| App path | `/home/<user>/public_html/<project>` | `/home/<server>.cloudwaysapps.com/<app>/public_html/<project>` |
| SSH / deploy user | the cPanel user | the app user (or master) |
| NVM | the user's own `~/.nvm` (legacy: shared `/opt/nvm`) | the master user's `~/.nvm`, shared by all apps |
| PM2 | one daemon per user (`~/.pm2`) | one shared daemon (`<master home>/.pm2`) |
| `nvm alias default` | set to `.nvmrc` on each deploy | never changed (shared by all apps) |

The Cloudways master home is `/home/master`, or `/mnt/BLOCKSTORAGE/home/master` on block storage servers (where `/home/master` is a symlink to it). Set `MASTER_HOME` to override it. Scripts always load nvm through the real path: nvm refuses to switch Node ("nvm is not compatible with the npm config prefix option") when `NVM_DIR` goes through a symlink.

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
  - [cPanel Utilities](#6-cpanel-specific-utilities)
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

# Non-interactive (CI / ssh without a terminal)
bash strapi-toolkit/update.sh --yes
```

**Option 2: Re-run the installer**
```bash
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash
# Will prompt to update (the prompt reads from your terminal, not the pipe)

# Non-interactive
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash -s -- --yes
```

### Update Behavior

Both `update.sh` and `install.sh` update safely:

1. Download the latest version into a temp dir next to the toolkit (`.strapi-toolkit-update.XXXXXX`)
2. Verify it: required scripts present, every `*.sh` passes `bash -n`
3. Compare with the installed copy; nothing changes if they are identical
4. Show changed files and ask for confirmation (skip with `--yes`)
5. Swap in with two renames; the old version is deleted only after the new one is in place

**Failure safety & cleanup:**
- Download failure, broken download, refused confirmation → installed toolkit untouched
- Failure or Ctrl+C in the middle of the swap → previous version is moved back
- The temp dir is removed on every exit; temp dirs left by a killed run (older than 1 hour) are removed on the next run
- The scripts run entirely inside `main()`, so a truncated `curl | bash` download never runs half a script

**Exact match with the repository:**
- Modified files are updated, new files are added, deleted files are removed
- No local modifications persist (intentional)
- No `.git` folder (the parent repo would otherwise treat the toolkit as a submodule)

**Why this matters:** If a script is renamed or deleted in the repository (e.g., `old-script.sh` → `new-script.sh`), a simple `git pull` would leave both files, potentially causing confusion. Our update method ensures you always have exactly what's in the repository.

---

## What's Included

```
strapi-toolkit/
├── backup/          # Data backup and restore utilities
│   ├── export.sh    # Back up (Strapi export) to the strapi-backup R2 bucket
│   ├── import.sh    # Restore a backup (Strapi import), safe for local development
│   └── r2-backup.cjs # R2/S3 helper for export.sh (uses the app's AWS SDK)
│
├── cloudways/       # Cloudways-specific tools
│   ├── sync-to-cloudways.sh   # Upload files via rsync
│   ├── fix-permissions.sh     # Fix file permissions
│   └── check-ports.sh         # Check port usage
│
├── cpanel/          # cPanel server setup tools (see cpanel/README.md)
│   ├── setup-site.sh          # One-time setup of a new site (as the cPanel user)
│   ├── pm2-boot-service.sh    # Restore PM2 apps after reboot (root, once per server)
│   └── generate-deploy-key.sh # Deploy keypair helper
│
├── deploy/          # Deployment orchestration
│   ├── build-and-restart.sh   # Full deployment workflow (build on the server)
│   └── restart-only.sh        # Server half of a GitHub Actions deploy
│
├── pm2/             # PM2 process management
│   └── pm2-manager.sh         # Unified PM2 interface
│
├── setup/           # Environment configuration
│   ├── generate-env-keys.sh   # Generate security keys
│   └── setup-env-keys.sh      # Write secrets into .env (--missing-only: never replaces existing ones)
│
└── shell-env.sh     # source it: set up your SSH shell like the deploy (node, npm, pm2)
```

---

## Common Use Cases

### 1. Backup Strapi Data

```bash
# On the server: upload to the backup bucket, print a 24h download URL
bash strapi-toolkit/backup/export.sh --link
```

### 2. Restore Strapi Data

```bash
# Paste a backup URL when asked (e.g. from export.sh --link)
bash strapi-toolkit/backup/import.sh

# Or a local archive
bash strapi-toolkit/backup/import.sh --file ./backups/backup-1793268008.tar.gz
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

### 4b. Work on the Server by Hand

An SSH session doesn't have the app's Node, npm or pm2 (on Cloudways the app user even lacks Node entirely). Source `shell-env.sh` once per session:

```bash
cd ~/public_html/<project>                 # the app folder
source strapi-toolkit/shell-env.sh         # or: source <app>/strapi-toolkit/shell-env.sh from anywhere
node --version; npm ls @strapi/strapi; pm2 list
```

It sets up the shell exactly like the deploy scripts (same detection, `DEPLOY_SERVER_TYPE` / `MASTER_HOME` work too):
- Node from `.nvmrc` via the right NVM — Cloudways: master's shared NVM through its real path (`/home/master` may be a symlink nvm rejects); cPanel: the user's own `~/.nvm`
- `pm2` on `PATH` and `PM2_HOME` — Cloudways: master's shared daemon; cPanel: `~/.pm2`
- `NODE_BIN`, so a manual `pm2 start ecosystem.config.cjs` uses the same Node as the deploy
- `NPM_CONFIG_CACHE` and `HOME` in `public_html` (the real home is kept in `REAL_HOME`; `--keep-home` leaves `HOME` alone)
- `LC_ALL=C.UTF-8` only if the current locale is broken (silences `manpath: can't set the locale`)

It must be sourced (running it with `bash` only prints a reminder), is safe to source again, and never closes your shell on an error. On Cloudways, PM2 and NVM are shared by every app: use `pm2-manager.sh` for this app, never `pm2 delete all`, `pm2 kill`, `npm install -g` or `nvm alias default`.

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

**Purpose:** Back up a Strapi app off-site: Strapi's own export (`strapi export`), uploaded to a shared R2 bucket.

**What a backup contains** (`backup-<timestamp>.tar.gz`, not encrypted): content types, all entries (including media library records, users-permissions users and roles), relations, and configuration (admin and plugin settings, webhooks). Media files only for sites with media in `public/uploads`; sites with media in R2/S3 get a copy of their media bucket next to the archive instead. Works with any database Strapi supports. Admin users are not part of Strapi exports.

**Usage:**

```bash
# Production: upload to the backup bucket and print a download URL (24h)
bash strapi-toolkit/backup/export.sh --link

# Keep the archive on this machine only
bash strapi-toolkit/backup/export.sh --local-only
```

| Option | |
|---|---|
| `--link`, `--link=1h` | Print a presigned download URL for the uploaded archive (default 24h, at most 7d). Anyone with the URL can download the whole database until it expires: don't post it where it stays around |
| `--local-only` | Upload nothing, keep the archive on this machine |
| `--keep-local` | Keep the local archive after uploading it |
| `--no-media` | Leave media files out (records are still included), and skip the media bucket copy |
| `--output DIR` | Where the local archive goes. Default `private_html/strapi-backups/<app>/` on servers (see below), `./backups/` on a development machine. Never inside `public/`, which the site serves |
| `--stall-timeout=SECONDS` | Stop the export when the archive stops growing this long (default 300, `0` = never) |
| `--print-cron` | Print the crontab line for a daily backup of this app (see below) and exit |

**Servers vs development machines:** an app with `.deploy-info` (written by the deploy) or under `public_html/` is on a server, cPanel or Cloudways. Local files on servers go to the `private_html` next to `public_html`, where the deploy keeps its pre-deploy dumps: outside the web root and never touched by deploys. That is `~/private_html` on cPanel and `/home/master/applications/<app>/private_html` on Cloudways, whichever user is logged in (app user or master). Servers refuse to back up without the backup bucket (`--local-only` to override); a development machine keeps the archive in `./backups/` when the bucket isn't set up.

**The backup bucket (`BACKUP_R2_*` in `.env`):**

```
strapi-backup/                              # one bucket for all apps
└── reading-strapi/                         # BACKUP_APP_NAME, default: the app's directory name
    ├── db/backup-1793268008.tar.gz         # one archive per run
    ├── media/<key>                         # first copy of each media file (R2/S3 sites)
    └── media-versions/<time>/<key>         # each later version of a replaced file
```

The backup only ever creates objects: it never overwrites or deletes one. So it works under a retention lock (below), and replacing a file in the media library (which keeps its key) doesn't lose the earlier version: the new content goes to `media-versions/<time of the run>/<key>`. The newest copy of a file is its latest `media-versions` entry, else `media/`.

```bash
BACKUP_R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
BACKUP_R2_ACCESS_KEY_ID=          # token scoped to the backup bucket, not the media keys
BACKUP_R2_SECRET_ACCESS_KEY=
BACKUP_R2_BUCKET=strapi-backup    # optional
BACKUP_APP_NAME=                  # optional
```

With these set: both buckets are checked before exporting; the archive is uploaded to `<app>/db/`, its size and md5 compared with the local file, and the local copy removed (`--keep-local` keeps it). A failed or mismatching upload keeps the local archive and exits with an error.

**Retention lock (set once on the bucket):** the backup keys live in each server's `.env`, and R2 keys that can write can also delete. A bucket lock rule makes every object undeletable and unchangeable for a set time, whatever the keys, so a compromised server or a bad script can't destroy recent backups. In the Cloudflare dashboard: *R2 → strapi-backup → Settings → Bucket lock rules → Add rule*, no prefix (whole bucket), retention e.g. 30 days. That needs a Cloudflare login, not the app's keys, which is the point. Keep the heartbeat monitoring on, so a problem is noticed within the lock period. Nobody (you included) can delete anything younger than the retention period.

**Old archives:** not pruned by the toolkit (it never deletes). Storage is cheap (a few MB per database archive), but if wanted, add an R2 lifecycle rule per app on the prefix `<app>/db/`, longer than the lock period. Never on `media/` or `media-versions/`: those hold the only copies of files no longer in the media bucket.

Nothing to install: `backup/r2-backup.cjs` uses the AWS SDK that comes with `@strapi/provider-upload-aws-s3` in the app's `node_modules` (Cloudways app users can't install software outside `public_html`). Apps without that provider can't upload.

**Sites with media in R2/S3** (`@strapi/provider-upload-aws-s3` + `AWS_BUCKET`): Strapi's export would download every media file over HTTP, which is slow and can hang forever (when a CDN compresses a file, e.g. Cloudflare in front of an R2 custom domain serving SVGs, its size no longer matches `Content-Length`, the archive breaks and the export never exits). So the archive never contains their media files; after the export the media bucket is copied: new files to `<app>/media/`, files replaced in the media library since their last copy (same key, different size or newer date) to `<app>/media-versions/<time>/`, unchanged files skipped.

**Daily backups (cron):** run `bash strapi-toolkit/backup/export.sh --print-cron` in the app folder on the server. It prints the exact line for this app, e.g.:

```
27 3 * * * cd '/home/user/public_html/reading-strapi' && bash strapi-toolkit/backup/export.sh > '/home/user/private_html/strapi-backups/reading-strapi/export.log' 2>&1 || cat '/home/user/private_html/strapi-backups/reading-strapi/export.log'
```

- cPanel: *Cron Jobs* (or `crontab -e`); Cloudways: *Application → Cron Job Management*
- The minute is derived from the app path, so apps on one server don't all run at once
- A successful run prints nothing; a failed one prints its log, which cron mails if a cron email is set (cPanel *Cron Email*). The last run's output is always in `export.log`
- **Monitoring:** set `BACKUP_HEARTBEAT_URL` in `.env` to a heartbeat check (e.g. healthchecks.io, period 1 day). Every successful upload pings it; the service alerts when a ping doesn't arrive, which also catches a cron that stopped running or a server that's down. Cron email alone can't (and Cloudways cron may not send any)

**Hang protection:** the export runs in the background; if the archive stops growing for `--stall-timeout` seconds, the export is stopped, the partial archive removed, and the script exits with an error. Ctrl+C stops the whole npm → node tree.

---

### `backup/import.sh`

**Purpose:** Restore a backup into this app (`strapi import`), on a server or on a development machine.

**Usage:**

```bash
# Prompts for a backup URL (e.g. from export.sh --link)
bash strapi-toolkit/backup/import.sh

# Local archive
bash strapi-toolkit/backup/import.sh --file ./backups/backup-1793268008.tar.gz
```

| Option | |
|---|---|
| `--file PATH` | Import a local archive instead of downloading one |
| `--with-config` | Also import the backup's settings, webhooks and plugin settings on a development machine (default there: keep its own) |
| `--recreate-tables` | MySQL: drop all tables first so Strapi recreates them, e.g. after converting the database to utf8mb4. Not rolled back if the import fails |

**What it does:**

1. Gets the archive: downloads the URL (checks it isn't an error page) or uses `--file`
2. Decides what to import:
   - **Media files:** never on R2/S3 sites (importing them makes Strapi delete every existing media file through the upload provider, which is the live bucket, also from a development machine whose `.env` has the bucket's keys), nor from archives without media. Media library records are always imported and keep pointing at the existing files
   - **Settings, webhooks, plugin settings** (Strapi's configuration: admin settings, plugin settings such as the Meilisearch host and indexing key): imported on servers; a development machine keeps its own unless `--with-config`, otherwise editing content there would update production's search index and fire production webhooks
3. MySQL: saves a safety dump of the current database to `private_html/strapi-backups/<app>/` (server, cPanel or Cloudways, see export.sh) or `./backups/` (development machine), where deploys never delete it. The password goes through `MYSQL_PWD`, never the command line
4. Shows what will happen and asks for `yes`
5. On a server: stops the app through `pm2-manager.sh` (restarted afterwards, also when the import fails or the script is interrupted)
6. Runs `strapi import --force`. Strapi imports in one transaction: if it fails (e.g. the archive's content types differ from the code's), it is rolled back and the database is left as it was

Needs the MySQL client tools for MySQL databases (macOS: `brew install mysql-client`). Admin users are not in backups, so a development machine keeps its own admin login.

**Restoring media of an R2/S3 site:** the media bucket is never touched by an import. If files are missing from it, copy them back from the backup bucket with any S3 tool (the toolkit has no media restore yet): the newest copy of a file is its latest `<app>/media-versions/<time>/<key>`, else `<app>/media/<key>`.

---

## 2. Deployment & Build

### `deploy/build-and-restart.sh`

**Purpose:** Zero-downtime deployment workflow - build Strapi and restart with PM2

**Key Features:**
- **Zero-downtime deployment** - App stays running during build
- Orchestrates full deployment process
- NVM environment auto-detection
- Automatic Node version switching (from `.nvmrc`; `22` tracks the latest 22.x)
- Exports the resolved Node as `NODE_BIN` so PM2 runs the same Node that built the app
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

**Environment Detection** (see [Supported Servers](#supported-servers)):
- cPanel: the login user's own `~/.nvm` and `~/.pm2`, falling back to the legacy shared `/opt/nvm`
- Cloudways: the master user's `~/.nvm` and `~/.pm2` (`MASTER_HOME`, `/home/master` or `/mnt/BLOCKSTORAGE/home/master`)
- Uses the login user's real home, even when a parent script has overridden `HOME`

**PM2 Config Detection:**
- Looks for `ecosystem.config.js` first
- Falls back to `ecosystem.config.cjs`
- Exits with error if neither found

**Use Cases:**
- Deploying code updates to server
- Rebuilding after dependency changes
- Applying configuration changes
- Standard deployment workflow

### `deploy/restart-only.sh`

**Purpose:** Server half of a GitHub Actions deploy, where the admin panel is built on the runner and synced with rsync (without `node_modules`)

**Workflow:**
1. Load NVM and the Node version from `.nvmrc` (same detection as `build-and-restart.sh`), export `NODE_BIN`
2. Check `.env` and the synced `dist/` (or `build/`)
3. Production dependencies (never synced with the code), only when `package.json`, `package-lock.json` or the Node ABI changed since the last install (fingerprint in `node_modules/.deploy-deps-hash`; the ABI is the same for every 22.x):
   - `DEPLOY_DEPS_INSTALL=runner` (the deploy workflow's default): the workflow has already installed them on the GitHub runner and copied them into `.deps-staging/`; this script only swaps them in. It fails, leaving the app untouched, if nothing matching was staged
   - `DEPLOY_DEPS_INSTALL=server` (or unset, e.g. a manual run): `npm ci --omit=dev --prefer-offline` into `.deps-staging/` while the app keeps serving. Needs ~1.3 GB free RAM; a "Killed" npm means the server ran out of memory
   - Either way the new `node_modules` is swapped in just before the restart, and the previous copy deleted after it
4. Restart PM2 (recreates the process if the Node version changed)
5. Wait until Strapi answers `http://127.0.0.1:<PORT>/_health` (up to `STRAPI_HEALTH_TIMEOUT` seconds, default 120); fail with the app's last log lines if it doesn't, so a successful deploy means Strapi is serving

**Usage:**

```bash
# Run from your Strapi project root (called by the GitHub Actions deploy workflow)
bash strapi-toolkit/deploy/restart-only.sh
```

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

# Restart application (graceful; recreates the process if the Node version changed)
bash strapi-toolkit/pm2/pm2-manager.sh restart

# Check Strapi answers /_health (also run automatically after restart/recreate)
bash strapi-toolkit/pm2/pm2-manager.sh health

# Delete + start current app (re-resolves Node/npm paths)
bash strapi-toolkit/pm2/pm2-manager.sh recreate

# Audit: Node version per PM2 process + nvm versions safe to uninstall (read-only)
bash strapi-toolkit/pm2/pm2-manager.sh node-versions

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

**Node Version Handling:**
- `.nvmrc` may contain a major line (`22`), minor (`22.23`) or exact version (`22.23.4`), with or without `v`
- `NODE_BIN` (directory of the resolved `node`/`npm`) is exported for `ecosystem.config.cjs`
- PM2 remembers the resolved `npm` path from an app's *first* start, and `pm2 restart` does not update it.
  `restart` therefore compares the running process with the config and does `delete` + `start` (current app only) when they differ
- Warns when `ecosystem.config.cjs` hardcodes a Node version that differs from `.nvmrc`

**Recommended `ecosystem.config.cjs` (no hardcoded Node version):**

```js
const path = require('path');
// Set by deploy/build-and-restart.sh and pm2-manager.sh; falls back to the Node running the pm2 CLI
const NVM_NODE_BIN = process.env.NODE_BIN || path.dirname(process.execPath);

module.exports = {
  apps: [{
    // ...
    interpreter: `${NVM_NODE_BIN}/node`,
    script: `${NVM_NODE_BIN}/npm`,   // explicit path, so PM2 never keeps a stale npm
    args: 'start',
    env: {
      PATH: `${NVM_NODE_BIN}:...`,
      PORT: '__STRAPI_PORT__',
    },
  }],
};
```

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
# Safe on any site: only fill in secrets that are missing, empty or still a
# placeholder (tobemodified); existing secrets are never replaced
bash strapi-toolkit/setup/setup-env-keys.sh --missing-only

# Rotate ALL secrets (new .env, or a planned rotation): logs out every user,
# invalidates API tokens and makes encrypted values unreadable
bash strapi-toolkit/setup/setup-env-keys.sh

# Add --yes to skip the confirmation prompt
bash strapi-toolkit/setup/setup-env-keys.sh --missing-only --yes
```

Secrets handled: `APP_KEYS` (two keys), `API_TOKEN_SALT`, `ADMIN_JWT_SECRET`, `TRANSFER_TOKEN_SALT`, `JWT_SECRET`, `ENCRYPTION_KEY`, `ADMIN_ENCRYPTION_KEY`. Strapi reads `.env` at startup, so restart afterwards (`bash strapi-toolkit/pm2/pm2-manager.sh restart`).

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

## 6. cPanel-Specific Utilities

Server setup tools for cPanel/WHM servers (one site per cPanel account, each with its own `~/.nvm` and `~/.pm2`). Deploys don't use them; see [`cpanel/README.md`](cpanel/README.md) for installing and running them.

| Script | Run as | Purpose |
|---|---|---|
| `cpanel/setup-site.sh` | the site's cPanel user (installed as `setup-strapi-site`) | One-time site setup: deploy key, NVM + Node, clone, `.env` with secrets, free port |
| `cpanel/pm2-boot-service.sh` | root, once per server | systemd service that restores every user's PM2 apps after a reboot |
| `cpanel/generate-deploy-key.sh` | the site's cPanel user | Generates the GitHub Actions deploy keypair |

Root installs them straight from this repo, e.g.:

```bash
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/cpanel/setup-site.sh -o /tmp/setup-site.sh
sudo install -m 755 /tmp/setup-site.sh /usr/local/bin/setup-strapi-site
```

---

## Workflow Examples

Complete step-by-step guides for common scenarios.

### Workflow 1: Production Data on a Development Machine

```bash
# 1. On the production server: back up, print a download URL
cd ~/public_html/<app>
bash strapi-toolkit/backup/export.sh --link

# 2. On the development machine (npm run develop stopped): paste the URL
cd ~/projects/my-strapi-app
bash strapi-toolkit/backup/import.sh

# 3. Start local development
npm run develop
```

The development machine keeps its own settings, webhooks and plugin settings (so it never updates production's search index), and the media files of an R2/S3 site are left alone: the imported records point at the production files, which load read-only by URL. Don't give a development machine the production media bucket's keys: deleting or replacing media there would change production's files.

---

### Workflow 2: Deploy Code Updates to Cloudways

```bash
# 1. On the server - Back up first (safety)
bash strapi-toolkit/backup/export.sh

# 2. On local - Push code changes
git add .
git commit -m "Update feature X"
git push origin master

# 3. On Cloudways - Pull and deploy
cd ~/public_html
git pull origin master
bash strapi-toolkit/deploy/build-and-restart.sh

# 4. Verify deployment
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

# 1. On Cloudways - Import the last good backup (URL from export.sh --link,
#    or a download link for <app>/db/ in the backup bucket)
cd ~/public_html/<app>
bash strapi-toolkit/backup/import.sh

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
# 1. On the server - Back up (safety)
bash strapi-toolkit/backup/export.sh

# 2. On local - Commit and push code
git add .
git commit -m "Update feature X"
git push origin master

# 3. On Cloudways - Pull and deploy
cd ~/public_html
git pull origin master
bash strapi-toolkit/deploy/build-and-restart.sh

# 4. Verify deployment
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
- **Server type** - `DEPLOY_SERVER_TYPE` if set, else Cloudways from the app path (`/applications/` or `.cloudwaysapps.com/`), otherwise cPanel
- **NVM & PM2 location** - cPanel: the user's `~/.nvm` + `~/.pm2` (or `/opt/nvm`); Cloudways: the master home's `.nvm` + `.pm2`
- **Cloudways master home** - `/home/master` or `/mnt/BLOCKSTORAGE/home/master` (block storage), from the app path; override with `MASTER_HOME`
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
export.sh                              import.sh
    │                                      │
    ├─→ Load NVM + Node                    ├─→ Download / unpack the archive
    ├─→ Check the backup + media buckets   ├─→ Exclude media (R2/S3, no media in
    ├─→ strapi export (stall watchdog)     │     archive), config (dev machine)
    ├─→ Upload to <app>/db/, check md5     ├─→ MySQL safety dump (private_html / ./backups)
    ├─→ Remove the local archive           ├─→ Confirm
    └─→ Copy media bucket → <app>/media/   ├─→ Stop the app (server, pm2-manager.sh)
                                           ├─→ strapi import (one transaction)
                                           └─→ Restart the app
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

| Script | macOS | Linux | cPanel | Cloudways | Notes |
|--------|-------|-------|--------|-----------|-------|
| `backup/export.sh` | ✅ | ✅ | ✅ | ✅ | Universal |
| `backup/import.sh` | ✅ | ✅ | ✅ | ✅ | Universal |
| `deploy/build-and-restart.sh` | ⚠️ | ✅ | ✅ | ✅ | Requires PM2 |
| `deploy/restart-only.sh` | ⚠️ | ✅ | ✅ | ✅ | GitHub Actions deploys |
| `pm2/pm2-manager.sh` | ✅ | ✅ | ✅ | ✅ | Universal (installs PM2 if missing) |
| `setup/generate-env-keys.sh` | ✅ | ✅ | ✅ | ✅ | Universal |
| `setup/setup-env-keys.sh` | ✅ | ✅ | ✅ | ✅ | Universal |
| `cloudways/sync-to-cloudways.sh` | ✅ | ✅ | ✅ | ✅ | Universal (requires rsync) |
| `cloudways/fix-permissions.sh` | ❌ | ❌ | ❌ | ✅ | Cloudways only |
| `cloudways/check-ports.sh` | ⚠️ | ✅ | ⚠️ | ✅ | Linux/Cloudways |
| `cpanel/setup-site.sh` | ❌ | ❌ | ✅ | ❌ | cPanel only (as the site user) |
| `cpanel/pm2-boot-service.sh` | ❌ | ❌ | ✅ | ❌ | cPanel only (root, systemd) |
| `cpanel/generate-deploy-key.sh` | ✅ | ✅ | ✅ | ❌ | Any shell with ssh-keygen |

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

**Q: What if my project uses PostgreSQL instead of MySQL?**
A: Backups use Strapi's own export/import, which works with any database Strapi supports. Only the safety dump before an import is MySQL-only.

**Q: Can I customize the scripts for my specific needs?**
A: Absolutely! Fork the repository and modify as needed. The scripts are designed to be readable and maintainable.

**Q: How do I update the toolkit after installation?**
A: Run `bash strapi-toolkit/update.sh` (add `--yes` in CI) or re-run the installer.

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
