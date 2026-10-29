#!/bin/bash
set -e

# Script: Strapi Backup Export
# Description: Exports Strapi data with enhanced logging, validation, and timing

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
OUTPUT_DIR=""
NO_MEDIA=false
LOCAL_ONLY=false
PRINT_CRON=false
KEEP_LOCAL=false
# Expiry of the --link download URL (empty = no link)
LINK_EXPIRE=""
# Seconds without the archive growing before the export counts as hung (0 = never)
STALL_TIMEOUT=300

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

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --output=*)
      OUTPUT_DIR="${1#*=}"
      shift
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --no-media)
      NO_MEDIA=true
      shift
      ;;
    --local-only)
      LOCAL_ONLY=true
      shift
      ;;
    --print-cron)
      PRINT_CRON=true
      shift
      ;;
    --keep-local)
      KEEP_LOCAL=true
      shift
      ;;
    --link)
      LINK_EXPIRE=24h
      shift
      ;;
    --link=*)
      LINK_EXPIRE="${1#*=}"
      shift
      ;;
    --stall-timeout=*)
      STALL_TIMEOUT="${1#*=}"
      shift
      ;;
    --stall-timeout)
      STALL_TIMEOUT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --output=DIR    Where the local archive goes (default: private_html/strapi-backups/<app>"
      echo "                  on servers, ./backups on a development machine). Never inside public/"
      echo "  --output DIR    Alternative syntax for output directory"
      echo "  --local-only    Keep the backup on this machine, upload nothing. Servers refuse to"
      echo "                  back up without the backup bucket unless this is given"
      echo "  --no-media      Leave media files out (media library records are still included)"
      echo "  --print-cron    Print the crontab line for a daily backup of this app, then exit"
      echo "  --keep-local    Keep the local archive after uploading it to the backup bucket"
      echo "  --link          Print a temporary download URL for the uploaded archive (valid 24h),"
      echo "                  e.g. for import.sh on another server. Anyone with the URL can"
      echo "                  download the database until it expires."
      echo "  --link=DURATION Same, with another expiry (e.g. 1h, 3d; at most 7d)"
      echo "  --stall-timeout=SECONDS"
      echo "                  Stop the export if the archive stops growing for this long"
      echo "                  (default: 300, 0 = never)"
      echo "  -h, --help      Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --link            # production: upload, print a download URL"
      echo "  $0 --local-only      # archive on this machine only"
      echo ""
      echo "Remote backups (BACKUP_R2_* in .env, see .env.example):"
      echo "  The archive is uploaded to <BACKUP_R2_BUCKET>/<app>/db/ and removed locally."
      echo "  Sites with R2/S3 media export the database only and copy the media bucket"
      echo "  to <BACKUP_R2_BUCKET>/<app>/media/ instead."
      echo "  On servers BACKUP_R2_* is required, unless --local-only is given."
      exit 0
      ;;
    *)
      echo -e "${RED}[✗] Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

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

# File size in bytes (0 if missing); wc works the same on macOS and Linux
file_size() {
  if [ -f "$1" ]; then
    wc -c < "$1" | tr -d ' '
  else
    echo 0
  fi
}

# Print a process and all its descendants (npm -> sh -> node strapi)
process_tree() {
  local pid=$1 child
  echo "$pid"
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    process_tree "$child"
  done
}

# Stop the running export: TERM first, KILL whatever is left after 10s
stop_export() {
  local pids pid alive i
  pids=$(process_tree "$EXPORT_PID")
  kill -TERM $pids 2>/dev/null || true
  for i in 1 2 3 4 5 6 7 8 9 10; do
    alive=false
    for pid in $pids; do
      kill -0 "$pid" 2>/dev/null && alive=true
    done
    [ "$alive" = false ] && return
    sleep 1
  done
  kill -KILL $pids 2>/dev/null || true
}

# Value from the environment, else from .env (quotes stripped), like Strapi reads it
env_value() {
  local key=$1
  if [ -n "${!key:-}" ]; then
    echo "${!key}"
    return
  fi
  [ -f .env ] || return 0
  grep -E "^${key}=" .env | tail -n 1 | cut -d '=' -f 2- | tr -d '"' | tr -d "'"
}

