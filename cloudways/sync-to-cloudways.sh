#!/bin/bash
set -e

# Script: Sync File to Cloudways
# Description: Upload files to Cloudways server using rsync (since SCP is blocked)
# Usage: ./sync-to-cloudways.sh --file=backup.tar.gz [--dest=path] [--profile=prod]

# Color codes for output
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

# Default values
FILE=""
DEST=""
SSH_HOST=""
SSH_PORT="${CLOUDWAYS_PORT:-22}"  # Use CLOUDWAYS_PORT env var if set, otherwise default to 22
SSH_USER=""
VERBOSE=false

# Show usage
show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Upload files to Cloudways server using rsync (SCP alternative)

Interactive Mode:
  Run without arguments to enter interactive mode with prompts

Options:
  --file=FILE          File or directory to upload
  --target=USER@HOST   SSH target in user@host format (like SSH)
  --host=HOST          SSH host
  --user=USER          SSH username
  --port=PORT          SSH port (default: 22, or CLOUDWAYS_PORT env var)
  --dest=PATH          Destination path (default: home directory)
  --verbose            Show detailed rsync output
  -h, --help           Show this help

Environment Variables:
  CLOUDWAYS_PORT       Default SSH port (overridden by --port option)

Examples:
  # Interactive mode (prompts for inputs)
  $0

  # Positional file argument (enables tab completion!)
  $0 ./README.md --target=user@host

  # Using --file with space (also enables tab completion)
  $0 --file ./backup.tar.gz --target=user@host

  # Using --file= format
  $0 --file=backup.tar.gz --target=user@host

  # Full example with port
  $0 ./backup.tar.gz --target=gocomm-strapi@143.198.84.148 --port=22000

  # Upload to specific subdirectory (automatically prefixed with public_html/)
  $0 backup.tar.gz --target=user@host --dest=backups/

  # Upload directory with verbose output
  $0 ./my-folder/ --target=user@host --verbose

EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --file=*)
      FILE="${1#*=}"
      shift
      ;;
    --file)
      FILE="$2"
      shift 2
      ;;
    --dest=*)
      DEST="${1#*=}"
      shift
      ;;
    --dest)
      DEST="$2"
      shift 2
      ;;
    --host=*)
      SSH_HOST="${1#*=}"
      shift
      ;;
    --host)
      SSH_HOST="$2"
      shift 2
      ;;
    --port=*)
      SSH_PORT="${1#*=}"
      shift
      ;;
    --port)
      SSH_PORT="$2"
      shift 2
      ;;
    --user=*)
      SSH_USER="${1#*=}"
      shift
      ;;
    --user)
      SSH_USER="$2"
      shift 2
      ;;
    --target=*)
      # Support --target=user@host format
      SSH_TARGET="${1#*=}"
      if [[ "$SSH_TARGET" =~ ^([^@]+)@(.+)$ ]]; then
        SSH_USER="${BASH_REMATCH[1]}"
        SSH_HOST="${BASH_REMATCH[2]}"
      else
        SSH_HOST="$SSH_TARGET"
      fi
      shift
      ;;
    --target)
      # Support --target user@host format (with space)
      SSH_TARGET="$2"
      if [[ "$SSH_TARGET" =~ ^([^@]+)@(.+)$ ]]; then
        SSH_USER="${BASH_REMATCH[1]}"
        SSH_HOST="${BASH_REMATCH[2]}"
      else
        SSH_HOST="$SSH_TARGET"
      fi
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      show_usage
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
    *)
      # Positional argument - assume it's the file if FILE is not set
      if [ -z "$FILE" ]; then
        FILE="$1"
      else
        echo -e "${RED}Unknown argument: $1${NC}"
        echo "Use --help for usage information"
        exit 1
      fi
      shift
      ;;
  esac
done

