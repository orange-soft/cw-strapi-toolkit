# Strapi Workflow Examples

Common workflows for managing Strapi across different environments.

---

## Workflow 1: Migrate Data from Legacy Server to Cloudways

### Step 1: Export from Legacy Server

```bash
# SSH into legacy server
ssh admin@legacy-server

# Export Strapi data
bash scripts/backup/export.sh --output ./backups

# Result: backup-YYYYMMDD_HHMMSS.tar.gz created
```

### Step 2: Download to Local Machine

```bash
# From your local machine, download from legacy server
scp admin@legacy-server:~/backups/backup-20251030_150000.tar.gz ./
```

### Step 3: Upload to Cloudways

```bash
# From your local machine
bash scripts/cloudways/sync-to-cloudways.sh \
  --file=backup-20251030_150000.tar.gz \
  --host=server.cloudways.com \
  --port=22000 \
  --user=master \
  --dest=backups/
```

### Step 4: Import on Cloudways

```bash
# SSH into Cloudways
ssh -p 22000 master@server.cloudways.com

# Navigate to app directory
cd applications/xxx/public_html/gocomm-strapi

# Import data
bash scripts/backup/import.sh --file=~/backups/backup-20251030_150000.tar.gz
```

---

## Workflow 2: Local Development with Production Data

### Step 1: Get Production Data

```bash
# SSH into Cloudways production
ssh -p 22000 master@cloudways-prod

# Export data
cd applications/xxx/public_html/gocomm-strapi
bash scripts/backup/export.sh --output ~/backups

# Result: backup-20251030_160000.tar.gz
```

### Step 2: Download to Local

```bash
# From local machine
scp -P 22000 master@cloudways-prod:~/backups/backup-20251030_160000.tar.gz ./
```

### Step 3: Import Locally

```bash
# On local machine (macOS)
cd ~/Projects/gocomm-strapi

# Import production data
bash scripts/backup/import.sh --file=./backup-20251030_160000.tar.gz
```

### Step 4: Develop Locally

```bash
# Start development server
npm run develop

# Make your changes...
# Test locally at http://localhost:1337/admin
```

---

## Workflow 3: Upload Local Changes to Cloudways

### Step 1: Export Local Data (after changes)

```bash
# On local machine
bash scripts/backup/export.sh --output ./

# Result: backup-20251030_170000.tar.gz
```

### Step 2: Upload to Cloudways

```bash
# Upload using sync script
bash scripts/cloudways/sync-to-cloudways.sh \
  --file=backup-20251030_170000.tar.gz \
  --profile=production
```

### Step 3: Import on Cloudways

```bash
# SSH into Cloudways
ssh -p 22000 master@cloudways-prod

# Import
cd applications/xxx/public_html/gocomm-strapi
bash scripts/backup/import.sh --file=~/backup-20251030_170000.tar.gz
```

---

## Workflow 4: Upgrade Strapi Version

### Step 1: Backup Production Data

```bash
# On Cloudways
bash scripts/backup/export.sh --output ~/backups
# Download to local (see Workflow 2)
```

### Step 2: Upgrade Locally

```bash
# On local machine
npm install @strapi/strapi@latest
npm install

# Test the upgrade
npm run develop
```

### Step 3: Push Code Changes to GitHub

```bash
git add package.json package-lock.json
git commit -m "Upgrade Strapi to v5.10.0"
git push origin gocomm.cms.my
```

### Step 4: Deploy to Cloudways

```bash
# GitHub Actions will automatically:
# 1. Sync code to server
# 2. Run npm ci
# 3. Build Strapi
# 4. Restart PM2

# Or manually on server:
ssh -p 22000 master@cloudways-prod
cd applications/xxx/public_html/gocomm-strapi
git pull origin gocomm.cms.my
bash scripts/deploy/build-and-restart.sh
```

---

## Workflow 5: Quick File Transfer to Cloudways

### Upload Single File

```bash
# Upload backup file
bash scripts/cloudways/sync-to-cloudways.sh --file=backup.tar.gz

# Upload to specific location
bash scripts/cloudways/sync-to-cloudways.sh \
  --file=backup.tar.gz \
  --dest=applications/xxx/public_html/gocomm-strapi/
```

### Upload Directory

```bash
# Upload entire directory
bash scripts/cloudways/sync-to-cloudways.sh \
  --file=./my-files/ \
  --dest=uploads/ \
  --verbose
```

---

## Workflow 6: Emergency Rollback

### Step 1: Export Current State (before rollback)

```bash
# On Cloudways
bash scripts/backup/export.sh --output ~/emergency-backup
```

### Step 2: Import Previous Backup

```bash
# Import older backup
bash scripts/backup/import.sh --file=~/backups/backup-20251029_120000.tar.gz
```

### Step 3: Restart Application

```bash
bash scripts/pm2/pm2-manager.sh restart
```

---

## Quick Reference

### Backup Operations
```bash
# Export
bash scripts/backup/export.sh

# Import
bash scripts/backup/import.sh --file=backup.tar.gz
```

### File Transfer
```bash
# Upload to Cloudways
bash scripts/cloudways/sync-to-cloudways.sh --file=myfile.tar.gz
```

### PM2 Operations
```bash
# Status
bash scripts/pm2/pm2-manager.sh status

# Restart
bash scripts/pm2/pm2-manager.sh restart

# Logs
bash scripts/pm2/pm2-manager.sh logs 50
```

### Deployment
```bash
# Full deployment
bash scripts/deploy/build-and-restart.sh
```