# Run the R2/S3 helper (backup/r2-backup.cjs) with the bucket credentials in
# its environment only, so the Strapi export never gets them
backup_tool() {
  (
    export BACKUP_R2_ENDPOINT BACKUP_R2_ACCESS_KEY_ID BACKUP_R2_SECRET_ACCESS_KEY BACKUP_R2_BUCKET
    export MEDIA_S3_ENDPOINT MEDIA_S3_REGION MEDIA_S3_ACCESS_KEY_ID MEDIA_S3_SECRET_ACCESS_KEY MEDIA_S3_BUCKET
    node "$SCRIPT_DIR/r2-backup.cjs" "$@"
  )
}

# Remove the half-written archive of this run
remove_partial_archive() {
  rm -f "${BACKUP_FILENAME}.tar.gz" "${BACKUP_FILENAME}.tar"
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
  DEFAULT_OUTPUT_DIR="${PRIVATE_DIR}/strapi-backups/$(basename "$PWD")"
else
  ON_SERVER=false
  # Ignored by git and excluded from deploy rsync
  DEFAULT_OUTPUT_DIR="$PWD/backups"
fi
OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}

if [ "$PRINT_CRON" = true ]; then
  APP_DIR=$(pwd -P)
  LOG_FILE="$DEFAULT_OUTPUT_DIR/export.log"
  # The redirect needs the folder before the script runs
  mkdir -p "$DEFAULT_OUTPUT_DIR" || error_exit "Cannot create $DEFAULT_OUTPUT_DIR"
  # Spread apps on one server over the hour instead of all at 03:00
  MINUTE=$(( $(printf '%s' "$APP_DIR" | cksum | cut -d ' ' -f 1) % 60 ))
  COMMAND="cd '$APP_DIR' && bash strapi-toolkit/backup/export.sh > '$LOG_FILE' 2>&1 || cat '$LOG_FILE'"

  echo "Daily backup of $(basename "$APP_DIR") at 03:$(printf '%02d' "$MINUTE") (server time):"
  echo ""
  echo "$MINUTE 3 * * * $COMMAND"
  echo ""
  echo "  cPanel:    Cron Jobs -> Add New Cron Job (minute $MINUTE, hour 3, command above),"
  echo "             or crontab -e and paste the whole line. Set \"Cron Email\": cron mails"
  echo "             the output only when a backup fails (it is quiet on success)."
  echo "  Cloudways: Application -> Cron Job Management -> paste the whole line."
  echo ""
  echo "  Each run's output: $LOG_FILE"
  if [ -n "$(env_value BACKUP_HEARTBEAT_URL)" ]; then
    echo "  Monitoring: BACKUP_HEARTBEAT_URL is set, every successful backup pings it."
  else
    echo "  Monitoring: set BACKUP_HEARTBEAT_URL in .env (e.g. a healthchecks.io check,"
    echo "  period 1 day). Every successful backup pings it, and the service alerts you"
    echo "  when a ping doesn't arrive: a failed backup or a cron that stopped running."
  fi
  echo ""
  echo "  Try it once now (same backup, output on screen):"
  echo "    cd '$APP_DIR' && bash strapi-toolkit/backup/export.sh"
  if [ "$ON_SERVER" = false ]; then
    echo ""
    warn_msg "This looks like a development machine (no .deploy-info, not in public_html): meant for the server's crontab"
  fi
  exit 0
fi

echo "========================================"
echo "    Strapi Backup Export"
echo "    Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

START_TIME=$(date +%s)
BACKUP_FILENAME="backup-${START_TIME}"

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

# Check if strapi export script exists
if ! grep -q '"strapi"' package.json; then
  error_exit "Strapi not found in package.json"
fi
success_msg "Strapi export command verified"

if ! [[ "$STALL_TIMEOUT" =~ ^[0-9]+$ ]]; then
  error_exit "--stall-timeout must be a number of seconds (0 = never): $STALL_TIMEOUT"
fi


# Media stored in R2/S3: Strapi's export would download every file over HTTP and
# can hang forever, so these sites export the database only and copy the bucket
MEDIA_BUCKET=$(env_value AWS_BUCKET)
REMOTE_MEDIA=false
if grep -q '"@strapi/provider-upload-aws-s3"' package.json && [ -n "$MEDIA_BUCKET" ]; then
  REMOTE_MEDIA=true
fi

BACKUP_R2_ENDPOINT=$(env_value BACKUP_R2_ENDPOINT)
BACKUP_R2_ACCESS_KEY_ID=$(env_value BACKUP_R2_ACCESS_KEY_ID)
BACKUP_R2_SECRET_ACCESS_KEY=$(env_value BACKUP_R2_SECRET_ACCESS_KEY)
BACKUP_R2_BUCKET=$(env_value BACKUP_R2_BUCKET)
BACKUP_R2_BUCKET=${BACKUP_R2_BUCKET:-strapi-backup}
BACKUP_APP_NAME=$(env_value BACKUP_APP_NAME)
BACKUP_APP_NAME=${BACKUP_APP_NAME:-$(basename "$PWD")}

