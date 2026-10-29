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
OUTPUT_DIR="."
NO_MEDIA=false
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
      echo "  --output=DIR    Specify output directory for backup (default: current directory)"
      echo "  --output DIR    Alternative syntax for output directory"
      echo "  --no-media      Local backup without media files (database, media library records"
      echo "                  and config only). Nothing is uploaded to the backup bucket."
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
      echo "  $0 --output=./public"
      echo "  $0 --output ./backups"
      echo "  $0 --no-media --output ./backups"
      echo ""
      echo "Remote backups (BACKUP_R2_* in .env, see .env.example):"
      echo "  The archive is uploaded to <BACKUP_R2_BUCKET>/<app>/db/ and removed locally."
      echo "  Sites with R2/S3 media export the database only and copy the media bucket"
      echo "  to <BACKUP_R2_BUCKET>/<app>/media/ instead. They refuse to run without"
      echo "  BACKUP_R2_*, unless --no-media is given."
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

# rclone from PATH, else from the login user's ~/bin (installed without root)
find_rclone() {
  local login_home
  if command -v rclone &> /dev/null; then
    command -v rclone
    return
  fi
  login_home=$(eval echo "~$(id -un)")
  if [ -x "${login_home}/bin/rclone" ]; then
    echo "${login_home}/bin/rclone"
  fi
}

