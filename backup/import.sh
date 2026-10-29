#!/bin/bash
set -e

# Script: Strapi Backup Import
# Description: Downloads and imports Strapi backup data with validation and extraction

# Auto-detect NVM location (local, cPanel, Cloudways, or custom)
# Cloudways master home: /home/master, or /mnt/BLOCKSTORAGE/home/master on block storage servers
CW_MASTER_HOME=""
for dir in /home/master /mnt/BLOCKSTORAGE/home/master; do
    if [ -s "${dir}/.nvm/nvm.sh" ]; then
        # Real path: /home/master may be a symlink, which nvm rejects
        CW_MASTER_HOME="$(cd "${dir}" && pwd -P)"
        break
    fi
done

if [ -n "$NVM_DIR" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
    # NVM_DIR already set and valid
    \. "$NVM_DIR/nvm.sh"
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
    # Standard location (macOS/Linux local, cPanel per-user)
    export NVM_DIR="$HOME/.nvm"
    \. "$NVM_DIR/nvm.sh"
elif [ -n "${CW_MASTER_HOME}" ]; then
    # Cloudways location
    export NVM_DIR="${CW_MASTER_HOME}/.nvm"
    \. "$NVM_DIR/nvm.sh"
    # Setup Cloudways-specific paths
    export PATH="${CW_MASTER_HOME}/bin:${CW_MASTER_HOME}/bin/npm/lib/node_modules/bin:${PATH}"

    # Override HOME to public_html
    # On Cloudways, the default HOME is owned by root, we need to use public_html instead
    # Detect if we're in an app directory (has package.json)
    if [ -f "$(pwd)/package.json" ]; then
        # We're in app directory, set HOME to parent (public_html)
        export HOME="$(dirname "$(pwd)")"
    elif [[ "$(pwd)" == */public_html ]]; then
        # We're already in public_html
        export HOME="$(pwd)"
    else
        # Fallback: try to find public_html in the path
        CURRENT_PATH="$(pwd)"
        if [[ "$CURRENT_PATH" == */public_html/* ]]; then
            export HOME="${CURRENT_PATH%%/public_html/*}/public_html"
        fi
    fi

    # Use per-app npm cache to avoid permission conflicts in multi-tenant environment
    export NPM_CONFIG_CACHE="${HOME}/.npm"
elif [ -s "/opt/nvm/nvm.sh" ]; then
    # Legacy shared NVM (cPanel servers before per-user ~/.nvm)
    export NVM_DIR="/opt/nvm"
    \. "$NVM_DIR/nvm.sh"
else
    echo "⚠️  Warning: NVM not found, using system Node/NPM"
fi

# Use Node version from .nvmrc if present and NVM is loaded
if [ -f ".nvmrc" ] && command -v nvm &> /dev/null; then
    NODE_VERSION=$(cat .nvmrc | tr -d '[:space:]')
    nvm use ${NODE_VERSION} 2>/dev/null || nvm install ${NODE_VERSION}
fi

# Default configuration
LOCAL_FILE=""
BACKUP_URL=""
WITH_CONFIG=false
RECREATE_TABLES=false

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME_DIR="$(basename "$PWD")"
# Server: deployed apps have .deploy-info (written by the deploy only) and live
# in public_html, on cPanel and Cloudways alike. Anything else is a development machine.
if [ -f .deploy-info ] || [[ "$PWD" == */public_html/* ]]; then
  ON_SERVER=true
  # The deploy's pre-deploy dumps folder: private_html next to public_html (the
  # app user's home on both server types), outside the web root and never touched
  # by deploys. Taken from the app's path, not $HOME (overridden on Cloudways) or
  # the login user (SSH as the Cloudways master user has another home).
  if [[ "$PWD" == */public_html/* ]]; then
    PRIVATE_DIR="${PWD%%/public_html/*}/private_html"
  else
    PRIVATE_DIR="$(eval echo "~$(id -un)")/private_html"
  fi
  SAFE_DIR="${PRIVATE_DIR}/strapi-backups/${APP_NAME_DIR}"
else
  ON_SERVER=false
  # Ignored by git and excluded from deploy rsync
  SAFE_DIR="$PWD/backups"
fi

# Color codes for output (if terminal supports it)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  GREEN=''
  YELLOW=''
  RED=''
  BLUE=''
  NC=''
fi

# Error handler
error_exit() {
  echo -e "${RED}[✗] Error: $1${NC}"
  exit 1
}

# Success message
success_msg() {
  echo -e "${GREEN}[✓] $1${NC}"
}

# Info message
info_msg() {
  echo -e "${BLUE}[→] $1${NC}"
}

# Warning message
warn_msg() {
  echo -e "${YELLOW}[!] $1${NC}"
}

# Value from .env (quotes stripped, values may contain "=")
env_file_value() {
  grep -E "^$1=" .env 2>/dev/null | tail -n 1 | cut -d '=' -f 2- | tr -d '"' | tr -d "'"
}

# Format bytes to human readable (using bash arithmetic, no bc dependency)
format_bytes() {
  local bytes=$1
  # Ensure bytes is a valid number
  if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
    echo "Invalid size"
    return
  fi

  if [ "$bytes" -lt 1024 ]; then
    echo "${bytes} B"
  elif [ "$bytes" -lt 1048576 ]; then
    # Convert to KB with 1 decimal place
    local kb=$((bytes * 10 / 1024))
    echo "$((kb / 10)).$((kb % 10)) KB"
  elif [ "$bytes" -lt 1073741824 ]; then
    # Convert to MB with 1 decimal place
    local mb=$((bytes * 10 / 1048576))
    echo "$((mb / 10)).$((mb % 10)) MB"
  else
    # Convert to GB with 1 decimal place
    local gb=$((bytes * 10 / 1073741824))
    echo "$((gb / 10)).$((gb % 10)) GB"
  fi
}

# Format seconds to human readable
format_duration() {
  local seconds=$1
  local minutes=$((seconds / 60))
  local remaining_seconds=$((seconds % 60))

  if [ $minutes -gt 0 ]; then
    echo "${minutes}m ${remaining_seconds}s"
  else
    echo "${remaining_seconds}s"
  fi
}

# Cleanup function
cleanup() {
  local exit_code=$?

  # Never leave the site down because the script stopped early
  if [ "${APP_STOPPED:-false}" = true ]; then
    APP_STOPPED=false
    warn_msg "Restarting the app..."
    bash "$PM2_MANAGER" restart || true
  fi

  # Clean up downloaded backup file (if we downloaded it)
  if [ -n "$TEMP_DOWNLOADED_FILE" ] && [ -f "$TEMP_DOWNLOADED_FILE" ]; then
    info_msg "Cleaning up downloaded file..."
    rm -f "$TEMP_DOWNLOADED_FILE"
  fi

  # Clean up copied backup file (if we copied it to current dir)
  if [ -n "$TEMP_COPIED_FILE" ] && [ -f "$TEMP_COPIED_FILE" ]; then
    info_msg "Cleaning up copied backup file..."
    rm -f "$TEMP_COPIED_FILE"
  fi

  # IMPORTANT: Do NOT delete BACKUP_FILE (database dump)
  # User needs it to restore if import failed
  if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ] && [ $exit_code -ne 0 ]; then
    echo ""
    warn_msg "Script failed! Database backup preserved at: $BACKUP_FILE"
    warn_msg "To restore, run: gunzip < $BACKUP_FILE | mysql -u \$DB_USER -p \$DB_NAME"
  fi
}

# Set trap for cleanup on exit, interruption, and termination
trap cleanup EXIT INT TERM

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --file=*)
      LOCAL_FILE="${1#*=}"
      shift
      ;;
    --file)
      LOCAL_FILE="$2"
      shift 2
      ;;
    --with-config)
      WITH_CONFIG=true
      shift
      ;;
    --recreate-tables)
      RECREATE_TABLES=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [URL | FILE] [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --file=PATH     Use a local backup file instead of downloading from URL"
      echo "  --file PATH     Alternative syntax for local file"
      echo "  --with-config   Also import the backup's settings, webhooks and plugin settings"
      echo "                  (e.g. Meilisearch host and keys). Default: on servers yes, on a"
      echo "                  development machine no, so it never talks to production services"
      echo "  --recreate-tables"
      echo "                  MySQL: drop ALL tables first so Strapi recreates them (use with the"
      echo "                  utf8mb4 conversion). Not rolled back if the import fails"
      echo "  -h, --help      Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 'https://…'                        # Download URL, e.g. from export.sh --link (quote it)"
      echo "  $0 ./backups/backup-1793279099.tar.gz # Local archive"
      echo "  $0                                    # Prompts for a URL"
      exit 0
      ;;
    http://*|https://*)
      BACKUP_URL="$1"
      shift
      ;;
    -*)
      echo -e "${RED}[✗] Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
    *)
      # A plain argument is a local archive (tab completion works)
      LOCAL_FILE="$1"
      shift
      ;;
  esac
done

echo "========================================"
echo "    Strapi Backup Import"
echo "    Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

START_TIME=$(date +%s)

# Pre-flight checks
info_msg "Running pre-flight checks..."

# Check if package.json exists
if [ ! -f "package.json" ]; then
  error_exit "package.json not found. Are you in a Strapi project directory?"
fi
success_msg "Strapi project detected"

# Check if npm is available
if ! command -v npm &> /dev/null; then
  error_exit "npm is not installed or not in PATH"
fi
success_msg "npm is available"

# Check if strapi import script exists
if ! grep -q '"strapi"' package.json; then
  error_exit "Strapi not found in package.json"
fi
success_msg "Strapi import command verified"

# Before downloading anything: the import needs this app's database settings
if [ ! -f ".env" ]; then
  error_exit ".env not found: this app needs its database settings before importing (start from .env.example)"
fi
success_msg ".env found"

echo ""

# Determine if using local file or downloading from URL
if [ -n "$LOCAL_FILE" ]; then
  # Local file mode
  info_msg "Using local file: $LOCAL_FILE"

  # Verify local file exists
  if [ ! -f "$LOCAL_FILE" ]; then
    error_exit "Local file not found: $LOCAL_FILE"
  fi
  success_msg "Local file found"

  # Get absolute path
  IMPORT_FILE="$(cd "$(dirname "$LOCAL_FILE")" && pwd)/$(basename "$LOCAL_FILE")"
  FILENAME=$(basename "$LOCAL_FILE")

  FILE_SIZE=$(stat -f%z "$IMPORT_FILE" 2>/dev/null || stat -c%s "$IMPORT_FILE" 2>/dev/null)
  FILE_SIZE_FORMATTED=$(format_bytes $FILE_SIZE)
  info_msg "File size: $FILE_SIZE_FORMATTED"

else
  # URL download mode
  # Check if curl is available
  if ! command -v curl &> /dev/null; then
    error_exit "curl is not installed or not in PATH"
  fi
  success_msg "curl is available"

  # Prompt for URL
  if [ -z "$BACKUP_URL" ]; then
    read -p "Enter the backup file URL: " BACKUP_URL
  fi

  if [ -z "$BACKUP_URL" ]; then
    error_exit "No URL provided"
  fi

  # Without the query: a presigned URL's signature lets anyone download the backup
  info_msg "Backup URL: ${BACKUP_URL%%\?*}"

  # Extract filename from URL
  FILENAME=$(basename "$BACKUP_URL" | sed 's/?.*//')

  if [ -z "$FILENAME" ]; then
    error_exit "Could not extract filename from URL"
  fi

  info_msg "Detected filename: $FILENAME"

  # Get script directory
  mkdir -p "$SAFE_DIR" || error_exit "Cannot create $SAFE_DIR"
  DOWNLOAD_PATH="$SAFE_DIR/$FILENAME"

  echo ""
  info_msg "Downloading backup file..."

  # Download the file with progress and capture HTTP status
  HTTP_CODE=$(curl -L -o "$DOWNLOAD_PATH" --progress-bar -w "%{http_code}" "$BACKUP_URL")

  if [ "$HTTP_CODE" -ge 400 ]; then
    # Clean up failed download
    rm -f "$DOWNLOAD_PATH"
    error_exit "Download failed with HTTP status $HTTP_CODE. Please check the URL."
  fi

  if [ "$HTTP_CODE" -ge 300 ] && [ "$HTTP_CODE" -lt 400 ]; then
    warn_msg "Received redirect status $HTTP_CODE, but curl followed it"
  fi

  success_msg "Download completed (HTTP $HTTP_CODE)"

  TEMP_DOWNLOADED_FILE="$DOWNLOAD_PATH"

  # Verify file exists and get size
  if [ ! -f "$DOWNLOAD_PATH" ]; then
    error_exit "Downloaded file not found: $DOWNLOAD_PATH"
  fi

  FILE_SIZE=$(stat -f%z "$DOWNLOAD_PATH" 2>/dev/null || stat -c%s "$DOWNLOAD_PATH" 2>/dev/null)
  FILE_SIZE_FORMATTED=$(format_bytes $FILE_SIZE)
  info_msg "Downloaded file size: $FILE_SIZE_FORMATTED"

  # Validate file size (should be at least 1KB for a real backup)
  MIN_SIZE=1024  # 1KB
  if [ "$FILE_SIZE" -lt "$MIN_SIZE" ]; then
    error_exit "Downloaded file is too small ($FILE_SIZE_FORMATTED). This is likely an error page, not a backup file. Please verify the URL is correct and the file is accessible."
  fi

  # Validate file type
  info_msg "Validating file format..."

  # Check if it's a valid tar or gzip file
  FILE_TYPE=$(file -b "$DOWNLOAD_PATH" 2>/dev/null || echo "unknown")

  if [[ "$FILENAME" == *.tar.gz ]] || [[ "$FILENAME" == *.gz ]]; then
    # Should be gzip format
    if ! echo "$FILE_TYPE" | grep -qi "gzip"; then
      error_exit "File is not in gzip format (detected: $FILE_TYPE). The URL may be returning an error page instead of the backup file."
    fi
    success_msg "Validated as gzip file"
  elif [[ "$FILENAME" == *.tar ]]; then
    # Should be tar format
    if ! echo "$FILE_TYPE" | grep -qi "tar\|posix"; then
      error_exit "File is not in tar format (detected: $FILE_TYPE). The URL may be returning an error page instead of the backup file."
    fi
    success_msg "Validated as tar file"
  else
    warn_msg "Unknown file extension. Detected format: $FILE_TYPE"
  fi

  IMPORT_FILE="$DOWNLOAD_PATH"
fi

# Check if file is gzipped

if [[ "$FILENAME" == *.gz ]]; then
  echo ""
  info_msg "Detected .gz file, extracting..."

  # Extract filename without .gz extension
  EXTRACTED_FILENAME="${FILENAME%.gz}"

  # Get directory where the file is located (either script dir or local file dir)
  FILE_DIR="$(dirname "$IMPORT_FILE")"
  EXTRACTED_PATH="$FILE_DIR/$EXTRACTED_FILENAME"

  # Extract the file
  if gunzip -c "$IMPORT_FILE" > "$EXTRACTED_PATH"; then
    success_msg "Extraction completed"

    # Get extracted file size
    EXTRACTED_SIZE=$(stat -f%z "$EXTRACTED_PATH" 2>/dev/null || stat -c%s "$EXTRACTED_PATH" 2>/dev/null)
    EXTRACTED_SIZE_FORMATTED=$(format_bytes $EXTRACTED_SIZE)
    info_msg "Extracted file size: $EXTRACTED_SIZE_FORMATTED"

    # Clean up the .gz file only if it was downloaded (not if it's a local file)
    if [ -z "$LOCAL_FILE" ]; then
      info_msg "Removing compressed file..."
      rm -f "$IMPORT_FILE"
      TEMP_DOWNLOADED_FILE="$EXTRACTED_PATH"
    fi

    # Use extracted file for import
    IMPORT_FILE="$EXTRACTED_PATH"
  else
    error_exit "Failed to extract .gz file"
  fi
fi

# Get the import filename
IMPORT_FILENAME=$(basename "$IMPORT_FILE")

# Media files: an import with media makes Strapi delete every existing media
# file through the upload provider before restoring the backup's. On R2/S3
# sites that is the live bucket (also from a development machine whose .env
# has the bucket's keys), so these sites never import media: their media is
# backed up and restored separately. Archives without media (export.sh
# --no-media, R2/S3 sites) skip it too. Media library records are always
# imported and keep pointing at the existing files.
EXCLUDE=()
if grep -q '"@strapi/provider-upload-aws-s3"' package.json && [ -n "$(env_file_value AWS_BUCKET)" ]; then
  EXCLUDE_MEDIA_REASON="this site stores media in R2/S3 (bucket: $(env_file_value AWS_BUCKET)), media files are never imported"
elif [[ "$IMPORT_FILENAME" == *.tar ]] && ! tar -tf "$IMPORT_FILE" 2>/dev/null | grep -q '^assets/uploads/'; then
  EXCLUDE_MEDIA_REASON="the backup has no media files"
else
  EXCLUDE_MEDIA_REASON=""
fi
[ -n "$EXCLUDE_MEDIA_REASON" ] && EXCLUDE+=(files)

# Settings (core store: admin settings, plugin settings such as the
# Meilisearch host and indexing key) and webhooks. A development machine
# keeps its own, otherwise editing content there would update production's
# search index and fire production webhooks.
if [ "$WITH_CONFIG" = false ] && [ "$ON_SERVER" = false ]; then
  EXCLUDE+=(config)
fi

IMPORT_ARGS=(-f "$IMPORT_FILENAME" --force)
if [ ${#EXCLUDE[@]} -gt 0 ]; then
  IMPORT_ARGS+=(--exclude "$(IFS=,; echo "${EXCLUDE[*]}")")
fi

# Ensure the file is in the current working directory for Strapi to find it
CURRENT_DIR=$(pwd)
TARGET_FILE="$CURRENT_DIR/$IMPORT_FILENAME"

# If the file is not in the current directory, copy it here
if [ "$IMPORT_FILE" != "$TARGET_FILE" ]; then
  info_msg "Copying backup file to current directory..."
  cp "$IMPORT_FILE" "$TARGET_FILE" || error_exit "Failed to copy backup file to current directory"
  success_msg "File copied to: $TARGET_FILE"

  # Mark this file for cleanup if it was copied
  TEMP_COPIED_FILE="$TARGET_FILE"
fi

echo ""
echo "========================================"
echo "    Database Backup (Safety)"
echo "========================================"
echo ""

# Extract database credentials from .env
info_msg "Reading database credentials from .env..."

if [ ! -f ".env" ]; then
  error_exit ".env file not found"
fi

DB_CLIENT=$(env_file_value DATABASE_CLIENT)
DB_HOST=$(env_file_value DATABASE_HOST)
DB_PORT=$(env_file_value DATABASE_PORT)
DB_NAME=$(env_file_value DATABASE_NAME)
DB_USER=$(env_file_value DATABASE_USERNAME)
DB_PASS=$(env_file_value DATABASE_PASSWORD)

# Set defaults
DB_CLIENT=${DB_CLIENT:-mysql}
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-3306}

info_msg "Database: ${DB_NAME:-(default)} (${DB_CLIENT})"

if [ "$RECREATE_TABLES" = true ] && [ "$DB_CLIENT" != "mysql" ]; then
  error_exit "--recreate-tables only works with MySQL"
fi

if [ "$DB_CLIENT" = "mysql" ]; then
  # Validate required fields
  [ -n "$DB_NAME" ] || error_exit "DATABASE_NAME not found in .env"
  [ -n "$DB_USER" ] || error_exit "DATABASE_USERNAME not found in .env"

  # Check if mysql/mysqldump are available
  if ! command -v mysql &> /dev/null || ! command -v mysqldump &> /dev/null; then
    error_exit "mysql/mysqldump not found. Please install MySQL client tools (macOS: brew install mysql-client)."
  fi

  # Password through the environment: on the command line other users of a
  # shared server could read it in the process list
  export MYSQL_PWD="$DB_PASS"
  MYSQL_CMD="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER"
  MYSQLDUMP_CMD="mysqldump -h $DB_HOST -P $DB_PORT -u $DB_USER"

  # Test database connection
  info_msg "Testing database connection..."
  if ! $MYSQL_CMD -e "SELECT 1" $DB_NAME &> /dev/null; then
    error_exit "Cannot connect to database. Please check your credentials."
  fi
  success_msg "Database connection successful"

  echo ""
  info_msg "Creating database backup before import..."

  mkdir -p "$SAFE_DIR" || error_exit "Cannot create $SAFE_DIR"
  BACKUP_FILE="$SAFE_DIR/db-dump-$(date +%s).sql.gz"

  # Create backup
  $MYSQLDUMP_CMD --single-transaction --quick --lock-tables=false $DB_NAME | gzip > "$BACKUP_FILE" || {
    error_exit "Database backup failed"
  }

  BACKUP_SIZE=$(wc -c < "$BACKUP_FILE" | tr -d ' ')
  if [ "$BACKUP_SIZE" -lt 100 ]; then
    error_exit "Backup file is suspiciously small ($BACKUP_SIZE bytes)"
  fi

  BACKUP_SIZE_FORMATTED=$(format_bytes $BACKUP_SIZE)
  success_msg "Database backup created: $BACKUP_FILE ($BACKUP_SIZE_FORMATTED)"
fi

PM2_MANAGER="$TOOLKIT_DIR/pm2/pm2-manager.sh"
STOP_APP=false
if [ "$ON_SERVER" = true ] && [ -f "$PM2_MANAGER" ] && { [ -f ecosystem.config.cjs ] || [ -f ecosystem.config.js ]; }; then
  STOP_APP=true
fi

echo ""
echo "========================================"
echo "    Import Confirmation"
echo "========================================"
echo ""
warn_msg "This replaces the content of ${DB_NAME:-the database} with the backup: $TARGET_FILE"
if [ "$RECREATE_TABLES" = true ]; then
  warn_msg "--recreate-tables: ALL tables in '$DB_NAME' are dropped first. If the import then fails, restore the safety dump."
else
  info_msg "Strapi imports in one transaction: if the import fails, it is rolled back"
fi
if [ -n "$EXCLUDE_MEDIA_REASON" ]; then
  info_msg "Media files: left untouched ($EXCLUDE_MEDIA_REASON)"
else
  warn_msg "Media files: ALL current media files are deleted and replaced by the backup's"
fi
if [[ " ${EXCLUDE[*]} " == *" config "* ]]; then
  info_msg "Settings, webhooks, plugin settings: this machine keeps its own (--with-config to import them)"
else
  warn_msg "Settings, webhooks, plugin settings (e.g. Meilisearch host and keys): taken from the backup"
fi
if [ "$STOP_APP" = true ]; then
  warn_msg "The app is stopped during the import (PM2) and restarted after"
elif [ "$ON_SERVER" = false ]; then
  info_msg "Stop 'npm run develop' first if it is running"
fi
if [ -n "$BACKUP_FILE" ]; then
  echo ""
  info_msg "Safety dump: $BACKUP_FILE"
  echo "  Restore with: gunzip < $BACKUP_FILE | mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p $DB_NAME"
fi
echo ""

read -p "Continue with the import? (yes/NO): " CONFIRM
if [[ ! "${CONFIRM:-no}" =~ ^[Yy][Ee][Ss]$ ]]; then
  info_msg "Import cancelled by user"
  exit 0
fi

if [ "$RECREATE_TABLES" = true ]; then
  echo ""
  echo "========================================"
  echo "    Clearing Database"
  echo "========================================"
  echo ""

  info_msg "Dropping all tables..."

  # Get all table names
  TABLES=$($MYSQL_CMD -N -e "SHOW TABLES" $DB_NAME 2>/dev/null)

  if [ -n "$TABLES" ]; then
    # Count tables
    TABLE_COUNT=$(echo "$TABLES" | wc -l | tr -d ' ')
    info_msg "Found $TABLE_COUNT tables to drop"

    # Build DROP TABLE statement (batch drop for efficiency)
    DROP_STATEMENT="SET FOREIGN_KEY_CHECKS=0; DROP TABLE IF EXISTS "
    FIRST=true
    while IFS= read -r table; do
      if [ "$FIRST" = true ]; then
        DROP_STATEMENT="${DROP_STATEMENT}\`$table\`"
        FIRST=false
      else
        DROP_STATEMENT="${DROP_STATEMENT}, \`$table\`"
      fi
    done <<< "$TABLES"
    DROP_STATEMENT="${DROP_STATEMENT}; SET FOREIGN_KEY_CHECKS=1;"

    # Execute drop
    $MYSQL_CMD $DB_NAME -e "$DROP_STATEMENT" 2>/dev/null || {
      error_exit "Failed to drop tables"
    }

    # Verify all tables are dropped
    REMAINING_TABLES=$($MYSQL_CMD -N -e "SHOW TABLES" $DB_NAME 2>/dev/null)
    if [ -n "$REMAINING_TABLES" ]; then
      warn_msg "Some tables could not be dropped:"
      echo "$REMAINING_TABLES"
      error_exit "Database cleanup incomplete"
    fi

    success_msg "All tables dropped successfully"
  else
    info_msg "No tables to drop (database is empty)"
  fi

  echo ""
  echo "========================================"
  echo "    Database Encoding Check"
  echo "========================================"
  echo ""

  info_msg "Checking database default encoding before import..."

  # Get database-level encoding and collation
  DB_CHARSET=$($MYSQL_CMD -N -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)
  DB_COLLATION=$($MYSQL_CMD -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)

  info_msg "Current database defaults: $DB_CHARSET / $DB_COLLATION"

  # Check if database needs conversion
  if [ "$DB_CHARSET" != "utf8mb4" ] || [ "$DB_COLLATION" != "utf8mb4_unicode_ci" ]; then
    echo ""
    warn_msg "Database default encoding is not utf8mb4/utf8mb4_unicode_ci"
    warn_msg "Imported data may have issues with emoji and unicode characters"
    echo ""
    echo "Options:"
    echo "  [1] Convert database to utf8mb4/utf8mb4_unicode_ci (recommended)"
    echo "  [2] Continue without conversion (may cause data corruption)"
    echo "  [3] Cancel import"
    echo ""
    read -p "Enter your choice (1-3): " ENCODING_CHOICE

    case $ENCODING_CHOICE in
      1)
        info_msg "Converting database to utf8mb4/utf8mb4_unicode_ci..."
        $MYSQL_CMD -e "ALTER DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" 2>/dev/null || {
          error_exit "Failed to convert database encoding"
        }

        # Verify conversion
        NEW_DB_CHARSET=$($MYSQL_CMD -N -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)
        NEW_DB_COLLATION=$($MYSQL_CMD -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)

        if [ "$NEW_DB_CHARSET" != "utf8mb4" ] || [ "$NEW_DB_COLLATION" != "utf8mb4_unicode_ci" ]; then
          error_exit "Database conversion verification failed"
        fi

        success_msg "Database converted to utf8mb4/utf8mb4_unicode_ci"
        info_msg "Imported tables will use utf8mb4/utf8mb4_unicode_ci"
        ;;
      2)
        warn_msg "Continuing without encoding conversion"
        warn_msg "Imported data may be corrupted if it contains emoji or special unicode"
        ;;
      3)
        info_msg "Import cancelled by user"
        exit 0
        ;;
      *)
        error_exit "Invalid choice: $ENCODING_CHOICE"
        ;;
    esac
  else
    success_msg "Database encoding is correct (utf8mb4/utf8mb4_unicode_ci)"
    info_msg "Imported tables will use utf8mb4/utf8mb4_unicode_ci"
  fi