if [ -n "$LINK_EXPIRE" ]; then
  if ! [[ "$LINK_EXPIRE" =~ ^([0-9]+)([smhd])$ ]]; then
    error_exit "--link expiry must look like 30m, 24h or 7d: $LINK_EXPIRE"
  fi
  case ${BASH_REMATCH[2]} in
    s) LINK_SECONDS=${BASH_REMATCH[1]} ;;
    m) LINK_SECONDS=$((BASH_REMATCH[1] * 60)) ;;
    h) LINK_SECONDS=$((BASH_REMATCH[1] * 3600)) ;;
    d) LINK_SECONDS=$((BASH_REMATCH[1] * 86400)) ;;
  esac
  # Presigned URLs are valid for at most 7 days
  if [ "$LINK_SECONDS" -lt 1 ] || [ "$LINK_SECONDS" -gt 604800 ]; then
    error_exit "--link expiry must be between 1s and 7d: $LINK_EXPIRE"
  fi
  if [ "$LOCAL_ONLY" = true ]; then
    error_exit "--link needs an uploaded backup, but --local-only keeps it on this machine"
  fi
fi

MISSING_BACKUP_VARS=()
for var in BACKUP_R2_ENDPOINT BACKUP_R2_ACCESS_KEY_ID BACKUP_R2_SECRET_ACCESS_KEY; do
  [ -n "${!var}" ] || MISSING_BACKUP_VARS+=("$var")
done

UPLOAD=false
if [ "$LOCAL_ONLY" = true ]; then
  info_msg "--local-only: the backup stays on this machine, nothing is uploaded"
