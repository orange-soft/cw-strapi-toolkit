#!/bin/bash
set -e

echo "========================================"
echo "🔑 Strapi Environment Keys Setup"
echo "========================================"
echo ""

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed or not in PATH"
    exit 1
fi

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${APP_ROOT}/.env"

# Function to generate a random 32-byte base64 key
generate_key() {
    node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
}

echo "Generating cryptographically secure random keys..."
echo ""

# Generate APP_KEYS (2 keys for key rotation)
APP_KEY_1=$(generate_key)
APP_KEY_2=$(generate_key)
API_TOKEN_SALT=$(generate_key)
ADMIN_JWT_SECRET=$(generate_key)
TRANSFER_TOKEN_SALT=$(generate_key)
JWT_SECRET=$(generate_key)

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
    read -p "Do you want to automatically update the .env file? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create backup
        BACKUP_FILE="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ENV_FILE" "$BACKUP_FILE"
        echo "✅ Backup created: ${BACKUP_FILE}"

        # Create temporary file
        TMP_FILE=$(mktemp)

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
            else
                echo "$line"
            fi
        done < "$ENV_FILE" > "$TMP_FILE"

        # Replace original file
        mv "$TMP_FILE" "$ENV_FILE"

        echo "✅ .env file updated successfully!"
        echo ""
        echo "🔄 Next steps:"
        echo "   1. Review the updated .env file: cat .env"
        echo "   2. Restart Strapi: pm2 restart ecosystem.config.cjs"
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
        echo "   4. Restart Strapi: pm2 restart ecosystem.config.cjs"
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