fi

if [ "$STOP_APP" = true ]; then
  echo ""
  bash "$PM2_MANAGER" stop || error_exit "Could not stop the app"
  APP_STOPPED=true
fi

echo ""
echo "========================================"
echo "    Running Strapi Import"
echo "========================================"
echo ""

info_msg "Starting import with DATA_IMPORT_MODE enabled..."
echo ""

# DATA_IMPORT_MODE lets an app's database config raise innodb_lock_wait_timeout
# for this long transaction (only if the app reads it; the boilerplate doesn't)
IMPORT_STATUS=0
DATA_IMPORT_MODE=true npm run strapi import -- "${IMPORT_ARGS[@]}" || IMPORT_STATUS=$?

if [ "$STOP_APP" = true ]; then
  echo ""
  APP_STOPPED=false
  bash "$PM2_MANAGER" restart || warn_msg "The app did not come back up, check: bash $PM2_MANAGER logs"
fi

if [ "$IMPORT_STATUS" -ne 0 ]; then
  echo ""
  if [ "$RECREATE_TABLES" = true ]; then
    error_exit "Backup import failed after the tables were dropped. Restore the safety dump: $BACKUP_FILE"
  fi
  error_exit "Backup import failed and was rolled back by Strapi. If anything looks wrong, restore the safety dump: ${BACKUP_FILE:-(none, not MySQL)}"
