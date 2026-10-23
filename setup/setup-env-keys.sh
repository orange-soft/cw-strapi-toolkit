#!/bin/bash
set -e

usage() {
    echo "Usage: bash strapi-toolkit/setup/setup-env-keys.sh [--missing-only] [--yes]"
    echo ""
    echo "  (default)       Generate ALL secrets and replace them in .env. Only for a new"
    echo "                  .env or a planned rotation: replacing them logs out every user,"
    echo "                  invalidates API tokens and makes encrypted values unreadable"
    echo "  --missing-only  Only fill in secrets that are missing, empty or still a"
    echo "                  placeholder (tobemodified). Existing secrets are never replaced,"
    echo "                  so it is safe on a running site"
    echo "  --yes, -y       Don't ask before updating .env"
}

MISSING_ONLY=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
        --missing-only) MISSING_ONLY=true ;;
        --yes|-y) ASSUME_YES=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "❌ Unknown option: $arg"; echo ""; usage; exit 1 ;;
    esac
done

echo "========================================"
echo "🔑 Strapi Environment Keys Setup"
echo "========================================"
echo ""

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed or not in PATH"
    exit 1
fi

# Get the script directory and app root
# Script is at: app/strapi-toolkit/setup/setup-env-keys.sh
# App root is at: app/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${APP_ROOT}/.env"

# Function to generate a random 32-byte base64 key
generate_key() {
    node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
}