# Interactive mode if missing required parameters
if [ -z "$FILE" ] || [ -z "$SSH_HOST" ] || [ -z "$SSH_PORT" ] || [ -z "$SSH_USER" ]; then
  echo "========================================"
  echo "📤 Sync to Cloudways - Interactive Mode"
  echo "========================================"
  echo ""

  # Prompt for file if missing
  if [ -z "$FILE" ]; then
    read -p "File or directory to upload: " FILE
    if [ -z "$FILE" ]; then
      error_exit "File path is required"
    fi
  fi

  # Validate file exists
  if [ ! -e "$FILE" ]; then
    error_exit "File not found: $FILE"
  fi

  # Prompt for SSH target if missing (support user@host format)
  if [ -z "$SSH_HOST" ] || [ -z "$SSH_USER" ]; then
    read -p "SSH target (user@host or just host): " SSH_TARGET

    if [ -z "$SSH_TARGET" ]; then
      error_exit "SSH target is required"
    fi

    # Parse user@host format
    if [[ "$SSH_TARGET" =~ ^([^@]+)@(.+)$ ]]; then
      SSH_USER="${BASH_REMATCH[1]}"
      SSH_HOST="${BASH_REMATCH[2]}"
      info_msg "Parsed: user=${SSH_USER}, host=${SSH_HOST}"
    else
      # Just host provided
      SSH_HOST="$SSH_TARGET"
      if [ -z "$SSH_USER" ]; then
        read -p "SSH username: " SSH_USER
        if [ -z "$SSH_USER" ]; then
          error_exit "SSH username is required"
        fi
      fi
    fi
  fi

  # Prompt for port if missing
  if [ -z "$SSH_PORT" ]; then
    read -p "SSH port [22]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
  fi

  # Prompt for destination (optional)
  if [ -z "$DEST" ]; then
    echo ""
    echo "Destination path (will be prefixed with public_html/):"
    echo "  - Press Enter for public_html/"
    echo "  - Or enter a subdirectory like: backups/ → public_html/backups/"
    read -p "Destination [public_html/]: " DEST
    # Don't set default here, let the main logic handle it
  fi

  echo ""
fi

# Final validation
if [ -z "$FILE" ]; then
  error_exit "Missing required parameter: --file"
fi

if [ ! -e "$FILE" ]; then
  error_exit "File not found: $FILE"
fi

if [ -z "$SSH_HOST" ]; then
  error_exit "Missing required parameter: --host"
fi

# Port has default value of 22, so no validation needed

if [ -z "$SSH_USER" ]; then
  error_exit "Missing required parameter: --user"
fi

echo "========================================"
echo "📤 Sync to Cloudways"
echo "⏱️  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

# Set default destination with public_html prefix (Cloudways structure)
if [ -z "$DEST" ]; then
  DEST="public_html/"
  info_msg "No destination specified, uploading to public_html/"
else
  # Prepend public_html/ to user-specified path
  DEST="public_html/${DEST}"
  info_msg "Destination: ${DEST}"
fi

echo ""
echo "🔍 Upload Details:"
echo "   Source: ${FILE}"
echo "   Destination: ${SSH_USER}@${SSH_HOST}:${DEST}"
echo "   Port: ${SSH_PORT}"
echo ""

# Check if source is directory or file
if [ -d "$FILE" ]; then
  FILE_TYPE="directory"
  # Add trailing slash for rsync to sync contents
  if [[ ! "$FILE" =~ /$ ]]; then
    FILE="${FILE}/"
  fi
else
  FILE_TYPE="file"
fi

info_msg "Type: ${FILE_TYPE}"

# Get file/directory size
if [ "$FILE_TYPE" = "directory" ]; then
  FILE_SIZE=$(du -sh "$FILE" | cut -f1)
else
  FILE_SIZE=$(du -h "$FILE" | cut -f1)
fi

echo "   Size: ${FILE_SIZE}"
echo ""

# Confirm upload
read -p "Continue with upload? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Upload cancelled."
  exit 0
fi

echo ""
info_msg "Starting rsync upload..."
echo ""

# Build rsync command
# Use options compatible with old rsync (macOS has 2.6.9 from 2006)
if [ "$VERBOSE" = true ]; then
  RSYNC_OPTS="-avz --progress"
else
  RSYNC_OPTS="-az --progress"
fi

# Rsync command
# -a: archive mode (preserves permissions, timestamps, etc.)
# -v: verbose
# -z: compress during transfer
# --progress: show progress
START_TIME=$(date +%s)

if rsync $RSYNC_OPTS \
  -e "ssh -p ${SSH_PORT}" \
  "$FILE" \
  "${SSH_USER}@${SSH_HOST}:${DEST}"; then

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  echo ""
  success_msg "Upload completed in ${DURATION}s"
  echo ""
  echo "📊 Summary:"
  echo "   Source: ${FILE}"
  echo "   Destination: ${SSH_USER}@${SSH_HOST}:${DEST}"
  echo "   Duration: ${DURATION}s"
  echo ""
  success_msg "File is now available on Cloudways server"
else
  echo ""
  error_exit "Rsync upload failed"
fi

echo ""
echo "========================================"
echo "✅ Sync Complete"
echo "🕐 Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