fi

echo ""
success_msg "Import completed successfully"

# Verify import success (MySQL only)
if [ "$DB_CLIENT" = "mysql" ]; then
  echo ""
  info_msg "Verifying import..."

  TABLE_COUNT=$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB_NAME'" 2>/dev/null)

  if [ "$TABLE_COUNT" -gt 0 ]; then
    success_msg "Import verification passed ($TABLE_COUNT tables created)"
  else
    warn_msg "No tables found after import (this may be normal for empty backups)"
  fi
fi

# Clean up the copied file after successful import
if [ -n "$TEMP_COPIED_FILE" ] && [ -f "$TEMP_COPIED_FILE" ]; then
  info_msg "Cleaning up copied backup file..."
  rm -f "$TEMP_COPIED_FILE"
fi

echo ""
success_msg "Import completed successfully!"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_FORMATTED=$(format_duration $DURATION)

echo ""
echo "========================================"
echo "    Import Summary"
echo "========================================"
if [ -n "$BACKUP_URL" ]; then
  echo "Source: ${BACKUP_URL%%\?*}"
else
  echo "Source: Local file"
fi
echo "File: $IMPORT_FILE"
if [ -n "$BACKUP_FILE" ]; then
  echo "Database backup: $BACKUP_FILE"
fi
echo "Duration: $DURATION_FORMATTED"
echo "========================================"
if [ -n "$BACKUP_FILE" ]; then
  echo ""
  info_msg "Database backup preserved at: $BACKUP_FILE"
  info_msg "You can safely delete it after verifying the import"
fi
echo ""