# --missing-only: fill in only absent / empty / placeholder secrets, keep the rest
if [ "$MISSING_ONLY" = true ]; then
    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ Error: .env not found at ${ENV_FILE}"
        echo "   Create it first: cp .env.example .env"
        exit 1
    fi

    SECRET_KEYS=(APP_KEYS API_TOKEN_SALT ADMIN_JWT_SECRET TRANSFER_TOKEN_SALT JWT_SECRET ENCRYPTION_KEY ADMIN_ENCRYPTION_KEY)

    # Missing = no line, an empty value, or a placeholder from .env.example
    is_missing() {
        local value
        value=$(grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d "\"' \r" || true)
        [ -z "$value" ] || echo "$value" | grep -qi "tobemodified"
    }

    TO_FILL=()
    KEPT=()
    for key in "${SECRET_KEYS[@]}"; do
        if is_missing "$key"; then TO_FILL+=("$key"); else KEPT+=("$key"); fi
    done

    if [ ${#TO_FILL[@]} -eq 0 ]; then
        echo "✅ All ${#SECRET_KEYS[@]} secrets are already set in ${ENV_FILE} - nothing changed"
        exit 0
    fi

    echo "📁 ${ENV_FILE}"
    echo "   Will add:     ${TO_FILL[*]}"
    echo "   Keeping as is: ${KEPT[*]:-none}"
    echo ""
    if [ "$ASSUME_YES" != true ]; then
        read -p "Add the missing secrets to .env? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Nothing changed."
            exit 0
        fi
    fi

    BACKUP_FILE="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$ENV_FILE" "$BACKUP_FILE"

    for key in "${TO_FILL[@]}"; do
        if [ "$key" = "APP_KEYS" ]; then
            value="\"$(generate_key),$(generate_key)\""
        else
            value="$(generate_key)"
        fi
        if grep -qE "^${key}=" "$ENV_FILE"; then
            # Replace the empty/placeholder line in place
            TMP_FILE=$(mktemp)
            KEY="$key" VALUE="$value" awk '
                index($0, ENVIRON["KEY"] "=") == 1 { print ENVIRON["KEY"] "=" ENVIRON["VALUE"]; next }
                { print }
            ' "$ENV_FILE" > "$TMP_FILE"
            cat "$TMP_FILE" > "$ENV_FILE"
            rm -f "$TMP_FILE"
        else
            # Keep the last line terminated before appending
            [ -z "$(tail -c 1 "$ENV_FILE")" ] || echo "" >> "$ENV_FILE"
            echo "${key}=${value}" >> "$ENV_FILE"
        fi
        echo "   ➕ ${key}"
    done

    echo ""
    echo "✅ Added ${#TO_FILL[@]} secret(s); existing ones untouched"
    echo "   Backup: ${BACKUP_FILE}"
    echo "   Strapi reads .env at startup: bash strapi-toolkit/pm2/pm2-manager.sh restart (or the next deploy)"
    exit 0
fi

echo "Generating cryptographically secure random keys..."
echo ""

# Generate APP_KEYS (2 keys for key rotation)
APP_KEY_1=$(generate_key)
APP_KEY_2=$(generate_key)
API_TOKEN_SALT=$(generate_key)
ADMIN_JWT_SECRET=$(generate_key)
TRANSFER_TOKEN_SALT=$(generate_key)
JWT_SECRET=$(generate_key)
ENCRYPTION_KEY=$(generate_key)
ADMIN_ENCRYPTION_KEY=$(generate_key)

echo "✅ Keys generated successfully!"
echo ""
echo "========================================"
echo "📋 Generated Keys:"
echo "========================================"
echo ""
echo "APP_KEYS=\"${APP_KEY_1},${APP_KEY_2}\""
echo "API_TOKEN_SALT=${API_TOKEN_SALT}"
echo "ADMIN_JWT_SECRET=${ADMIN_JWT_SECRET}"
echo "TRANSFER_TOKEN_SALT=${TRANSFER_TOKEN_SALT}"
echo "JWT_SECRET=${JWT_SECRET}"
echo "ENCRYPTION_KEY=${ENCRYPTION_KEY}"
echo "ADMIN_ENCRYPTION_KEY=${ADMIN_ENCRYPTION_KEY}"
echo ""
echo "========================================"
echo ""

# Check if .env file exists
if [ -f "$ENV_FILE" ]; then
    echo "📁 Found .env file at: ${ENV_FILE}"
    echo ""
    echo "⚠️  WARNING: This will update your .env file!"
    echo "   A backup will be created at: ${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo ""
    echo "   (to only fill in missing secrets on a running site, use --missing-only)"
    echo ""
    if [ "$ASSUME_YES" = true ]; then
        REPLY=y
    else
        read -p "Do you want to automatically update the .env file? (y/n) " -n 1 -r
        echo
    fi

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create backup
        BACKUP_FILE="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$BACKUP_FILE"
        echo "✅ Backup created: ${BACKUP_FILE}"

        # Create temporary file
        TMP_FILE=$(mktemp)

        # Track which keys were found in the file
        FOUND_ENCRYPTION_KEY=false
        FOUND_ADMIN_ENCRYPTION_KEY=false

        # Update the keys in the .env file
        while IFS= read -r line; do
            if [[ $line =~ ^APP_KEYS= ]]; then
                echo "APP_KEYS=\"${APP_KEY_1},${APP_KEY_2}\""
            elif [[ $line =~ ^API_TOKEN_SALT= ]]; then
                echo "API_TOKEN_SALT=${API_TOKEN_SALT}"
            elif [[ $line =~ ^ADMIN_JWT_SECRET= ]]; then
                echo "ADMIN_JWT_SECRET=${ADMIN_JWT_SECRET}"
            elif [[ $line =~ ^TRANSFER_TOKEN_SALT= ]]; then
                echo "TRANSFER_TOKEN_SALT=${TRANSFER_TOKEN_SALT}"
            elif [[ $line =~ ^JWT_SECRET= ]]; then
                echo "JWT_SECRET=${JWT_SECRET}"
            elif [[ $line =~ ^ENCRYPTION_KEY= ]]; then
                echo "ENCRYPTION_KEY=${ENCRYPTION_KEY}"
                FOUND_ENCRYPTION_KEY=true
            elif [[ $line =~ ^ADMIN_ENCRYPTION_KEY= ]]; then
                echo "ADMIN_ENCRYPTION_KEY=${ADMIN_ENCRYPTION_KEY}"
                FOUND_ADMIN_ENCRYPTION_KEY=true
            else
                echo "$line"
            fi
        done < "$ENV_FILE" > "$TMP_FILE"

        # Append missing keys at the end if they weren't found
        if [ "$FOUND_ENCRYPTION_KEY" = false ]; then
            echo "ENCRYPTION_KEY=${ENCRYPTION_KEY}" >> "$TMP_FILE"
            echo "   ➕ Added ENCRYPTION_KEY (was missing)"
        fi

        if [ "$FOUND_ADMIN_ENCRYPTION_KEY" = false ]; then
            echo "ADMIN_ENCRYPTION_KEY=${ADMIN_ENCRYPTION_KEY}" >> "$TMP_FILE"
            echo "   ➕ Added ADMIN_ENCRYPTION_KEY (was missing)"
        fi

        # Replace original file
        mv "$TMP_FILE" "$ENV_FILE"

        echo "✅ .env file updated successfully!"
        echo ""
        echo "🔄 Next steps:"
        echo "   1. Review the updated .env file: cat .env"
        echo "   2. Restart Strapi: bash strapi-toolkit/pm2/pm2-manager.sh restart"
        echo "   3. Test admin login"
        echo ""
        echo "📌 If something goes wrong, restore from backup:"
        echo "   cp ${BACKUP_FILE} ${ENV_FILE}"
        echo ""
    else
        echo ""
        echo "📝 Manual update instructions:"
        echo "   1. Edit your .env file: nano ${ENV_FILE}"
        echo "   2. Replace the values above"
        echo "   3. Save and exit (Ctrl+X, then Y, then Enter)"
        echo "   4. Restart Strapi: bash strapi-toolkit/pm2/pm2-manager.sh restart"
        echo ""
    fi
else
    echo "📝 .env file not found at: ${ENV_FILE}"
    echo ""
    echo "To create a new .env file:"
    echo "   1. Copy from example: cp .env.example .env"
    echo "   2. Edit: nano .env"
    echo "   3. Paste the keys above"
    echo "   4. Update database settings"
    echo "   5. Save and restart Strapi"
    echo ""
fi

echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   - Keep these keys secret and secure"
echo "   - Never commit them to git"
echo "   - Use different keys for each environment"
echo "   - Changing keys will log out all users and invalidate API tokens"
echo ""