elif [ ${#MISSING_BACKUP_VARS[@]} -eq 0 ]; then
  UPLOAD=true
elif [ ${#MISSING_BACKUP_VARS[@]} -lt 3 ] || [ "$ON_SERVER" = true ]; then
  # Half-configured, or a server with nowhere off-site to put its backup
  echo ""
  if [ ${#MISSING_BACKUP_VARS[@]} -lt 3 ]; then
    echo -e "${RED}[✗] The remote backup bucket is only partly set up in .env.${NC}"
  else
    echo -e "${RED}[✗] Backups on a server go to the remote backup bucket, which is not set up in .env.${NC}"
  fi
  echo -e "${RED}    Missing: ${MISSING_BACKUP_VARS[*]} (see .env.example)${NC}"
  echo ""
  echo "    Or keep this backup on this machine only:"
  echo "      bash ${BASH_SOURCE[0]} --local-only"
  exit 1
else
  info_msg "BACKUP_R2_* not set in .env: the backup stays on this machine"
fi
[ -n "$LINK_EXPIRE" ] && [ "$UPLOAD" = false ] && error_exit "--link needs the remote backup bucket (BACKUP_R2_* in .env, see .env.example)"

# R2/S3 media is never put in the archive (see above); it is copied to the
# backup bucket instead, unless --no-media
EXCLUDE_MEDIA=false
{ [ "$NO_MEDIA" = true ] || [ "$REMOTE_MEDIA" = true ]; } && EXCLUDE_MEDIA=true
COPY_MEDIA=false
[ "$UPLOAD" = true ] && [ "$REMOTE_MEDIA" = true ] && [ "$NO_MEDIA" = false ] && COPY_MEDIA=true

if [ "$UPLOAD" = true ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BACKUP_DEST="${BACKUP_APP_NAME}"

  if [ "$COPY_MEDIA" = true ]; then
    MEDIA_S3_ENDPOINT=$(env_value AWS_ENDPOINT)
    MEDIA_S3_REGION=$(env_value AWS_REGION)
    MEDIA_S3_ACCESS_KEY_ID=$(env_value AWS_ACCESS_KEY_ID)
    MEDIA_S3_SECRET_ACCESS_KEY=$(env_value AWS_SECRET_ACCESS_KEY)
    MEDIA_S3_BUCKET=$MEDIA_BUCKET
  fi

  # Fail now on wrong credentials or a missing AWS SDK, not after the export
  if [ "$COPY_MEDIA" = true ]; then
    backup_tool check media || error_exit "Remote backup check failed (see above), nothing was exported"
    success_msg "Backup bucket ${BACKUP_R2_BUCKET} and media bucket ${MEDIA_BUCKET} reachable"
  else
    backup_tool check || error_exit "Remote backup check failed (see above), nothing was exported"
    success_msg "Backup bucket ${BACKUP_R2_BUCKET} reachable"
  fi
fi

# Handle output directory
case "$OUTPUT_DIR" in
  /*) ;;
  *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;;
esac
info_msg "Output directory: $OUTPUT_DIR"
# Strapi serves public/ to anyone: a backup there could be downloaded from the site
if [[ "$OUTPUT_DIR/" == "$PWD/public/"* ]]; then
  error_exit "Refusing to write a backup inside public/, which the site serves to anyone: $OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR" || error_exit "Failed to create output directory: $OUTPUT_DIR"
[ -w "$OUTPUT_DIR" ] || error_exit "Output directory is not writable: $OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd -P)

# Same check on the real path (symlinks)
PUBLIC_DIR=$(cd public 2>/dev/null && pwd -P || true)
if [ -n "$PUBLIC_DIR" ] && [[ "$OUTPUT_DIR/" == "$PUBLIC_DIR/"* ]]; then
  error_exit "Refusing to write a backup inside public/, which the site serves to anyone: $OUTPUT_DIR"
fi

echo ""
info_msg "Starting backup export..."
echo ""

EXPORT_ARGS=(-f "$BACKUP_FILENAME" --no-encrypt)
if [ "$EXCLUDE_MEDIA" = true ]; then
  # Media library records still go into the archive (entities stage), only the files are left out
  EXPORT_ARGS+=(--exclude files)
  if [ "$COPY_MEDIA" = true ]; then
    info_msg "Exporting without media files, the media bucket is copied after the export"
  elif [ "$NO_MEDIA" = true ]; then
    warn_msg "--no-media: media files are not in this backup"
  else
    warn_msg "Media files are in R2/S3 and not in this backup (only uploaded backups copy them)"
  fi
  echo ""
fi

# Run the export in the background so a hung export can be detected.
# Strapi can hang forever without exiting (e.g. a remote media file whose
# downloaded size differs from its Content-Length breaks the archive), so watch
# the archive: if it stops growing for STALL_TIMEOUT seconds, stop the export.
npm run strapi export -- "${EXPORT_ARGS[@]}" &
EXPORT_PID=$!
trap 'echo ""; warn_msg "Interrupted, stopping the export..."; stop_export; remove_partial_archive; exit 130' INT TERM

LAST_SIZE=-1
LAST_GROWTH=$(date +%s)
while kill -0 "$EXPORT_PID" 2>/dev/null; do
  sleep 5
  SIZE=$(( $(file_size "${BACKUP_FILENAME}.tar.gz") + $(file_size "${BACKUP_FILENAME}.tar") ))
  NOW=$(date +%s)
  if [ "$SIZE" -ne "$LAST_SIZE" ]; then
    LAST_SIZE=$SIZE
    LAST_GROWTH=$NOW
  elif [ "$STALL_TIMEOUT" -gt 0 ] && [ $((NOW - LAST_GROWTH)) -ge "$STALL_TIMEOUT" ]; then
    echo ""
    warn_msg "No progress for $(format_duration "$STALL_TIMEOUT"), stopping the export..."
    stop_export
    wait "$EXPORT_PID" 2>/dev/null || true
    remove_partial_archive
    if [ "$EXCLUDE_MEDIA" = true ]; then
      error_exit "Backup export hung (no progress for $(format_duration "$STALL_TIMEOUT")). See the Strapi errors above."
    fi
    error_exit "Backup export hung (no progress for $(format_duration "$STALL_TIMEOUT")). If the errors above mention assets, retry with --no-media and back up the media separately."
  fi
done

EXPORT_STATUS=0
wait "$EXPORT_PID" || EXPORT_STATUS=$?
trap - INT TERM
[ "$EXPORT_STATUS" -eq 0 ] || error_exit "Backup export failed"

echo ""
info_msg "Verifying backup file..."

# Find the generated backup file (it might have .tar.gz.enc or .tar.gz extension)
BACKUP_FILE=""
if [ -f "${BACKUP_FILENAME}.tar.gz" ]; then
  BACKUP_FILE="${BACKUP_FILENAME}.tar.gz"
elif [ -f "${BACKUP_FILENAME}.tar" ]; then
  BACKUP_FILE="${BACKUP_FILENAME}.tar"
else
  error_exit "Backup file not found: ${BACKUP_FILENAME}.tar.gz"
fi

# Move to output directory if not already there
if [ "$OUTPUT_DIR" != "$PWD" ]; then
  info_msg "Moving backup to output directory..."
  mv "$BACKUP_FILE" "$OUTPUT_DIR/" || error_exit "Failed to move backup to output directory"
fi

BACKUP_PATH="$OUTPUT_DIR/$BACKUP_FILE"

# Verify the backup file exists
if [ ! -f "$BACKUP_PATH" ]; then
  error_exit "Backup file not found after export: $BACKUP_PATH"
fi

# Get backup file size
BACKUP_SIZE=$(file_size "$BACKUP_PATH")
BACKUP_SIZE_FORMATTED=$(format_bytes $BACKUP_SIZE)

success_msg "Backup archive created: $BACKUP_PATH ($BACKUP_SIZE_FORMATTED)"

if [ "$UPLOAD" = true ]; then
  REMOTE_DB_KEY="${BACKUP_DEST}/db/${BACKUP_FILE}"
  echo ""
  info_msg "Uploading to ${BACKUP_R2_BUCKET}/${REMOTE_DB_KEY}..."
  # Checks the uploaded size and md5 against the local file before we delete it
  UPLOAD_CHECK=$(backup_tool upload "$BACKUP_PATH" "$REMOTE_DB_KEY") \
    || error_exit "Upload failed, the backup is still at: $BACKUP_PATH"
  success_msg "Upload verified ($UPLOAD_CHECK)"

  if [ "$KEEP_LOCAL" = false ]; then
    rm -f "$BACKUP_PATH"
    info_msg "Local archive removed (use --keep-local to keep it)"
  fi

  DOWNLOAD_URL=""
  if [ -n "$LINK_EXPIRE" ]; then
    # Presigned URL: works without credentials until it expires
    DOWNLOAD_URL=$(backup_tool link "$REMOTE_DB_KEY" "$LINK_SECONDS") \
      || warn_msg "Could not create the download link, the backup itself is uploaded"
  fi

  if [ "$COPY_MEDIA" = true ]; then
    # After the database export, so every file the backup refers to is copied.
    # Never overwrites or deletes in the backup (works under a bucket lock):
    # replaced files get a new version in media-versions/
    echo ""
    info_msg "Copying media ${MEDIA_BUCKET} -> ${BACKUP_R2_BUCKET}/${BACKUP_DEST}/media/..."
    backup_tool copy-media "${BACKUP_DEST}" \
      || error_exit "Media copy failed. The database backup is uploaded; re-run to retry (copied files are skipped)."
    success_msg "Media copied"
  fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_FORMATTED=$(format_duration $DURATION)

echo ""
success_msg "Backup completed successfully!"

echo ""
echo "========================================"
echo "    Backup Details"
echo "========================================"
if [ "$UPLOAD" = true ]; then
  echo "Remote: ${BACKUP_R2_BUCKET}/${REMOTE_DB_KEY}"
  [ "$KEEP_LOCAL" = true ] && echo "Local: $BACKUP_PATH"
else
  echo "Location: $BACKUP_PATH"
fi
echo "Size: $BACKUP_SIZE_FORMATTED"
echo "Duration: $DURATION_FORMATTED"
if [ "$COPY_MEDIA" = true ]; then
  echo "Media: ${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}/media/"
elif [ "$EXCLUDE_MEDIA" = true ]; then
  echo "Media: not included"
fi
if [ -n "${DOWNLOAD_URL:-}" ]; then
  echo ""
  echo "Download (valid ${LINK_EXPIRE}, anyone with this URL can download the backup):"
  echo "$DOWNLOAD_URL"
  echo ""
  echo "Restore elsewhere (quotes included): bash strapi-toolkit/backup/import.sh '$DOWNLOAD_URL'"
fi
echo "========================================"
echo ""

# Monitoring: the service alerts when this ping doesn't arrive in time
HEARTBEAT_URL=$(env_value BACKUP_HEARTBEAT_URL)
if [ "$UPLOAD" = true ] && [ -n "$HEARTBEAT_URL" ]; then
  if curl -fsS -m 10 --retry 3 -o /dev/null "$HEARTBEAT_URL"; then
    success_msg "Heartbeat sent"
  else
    warn_msg "Could not send the heartbeat to BACKUP_HEARTBEAT_URL (the backup itself succeeded)"
  fi
fi
