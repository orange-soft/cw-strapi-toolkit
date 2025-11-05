#!/bin/bash
set -e

# Script: Check and Fix MySQL Database Encoding
# Description: Verifies database and table encoding/collation, offers conversion to utf8mb4

# Color codes for output
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color
else
  GREEN=''
  YELLOW=''
  RED=''
  BLUE=''
  CYAN=''
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

# Header message
header_msg() {
  echo -e "${CYAN}$1${NC}"
}

echo "========================================"
echo "    MySQL Encoding & Collation Checker"
echo "    Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

# Pre-flight checks
info_msg "Running pre-flight checks..."

# Check if .env file exists
if [ ! -f ".env" ]; then
  error_exit ".env file not found. Are you in a Strapi project directory?"
fi
success_msg ".env file found"

# Check if mysql client is available
if ! command -v mysql &> /dev/null; then
  error_exit "mysql client is not installed or not in PATH"
fi
success_msg "mysql client is available"

echo ""

# Extract database credentials from .env
info_msg "Reading database credentials from .env..."

DB_HOST=$(grep "^DATABASE_HOST=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
DB_PORT=$(grep "^DATABASE_PORT=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
DB_NAME=$(grep "^DATABASE_NAME=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
DB_USER=$(grep "^DATABASE_USERNAME=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
DB_PASS=$(grep "^DATABASE_PASSWORD=" .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")

# Set defaults
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-3306}

# Validate required fields
if [ -z "$DB_NAME" ]; then
  error_exit "DATABASE_NAME not found in .env"
fi

if [ -z "$DB_USER" ]; then
  error_exit "DATABASE_USERNAME not found in .env"
fi

success_msg "Database credentials loaded"
info_msg "Host: $DB_HOST:$DB_PORT"
info_msg "Database: $DB_NAME"
info_msg "User: $DB_USER"

echo ""

# Test database connection
info_msg "Testing database connection..."

# Build mysql command
MYSQL_CMD="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER"
if [ -n "$DB_PASS" ]; then
  MYSQL_CMD="$MYSQL_CMD -p$DB_PASS"
fi

# Test connection
if ! $MYSQL_CMD -e "SELECT 1" $DB_NAME &> /dev/null; then
  error_exit "Cannot connect to database. Please check your credentials."
fi

success_msg "Database connection successful"

echo ""
echo "========================================"
echo "    Database Encoding Check"
echo "========================================"
echo ""

# Get database-level encoding and collation
info_msg "Checking database-level settings..."

DB_CHARSET=$($MYSQL_CMD -N -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)
DB_COLLATION=$($MYSQL_CMD -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)

if [ -z "$DB_CHARSET" ]; then
  error_exit "Failed to retrieve database encoding"
fi

header_msg "Database: $DB_NAME"
echo "  Character Set: $DB_CHARSET"
echo "  Collation:     $DB_COLLATION"
echo ""

# Check if database needs conversion
DB_NEEDS_CONVERSION=false
if [ "$DB_CHARSET" != "utf8mb4" ] || [ "$DB_COLLATION" != "utf8mb4_unicode_ci" ]; then
  DB_NEEDS_CONVERSION=true
  warn_msg "Database encoding is not utf8mb4/utf8mb4_unicode_ci"
else
  success_msg "Database encoding is correct (utf8mb4/utf8mb4_unicode_ci)"
fi

echo ""
echo "========================================"
echo "    Table Encoding Check"
echo "========================================"
echo ""

info_msg "Checking all tables..."

# Get all tables with their encoding
TABLE_INFO=$($MYSQL_CMD -N -e "
  SELECT
    TABLE_NAME,
    CCSA.CHARACTER_SET_NAME,
    TABLE_COLLATION
  FROM information_schema.TABLES T
  LEFT JOIN information_schema.COLLATION_CHARACTER_SET_APPLICABILITY CCSA
    ON T.TABLE_COLLATION = CCSA.COLLATION_NAME
  WHERE TABLE_SCHEMA='$DB_NAME'
  ORDER BY TABLE_NAME
" 2>/dev/null)

if [ -z "$TABLE_INFO" ]; then
  warn_msg "No tables found in database"
  TABLES_NEED_CONVERSION=false
else
  # Count tables
  TABLE_COUNT=$(echo "$TABLE_INFO" | wc -l | tr -d ' ')
  info_msg "Found $TABLE_COUNT tables"
  echo ""

  # Track tables that need conversion
  TABLES_TO_CONVERT=()
  TABLES_NEED_CONVERSION=false

  # Display table info
  printf "%-40s %-20s %-30s\n" "Table Name" "Character Set" "Collation"
  echo "--------------------------------------------------------------------------------"

  while IFS=$'\t' read -r table charset collation; do
    # Check if table needs conversion
    if [ "$charset" != "utf8mb4" ] || [ "$collation" != "utf8mb4_unicode_ci" ]; then
      printf "${YELLOW}%-40s %-20s %-30s${NC}\n" "$table" "$charset" "$collation"
      TABLES_TO_CONVERT+=("$table")
      TABLES_NEED_CONVERSION=true
    else
      printf "${GREEN}%-40s %-20s %-30s${NC}\n" "$table" "$charset" "$collation"
    fi
  done <<< "$TABLE_INFO"

  echo ""

  if [ "$TABLES_NEED_CONVERSION" = true ]; then
    warn_msg "${#TABLES_TO_CONVERT[@]} tables need conversion (shown in yellow)"
  else
    success_msg "All tables are using utf8mb4/utf8mb4_unicode_ci"
  fi
fi

echo ""

# If nothing needs conversion, exit
if [ "$DB_NEEDS_CONVERSION" = false ] && [ "$TABLES_NEED_CONVERSION" = false ]; then
  success_msg "All database and table encodings are correct!"
  echo ""
  exit 0
fi

# Ask user what to do
echo "========================================"
echo "    Conversion Options"
echo "========================================"
echo ""

if [ "$DB_NEEDS_CONVERSION" = true ]; then
  warn_msg "Database needs conversion to utf8mb4/utf8mb4_unicode_ci"
fi

if [ "$TABLES_NEED_CONVERSION" = true ]; then
  warn_msg "${#TABLES_TO_CONVERT[@]} tables need conversion"
fi

echo ""
echo "Options:"
echo "  [1] Convert database and all tables to utf8mb4/utf8mb4_unicode_ci"
echo "  [2] Convert database only (new tables will inherit utf8mb4)"
echo "  [3] Convert specific tables only"
echo "  [4] Exit without changes"
echo ""

read -p "Enter your choice (1-4): " CHOICE

case $CHOICE in
  1)
    # Convert everything
    echo ""
    warn_msg "⚠️  IMPORTANT: This will convert the database AND all tables"
    warn_msg "⚠️  This operation modifies data and cannot be easily reversed"
    warn_msg "⚠️  Large tables may take several minutes to convert"
    echo ""
    warn_msg "🛡️  STRONGLY RECOMMENDED: Create a database backup first!"
    echo ""
    echo "To create a backup, run:"
    echo "  bash strapi-toolkit/backup/export.sh --output ./backups"
    echo ""
    echo "Or manually:"
    BACKUP_TIMESTAMP=$(date +%s)
    echo "  mysqldump -h $DB_HOST -P $DB_PORT -u $DB_USER -p $DB_NAME | gzip > db-backup-${BACKUP_TIMESTAMP}.sql.gz"
    echo ""

    read -p "Have you created a backup? (yes/NO): " BACKUP_CONFIRM

    if [[ ! "$BACKUP_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
      echo ""
      warn_msg "⚠️  WARNING: Proceeding without a backup is RISKY!"
      warn_msg "⚠️  If conversion fails, you may lose data permanently"
      echo ""
      read -p "Proceed WITHOUT backup at your own risk? (yes/NO): " RISK_CONFIRM

      if [[ ! "$RISK_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        info_msg "Conversion cancelled - please create a backup first"
        exit 0
      fi
    fi

    echo ""
    read -p "Final confirmation - proceed with conversion? (yes/NO): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
      info_msg "Conversion cancelled"
      exit 0
    fi

    echo ""
    info_msg "Starting conversion..."

    # Convert database
    if [ "$DB_NEEDS_CONVERSION" = true ]; then
      info_msg "Converting database: $DB_NAME"
      $MYSQL_CMD -e "ALTER DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" 2>/dev/null || error_exit "Failed to convert database"
      success_msg "Database converted"
    fi

    # Convert all tables that need it
    if [ "$TABLES_NEED_CONVERSION" = true ]; then
      for table in "${TABLES_TO_CONVERT[@]}"; do
        info_msg "Converting table: $table"
        $MYSQL_CMD $DB_NAME -e "ALTER TABLE \`$table\` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" 2>/dev/null || {
          warn_msg "Failed to convert table: $table (continuing...)"
        }
      done
      success_msg "All tables converted"
    fi

    echo ""
    success_msg "Conversion completed!"
    ;;

  2)
    # Convert database only
    if [ "$DB_NEEDS_CONVERSION" = false ]; then
      info_msg "Database is already utf8mb4/utf8mb4_unicode_ci"
      exit 0
    fi

    echo ""
    warn_msg "This will convert ONLY the database (not existing tables)"
    info_msg "New tables created after this will inherit utf8mb4/utf8mb4_unicode_ci"
    echo ""
    read -p "Continue? (yes/NO): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
      info_msg "Conversion cancelled"
      exit 0
    fi

    echo ""
    info_msg "Converting database: $DB_NAME"
    $MYSQL_CMD -e "ALTER DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" 2>/dev/null || error_exit "Failed to convert database"
    success_msg "Database converted!"
    ;;

  3)
    # Convert specific tables
    if [ "$TABLES_NEED_CONVERSION" = false ]; then
      info_msg "No tables need conversion"
      exit 0
    fi

    echo ""
    info_msg "Tables that need conversion:"
    for i in "${!TABLES_TO_CONVERT[@]}"; do
      echo "  $((i+1)). ${TABLES_TO_CONVERT[$i]}"
    done
    echo ""

    read -p "Enter table numbers to convert (e.g., 1,3,5 or 'all'): " TABLE_SELECTION

    if [ "$TABLE_SELECTION" = "all" ]; then
      SELECTED_TABLES=("${TABLES_TO_CONVERT[@]}")
    else
      # Parse comma-separated list
      IFS=',' read -ra INDICES <<< "$TABLE_SELECTION"
      SELECTED_TABLES=()
      for idx in "${INDICES[@]}"; do
        idx=$(echo "$idx" | tr -d ' ')
        if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#TABLES_TO_CONVERT[@]}" ]; then
          SELECTED_TABLES+=("${TABLES_TO_CONVERT[$((idx-1))]}")
        else
          warn_msg "Skipping invalid index: $idx"
        fi
      done
    fi

    if [ ${#SELECTED_TABLES[@]} -eq 0 ]; then
      info_msg "No tables selected"
      exit 0
    fi

    echo ""
    warn_msg "⚠️  IMPORTANT: This will convert ${#SELECTED_TABLES[@]} tables"
    warn_msg "⚠️  This operation modifies data and cannot be easily reversed"
    echo ""
    warn_msg "🛡️  RECOMMENDED: Create a database backup first!"
    echo ""
    echo "To create a backup, run:"
    echo "  bash strapi-toolkit/backup/export.sh --output ./backups"
    echo ""

    read -p "Have you created a backup? (yes/NO): " BACKUP_CONFIRM

    if [[ ! "$BACKUP_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
      echo ""
      warn_msg "⚠️  WARNING: Proceeding without a backup is RISKY!"
      warn_msg "⚠️  If conversion fails, you may lose data permanently"
      echo ""
      read -p "Proceed WITHOUT backup at your own risk? (yes/NO): " RISK_CONFIRM

      if [[ ! "$RISK_CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
        info_msg "Conversion cancelled - please create a backup first"
        exit 0
      fi
    fi

    echo ""
    info_msg "Converting ${#SELECTED_TABLES[@]} tables..."
    for table in "${SELECTED_TABLES[@]}"; do
      info_msg "Converting table: $table"
      $MYSQL_CMD $DB_NAME -e "ALTER TABLE \`$table\` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci" 2>/dev/null || {
        warn_msg "Failed to convert table: $table (continuing...)"
      }
    done
    success_msg "Selected tables converted!"
    ;;

  4)
    info_msg "Exiting without changes"
    exit 0
    ;;

  *)
    error_exit "Invalid choice: $CHOICE"
    ;;
esac

echo ""
echo "========================================"
echo "    Verification"
echo "========================================"
echo ""

# Verify database encoding
info_msg "Verifying database encoding..."
NEW_DB_CHARSET=$($MYSQL_CMD -N -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)
NEW_DB_COLLATION=$($MYSQL_CMD -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME'" 2>/dev/null)

if [ "$NEW_DB_CHARSET" = "utf8mb4" ] && [ "$NEW_DB_COLLATION" = "utf8mb4_unicode_ci" ]; then
  success_msg "Database: $NEW_DB_CHARSET / $NEW_DB_COLLATION"
else
  warn_msg "Database: $NEW_DB_CHARSET / $NEW_DB_COLLATION (not fully converted)"
fi

# Count remaining tables that need conversion
info_msg "Checking remaining tables..."
REMAINING_TABLES=$($MYSQL_CMD -N -e "
  SELECT COUNT(*)
  FROM information_schema.TABLES T
  LEFT JOIN information_schema.COLLATION_CHARACTER_SET_APPLICABILITY CCSA
    ON T.TABLE_COLLATION = CCSA.COLLATION_NAME
  WHERE TABLE_SCHEMA='$DB_NAME'
    AND (CCSA.CHARACTER_SET_NAME != 'utf8mb4' OR TABLE_COLLATION != 'utf8mb4_unicode_ci')
" 2>/dev/null)

if [ "$REMAINING_TABLES" -eq 0 ]; then
  success_msg "All tables are now utf8mb4/utf8mb4_unicode_ci"
else
  warn_msg "$REMAINING_TABLES tables still need conversion"
  info_msg "Run this script again to convert remaining tables"
fi

echo ""
success_msg "Operation completed!"
echo ""
