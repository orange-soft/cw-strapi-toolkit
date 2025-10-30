#!/bin/bash
set -e

# Script: Strapi Backup Export
# Description: Exports Strapi data with enhanced logging, validation, and timing

# Auto-detect NVM location (Cloudways, local, or custom)
if [ -n "$NVM_DIR" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
    # NVM_DIR already set and valid
    \. "$NVM_DIR/nvm.sh"
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
    # Standard location (macOS/Linux local)
    export NVM_DIR="$HOME/.nvm"
    \. "$NVM_DIR/nvm.sh"
elif [ -s "/home/master/.nvm/nvm.sh" ]; then
    # Cloudways location
    export NVM_DIR="/home/master/.nvm"
    \. "$NVM_DIR/nvm.sh"
    # Setup Cloudways-specific paths
    export PATH="/home/master/bin:/home/master/bin/npm/lib/node_modules/bin:${PATH}"
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
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --output=DIR    Specify output directory for backup (default: current directory)"
      echo "  --output DIR    Alternative syntax for output directory"
      echo "  -h, --help      Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --output=./public"
      echo "  $0 --output ./backups"
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

# Run the export
npm run strapi export -- -f "$BACKUP_FILENAME" --no-encrypt || error_exit "Backup export failed"

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
BACKUP_SIZE=$(stat -f%z "$BACKUP_PATH" 2>/dev/null || stat -c%s "$BACKUP_PATH" 2>/dev/null)
BACKUP_SIZE_FORMATTED=$(format_bytes $BACKUP_SIZE)

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_FORMATTED=$(format_duration $DURATION)

success_msg "Backup completed successfully!"

echo ""
echo "========================================"
echo "    Backup Details"
echo "========================================"
echo "Location: $BACKUP_PATH"
echo "Size: $BACKUP_SIZE_FORMATTED"
echo "Duration: $DURATION_FORMATTED"
echo "========================================"
echo ""
