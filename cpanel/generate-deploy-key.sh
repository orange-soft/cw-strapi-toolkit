#!/bin/bash
# ============================================
# Generate Deployment SSH Key for cPanel User
# ============================================
# Usage: bash generate-deploy-key.sh <cpanel_username>
# Example: bash generate-deploy-key.sh calvarystrapi

set -e

CPANEL_USERNAME="$1"

if [ -z "$CPANEL_USERNAME" ]; then
    echo "Usage: bash $0 <cpanel_username>"
    echo "Example: bash $0 calvarystrapi"
    exit 1
fi

# Validate username (alphanumeric and underscores only)
if ! [[ "$CPANEL_USERNAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "Error: Invalid cPanel username. Use only alphanumeric characters and underscores."
    exit 1
fi

KEY_NAME="deploy_${CPANEL_USERNAME}"
KEY_PATH="$HOME/.ssh/${KEY_NAME}"
COMMENT="deploy-${CPANEL_USERNAME}"

echo "============================================"
echo "Generating Deployment Key"
echo "============================================"
echo "  cPanel User: $CPANEL_USERNAME"
echo "  Key Name:    $KEY_NAME"
echo "  Key Path:    $KEY_PATH"
echo "  Comment:     $COMMENT"
echo ""

# Check if key already exists
if [ -f "$KEY_PATH" ]; then
    echo "⚠️  Key already exists at $KEY_PATH"
    echo ""
    read -p "Do you want to overwrite it? (yes/no): " OVERWRITE
    if [ "$OVERWRITE" != "yes" ]; then
        echo "Aborted. Using existing key."
        echo ""
        echo "Public key:"
        cat "${KEY_PATH}.pub"
        exit 0
    fi
    echo ""
fi

# Ensure .ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate the key
echo "Generating ED25519 key..."
ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "$COMMENT"

echo ""
echo "============================================"
echo "✅ Key Generated Successfully"
echo "============================================"
echo ""
echo "Files created:"
echo "  Private key: $KEY_PATH"
echo "  Public key:  ${KEY_PATH}.pub"
echo ""

echo "============================================"
echo "PUBLIC KEY (for setup-strapi-site)"
echo "============================================"
echo "Copy this key to paste during setup-strapi-site:"
echo ""
cat "${KEY_PATH}.pub"
echo ""

# Copy to clipboard if available
if command -v pbcopy &> /dev/null; then
    cat "${KEY_PATH}.pub" | pbcopy
    echo "✅ Public key copied to clipboard (Mac)"
    echo ""
elif command -v xclip &> /dev/null; then
    cat "${KEY_PATH}.pub" | xclip -selection clipboard
    echo "✅ Public key copied to clipboard (Linux)"
    echo ""
fi

echo "============================================"
echo "PRIVATE KEY (for GitHub Secret)"
echo "============================================"
echo "Use this command to copy the private key for GitHub:"
echo ""
echo "  cat $KEY_PATH | pbcopy      # Mac"
echo "  cat $KEY_PATH | xclip -selection clipboard  # Linux"
echo "  cat $KEY_PATH               # View only"
echo ""

echo "============================================"
echo "Next Steps"
echo "============================================"
echo ""
echo "1. Save keys to team password manager (1Password/Bitwarden):"
echo "   - Title: Deploy Key - $CPANEL_USERNAME"
echo "   - Private Key: (content of $KEY_PATH)"
echo "   - Public Key: (content of ${KEY_PATH}.pub)"
echo ""
echo "2. When running setup-strapi-site:"
echo "   - Paste the PUBLIC key when prompted"
echo ""
echo "3. In GitHub repo Settings > Environments > <deploy branch name>:"
echo "   - Add environment SECRET: DEPLOY_SSH_PRIVATE_KEY = (content of $KEY_PATH)"
echo ""
echo "4. Share PUBLIC key with team (safe to share openly)"
echo "   Share PRIVATE key securely via password manager only"
echo ""
