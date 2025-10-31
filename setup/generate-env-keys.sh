#!/bin/bash
set -e

echo "========================================"
echo "🔑 Strapi Environment Keys Generator"
echo "========================================"
echo ""

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed or not in PATH"
    exit 1
fi

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
ENCRYPTION_KEY=$(generate_key)
ADMIN_ENCRYPTION_KEY=$(generate_key)

echo "✅ Keys generated successfully!"
echo ""
echo "========================================"
echo "📋 Copy these values to your .env file:"
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
echo "📝 Instructions:"
echo "1. Copy the values above"
echo "2. Edit your .env file: nano .env"
echo "3. Replace the 'tobemodified' values with the generated keys"
echo "4. Save the file (Ctrl+X, then Y, then Enter)"
echo "5. Restart Strapi: pm2 restart ecosystem.config.cjs"
echo ""
echo "⚠️  IMPORTANT:"
echo "   - Keep these keys secret and secure"
echo "   - Never commit them to git"
echo "   - Changing keys will log out all users"
echo ""