# Run rclone with the RCLONE_CONFIG_* remotes defined in this script
rclone_cmd() {
  (
    export ${!RCLONE_CONFIG_@}
    "$RCLONE" "$@"
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
  if ! [[ "$LINK_EXPIRE" =~ ^[0-9]+[smhd]$ ]]; then
    error_exit "--link expiry must look like 30m, 24h or 7d: $LINK_EXPIRE"
  fi
  if [ "$NO_MEDIA" = true ]; then
    error_exit "--link needs an uploaded backup, but --no-media only makes a local one"
  fi
fi

MISSING_BACKUP_VARS=()
for var in BACKUP_R2_ENDPOINT BACKUP_R2_ACCESS_KEY_ID BACKUP_R2_SECRET_ACCESS_KEY; do
  [ -n "${!var}" ] || MISSING_BACKUP_VARS+=("$var")
done

UPLOAD=false
EXCLUDE_MEDIA=false
if [ "$NO_MEDIA" = true ]; then
  EXCLUDE_MEDIA=true
  info_msg "--no-media: local backup only, nothing is uploaded"
elif [ ${#MISSING_BACKUP_VARS[@]} -eq 0 ]; then
  UPLOAD=true
  [ "$REMOTE_MEDIA" = true ] && EXCLUDE_MEDIA=true
elif [ ${#MISSING_BACKUP_VARS[@]} -lt 3 ] || [ "$REMOTE_MEDIA" = true ]; then
  # Half-configured, or R2 media with nowhere to back it up to
  echo ""
  if [ "$REMOTE_MEDIA" = true ]; then
    echo -e "${RED}[✗] This site stores its media in R2/S3 (bucket: ${MEDIA_BUCKET}), so its backup${NC}"
    echo -e "${RED}    goes to the remote backup bucket, which is not set up in .env.${NC}"
  else
    echo -e "${RED}[✗] The remote backup bucket is only partly set up in .env.${NC}"
  fi
  echo -e "${RED}    Missing: ${MISSING_BACKUP_VARS[*]} (see .env.example)${NC}"
  echo ""
  echo "    Or make a local backup without media files:"
  echo "      bash ${BASH_SOURCE[0]} --no-media"
  exit 1
else
  [ -n "$LINK_EXPIRE" ] && error_exit "--link needs the remote backup bucket (BACKUP_R2_* in .env, see .env.example)"
  info_msg "BACKUP_R2_* not set in .env: the backup stays on this server"
fi

if [ "$UPLOAD" = true ]; then
  RCLONE=$(find_rclone)
  if [ -z "$RCLONE" ]; then
    error_exit "rclone is needed to upload the backup. Install it without root:
    curl -fsSLO https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip -j rclone-current-linux-amd64.zip '*/rclone' -d ~/bin && rm rclone-current-linux-amd64.zip"
  fi
  success_msg "rclone found: $RCLONE"

  # rclone remotes from environment variables, no rclone.conf needed. Set but
  # not exported here: rclone_cmd exports them for rclone only, so the Strapi
  # export never gets the backup credentials in its environment.
  RCLONE_CONFIG_BACKUP_TYPE=s3
  RCLONE_CONFIG_BACKUP_PROVIDER=Cloudflare
  RCLONE_CONFIG_BACKUP_ENDPOINT="$BACKUP_R2_ENDPOINT"
  RCLONE_CONFIG_BACKUP_ACCESS_KEY_ID="$BACKUP_R2_ACCESS_KEY_ID"
  RCLONE_CONFIG_BACKUP_SECRET_ACCESS_KEY="$BACKUP_R2_SECRET_ACCESS_KEY"
  # A token scoped to one bucket can't list or create buckets
  RCLONE_CONFIG_BACKUP_NO_CHECK_BUCKET=true
  BACKUP_REMOTE="backup:${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}"

  # Fail now on wrong credentials, not after the export
  rclone_cmd lsf "backup:${BACKUP_R2_BUCKET}" --max-depth 1 > /dev/null \
    || error_exit "Cannot access the backup bucket ${BACKUP_R2_BUCKET} (check BACKUP_R2_* in .env)"
  success_msg "Backup bucket reachable: ${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}/"

  if [ "$REMOTE_MEDIA" = true ]; then
    MEDIA_ENDPOINT=$(env_value AWS_ENDPOINT)
    RCLONE_CONFIG_MEDIA_TYPE=s3
    RCLONE_CONFIG_MEDIA_ACCESS_KEY_ID="$(env_value AWS_ACCESS_KEY_ID)"
    RCLONE_CONFIG_MEDIA_SECRET_ACCESS_KEY="$(env_value AWS_SECRET_ACCESS_KEY)"
    RCLONE_CONFIG_MEDIA_NO_CHECK_BUCKET=true
    if [ -z "$MEDIA_ENDPOINT" ]; then
      RCLONE_CONFIG_MEDIA_PROVIDER=AWS
      RCLONE_CONFIG_MEDIA_REGION="$(env_value AWS_REGION)"
    elif [[ "$MEDIA_ENDPOINT" == *r2.cloudflarestorage.com* ]]; then
      RCLONE_CONFIG_MEDIA_PROVIDER=Cloudflare
      RCLONE_CONFIG_MEDIA_ENDPOINT="$MEDIA_ENDPOINT"
    else
      RCLONE_CONFIG_MEDIA_PROVIDER=Other
      RCLONE_CONFIG_MEDIA_ENDPOINT="$MEDIA_ENDPOINT"
    fi
    rclone_cmd lsf "media:${MEDIA_BUCKET}" --max-depth 1 > /dev/null \
      || error_exit "Cannot access the media bucket ${MEDIA_BUCKET} (check AWS_* in .env)"
    success_msg "Media bucket reachable: ${MEDIA_BUCKET}"
  fi
fi

# Handle output directory
if [ "$OUTPUT_DIR" != "." ]; then
  info_msg "Output directory: $OUTPUT_DIR"

  # Create output directory if it doesn't exist
  if [ ! -d "$OUTPUT_DIR" ]; then
    info_msg "Creating output directory..."
    mkdir -p "$OUTPUT_DIR" || error_exit "Failed to create output directory: $OUTPUT_DIR"
    success_msg "Output directory created"
  fi

  # Verify directory is writable
  if [ ! -w "$OUTPUT_DIR" ]; then
    error_exit "Output directory is not writable: $OUTPUT_DIR"
  fi
  success_msg "Output directory is writable"
else
  info_msg "Using current directory for output"
fi

# Convert to absolute path
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

echo ""
info_msg "Starting backup export..."
echo ""

EXPORT_ARGS=(-f "$BACKUP_FILENAME" --no-encrypt)
if [ "$EXCLUDE_MEDIA" = true ]; then
  # Media library records still go into the archive (entities stage), only the files are left out
  EXPORT_ARGS+=(--exclude files)
  if [ "$NO_MEDIA" = true ]; then
    warn_msg "--no-media: media files are not in this backup, back them up separately"
  else
    info_msg "Exporting the database only, the media bucket is copied after the export"
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

REMOTE_DB_PATH=""
if [ "$UPLOAD" = true ]; then
  REMOTE_DB_PATH="${BACKUP_REMOTE}/db/${BACKUP_FILE}"
  echo ""
  info_msg "Uploading to ${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}/db/${BACKUP_FILE}..."
  rclone_cmd copyto "$BACKUP_PATH" "$REMOTE_DB_PATH" \
    || error_exit "Upload failed, the backup is still at: $BACKUP_PATH"

  # Compare checksums before removing the only local copy
  LOCAL_MD5=$(rclone_cmd md5sum "$BACKUP_PATH" | cut -d ' ' -f 1)
  REMOTE_MD5=$(rclone_cmd md5sum "$REMOTE_DB_PATH" | cut -d ' ' -f 1)
  if [ -z "$LOCAL_MD5" ] || [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
    error_exit "Uploaded backup does not match the local file (md5 ${LOCAL_MD5:-?} vs ${REMOTE_MD5:-?}), keeping: $BACKUP_PATH"
  fi
  success_msg "Upload verified (md5 $LOCAL_MD5)"

  if [ "$KEEP_LOCAL" = false ]; then
    rm -f "$BACKUP_PATH"
    info_msg "Local archive removed (use --keep-local to keep it)"
  fi

  DOWNLOAD_URL=""
  if [ -n "$LINK_EXPIRE" ]; then
    # Presigned URL: works without credentials until it expires (S3 allows at most 7 days)
    DOWNLOAD_URL=$(rclone_cmd link "$REMOTE_DB_PATH" --expire "$LINK_EXPIRE") \
      || warn_msg "Could not create the download link, the backup itself is uploaded"
  fi

  if [ "$REMOTE_MEDIA" = true ]; then
    # After the database export, so every file the backup refers to is copied.
    # copy never deletes in the backup; unchanged files are skipped (md5 from the listing)
    echo ""
    info_msg "Copying media ${MEDIA_BUCKET} -> ${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}/media/..."
    rclone_cmd copy "media:${MEDIA_BUCKET}" "${BACKUP_REMOTE}/media" \
      --checksum --fast-list --transfers 8 \
      --stats 30s --stats-one-line --stats-log-level NOTICE \
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
  echo "Remote: ${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}/db/${BACKUP_FILE}"
  [ "$KEEP_LOCAL" = true ] && echo "Local: $BACKUP_PATH"
else
  echo "Location: $BACKUP_PATH"
fi
echo "Size: $BACKUP_SIZE_FORMATTED"
echo "Duration: $DURATION_FORMATTED"
if [ "$NO_MEDIA" = true ]; then
  echo "Media: not included (--no-media)"
elif [ "$UPLOAD" = true ] && [ "$REMOTE_MEDIA" = true ]; then
  echo "Media: ${BACKUP_R2_BUCKET}/${BACKUP_APP_NAME}/media/"
fi
if [ -n "${DOWNLOAD_URL:-}" ]; then
  echo ""
  echo "Download (valid ${LINK_EXPIRE}, anyone with this URL can download the backup):"
  echo "$DOWNLOAD_URL"
  echo ""
  echo "Restore on another server: bash strapi-toolkit/backup/import.sh, then paste the URL"
fi
echo "========================================"
echo ""
