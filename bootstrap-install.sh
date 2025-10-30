#!/bin/bash
# Bootstrap Installer for Strapi DevOps Toolkit (Private Repo)
# This script can be hosted as a public gist
# Usage: curl -fsSL https://gist.githubusercontent.com/.../bootstrap-install.sh | bash

set -e

REPO="orange-soft/gocomm-strapi"
TEMP_DIR="/tmp/strapi-toolkit-$$"

echo "========================================"
echo "📦 Strapi DevOps Toolkit Installer"
echo "========================================"
echo ""

# Check authentication methods
if command -v gh &> /dev/null; then
    # GitHub CLI available
    echo "✓ GitHub CLI detected"
    echo ""

    # Check if authenticated
    if gh auth status &> /dev/null; then
        echo "✓ Already authenticated with GitHub"
    else
        echo "Please authenticate with GitHub:"
        gh auth login
    fi

    echo ""
    echo "📥 Downloading toolkit..."

    # Clone using gh (works with private repos)
    gh repo clone "$REPO" "$TEMP_DIR" -- --depth 1 --filter=blob:none --sparse
    cd "$TEMP_DIR"
    git sparse-checkout set scripts

    # Run installer
    bash scripts/install.sh

    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"

elif [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
    # SSH key exists
    echo "✓ SSH key detected"
    echo ""
    echo "📥 Downloading toolkit via SSH..."

    # Try SSH clone
    if git clone --depth 1 "git@github.com:${REPO}.git" "$TEMP_DIR" 2>/dev/null; then
        cd "$TEMP_DIR"
        bash scripts/install.sh
        cd /
        rm -rf "$TEMP_DIR"
    else
        echo ""
        echo "❌ SSH authentication failed"
        echo ""
        echo "Please ensure:"
        echo "  1. Your SSH key is added to GitHub"
        echo "  2. You have access to the repository"
        echo ""
        echo "Or install GitHub CLI for easier authentication:"
        echo "  brew install gh (macOS)"
        echo "  sudo apt install gh (Ubuntu/Debian)"
        exit 1
    fi
else
    # No authentication method available
    echo "❌ No authentication method found"
    echo ""
    echo "Please install GitHub CLI:"
    echo "  macOS: brew install gh"
    echo "  Ubuntu/Debian: sudo apt install gh"
    echo "  CentOS/RHEL: sudo yum install gh"
    echo ""
    echo "Or configure SSH keys:"
    echo "  ssh-keygen -t ed25519 -C 'your_email@example.com'"
    echo "  # Then add ~/.ssh/id_ed25519.pub to GitHub"
    exit 1
fi

echo ""
echo "✅ Installation complete!"
