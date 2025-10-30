#!/bin/bash
set -e

# Cloudways Strapi Toolkit Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/main/install.sh | bash
# Or: bash install.sh

INSTALL_DIR="./strapi-toolkit"
REPO_URL="https://github.com/orange-soft/cw-strapi-toolkit.git"
REPO_BRANCH="main"

echo "========================================"
echo "📦 Cloudways Strapi Toolkit Installer"
echo "========================================"
echo ""
echo "Installing to: $(pwd)/strapi-toolkit"
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Error: git is not installed"
    echo "   Please install git first"
    exit 1
fi

# Check if directory already exists
if [ -d "$INSTALL_DIR" ]; then
    echo "⚠️  Toolkit already installed at: $INSTALL_DIR"
    read -p "Update to latest version? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔄 Updating toolkit..."
        cd "$INSTALL_DIR"
        git pull origin "$REPO_BRANCH"
        echo "✅ Toolkit updated!"
    else
        echo "Installation cancelled."
        exit 0
    fi
else
    echo "📥 Installing toolkit..."

    # Clone repository
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"

    echo "✅ Toolkit installed!"
fi

echo ""
echo "========================================"
echo "📋 Available Scripts:"
echo "========================================"
echo ""
echo "Deployment:"
echo "  ${INSTALL_DIR}/deploy/build-and-restart.sh"
echo ""
echo "PM2 Management:"
echo "  ${INSTALL_DIR}/pm2/pm2-manager.sh"
echo ""
echo "Backup/Restore:"
echo "  ${INSTALL_DIR}/backup/export.sh"
echo "  ${INSTALL_DIR}/backup/import.sh"
echo ""
echo "Setup:"
echo "  ${INSTALL_DIR}/setup/generate-env-keys.sh"
echo "  ${INSTALL_DIR}/setup/setup-env-keys.sh"
echo ""
echo "Cloudways Utilities:"
echo "  ${INSTALL_DIR}/cloudways/fix-permissions.sh"
echo "  ${INSTALL_DIR}/cloudways/check-ports.sh"
echo "  ${INSTALL_DIR}/cloudways/sync-to-cloudways.sh"
echo ""
echo "========================================"
echo "💡 Quick Start:"
echo "========================================"
echo ""
echo "1. Use scripts directly from current directory:"
echo "   bash ${INSTALL_DIR}/backup/export.sh"
echo ""
echo "2. Or create an alias in your shell profile:"
echo "   alias strapi-backup='bash $(pwd)/${INSTALL_DIR}/backup/export.sh'"
echo ""
echo "3. View workflow examples:"
echo "   cat ${INSTALL_DIR}/WORKFLOW_EXAMPLES.md"
echo ""
echo "✅ Installation complete!"
