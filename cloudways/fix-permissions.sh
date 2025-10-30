#!/bin/bash
# Script: Fix Master Home Directory Permissions for www-data Group
# Purpose: Ensure www-data group has write access to shared directories in /home/master/
# Context: Multi-tenant server where apps share master's NVM, NPM, PM2, and config

set -e

echo "========================================"
echo "🔧 Fix Master Home Group Permissions"
echo "⏱️  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

# Define paths
MASTER_HOME="/home/master"
APP_ROOT="$(pwd)"
GROUP="www-data"

echo "🔍 Environment Check:"
echo "   Master Home: ${MASTER_HOME}"
echo "   App Root: ${APP_ROOT}"
echo "   Group: ${GROUP}"
echo "   Current User: $(whoami)"
echo "   Current Groups: $(groups)"
echo ""

# Check if user is in www-data group
if groups | grep -q "\b${GROUP}\b"; then
    echo "✅ Current user is in ${GROUP} group"
else
    echo "⚠️  WARNING: Current user is NOT in ${GROUP} group"
    echo "   You may need to run this with a user in ${GROUP} group"
    echo ""
fi

# Function to fix directory permissions
fix_permissions() {
    local dir=$1
    local perms=$2
    local desc=$3

    echo "📁 ${desc}..."
    echo "   Path: ${dir}"

    # Create directory if it doesn't exist
    if [ ! -d "$dir" ]; then
        echo "   Creating directory..."
        if mkdir -p "$dir" 2>/dev/null; then
            echo "   ✅ Created"
        else
            echo "   ❌ Cannot create (may need master user or sudo)"
            return 1
        fi
    else
        echo "   ✅ Already exists"
    fi

    # Check current permissions and group
    echo "   Current: $(ls -ld "$dir" | awk '{print $1, $3, $4}')"

    # Set group permissions
    if chmod "$perms" "$dir" 2>/dev/null; then
        echo "   ✅ Permissions set to ${perms}"
    else
        echo "   ⚠️  Cannot change permissions (may need master user or sudo)"
    fi

    # Ensure group is www-data
    if chgrp "$GROUP" "$dir" 2>/dev/null; then
        echo "   ✅ Group set to ${GROUP}"
    else
        echo "   ⚠️  Cannot change group (may need master user or sudo)"
    fi

    echo ""
}

echo "========================================"
echo "Fixing Shared Directories in ${MASTER_HOME}"
echo "========================================"
echo ""

# Fix .npm cache (needs group write for npm ci)
fix_permissions "${MASTER_HOME}/.npm" "775" "NPM Cache Directory (WRITE needed)"

# Fix .pm2 directory (needs group write for pm2 save)
fix_permissions "${MASTER_HOME}/.pm2" "775" "PM2 Process Manager (WRITE needed)"

# Fix .config directory (needs group write for Strapi build)
fix_permissions "${MASTER_HOME}/.config" "775" "Config Directory (WRITE needed)"

# Fix .config/com.strapi subdirectory
if [ -d "${MASTER_HOME}/.config" ]; then
    fix_permissions "${MASTER_HOME}/.config/com.strapi" "775" "Strapi Config Directory (WRITE needed)"
fi

# .nvm directory (typically read-only, but check)
if [ -d "${MASTER_HOME}/.nvm" ]; then
    echo "📁 NVM Directory (READ-ONLY check)..."
    echo "   Path: ${MASTER_HOME}/.nvm"
    echo "   Current: $(ls -ld "${MASTER_HOME}/.nvm" | awk '{print $1, $3, $4}')"
    echo "   ℹ️  NVM installs need write access if installing new Node versions"
    echo "   ℹ️  If you see permission errors with 'nvm install', this needs 775"
    echo ""
fi

echo "========================================"
echo "Fixing App-Level Directories"
echo "========================================"
echo ""

# Fix app cache directories (in your app directory)
mkdir -p "${APP_ROOT}/.cache" 2>/dev/null || true
mkdir -p "${APP_ROOT}/.strapi" 2>/dev/null || true
mkdir -p "${APP_ROOT}/.tmp" 2>/dev/null || true

chmod 775 "${APP_ROOT}/.cache" 2>/dev/null || true
chmod 775 "${APP_ROOT}/.strapi" 2>/dev/null || true
chmod 775 "${APP_ROOT}/.tmp" 2>/dev/null || true

echo "✅ App cache directories created/verified"
echo ""

echo "========================================"
echo "Permission Summary"
echo "========================================"
echo ""
echo "Directories that need GROUP WRITE (775):"
echo "  ${MASTER_HOME}/.npm      - npm cache"
echo "  ${MASTER_HOME}/.pm2      - PM2 state files"
echo "  ${MASTER_HOME}/.config   - Strapi configuration"
echo ""
echo "Current status:"
ls -ld "${MASTER_HOME}/.npm" 2>/dev/null || echo "  .npm: NOT FOUND"
ls -ld "${MASTER_HOME}/.pm2" 2>/dev/null || echo "  .pm2: NOT FOUND"
ls -ld "${MASTER_HOME}/.config" 2>/dev/null || echo "  .config: NOT FOUND"
echo ""

echo "========================================"
echo "Next Steps"
echo "========================================"
echo ""
echo "If you see permission warnings above:"
echo ""
echo "Option 1: Run as master user (or sudo)"
echo "  sudo -u master bash scripts/fix-permissions.sh"
echo ""
echo "Option 2: Ask master user to run these commands:"
echo "  chmod -R 775 ${MASTER_HOME}/.npm"
echo "  chmod -R 775 ${MASTER_HOME}/.pm2"
echo "  chmod -R 775 ${MASTER_HOME}/.config"
echo "  chgrp -R ${GROUP} ${MASTER_HOME}/.npm"
echo "  chgrp -R ${GROUP} ${MASTER_HOME}/.pm2"
echo "  chgrp -R ${GROUP} ${MASTER_HOME}/.config"
echo ""
echo "After fixing permissions:"
echo "  ./scripts/build-and-restart-pm2.sh"
echo ""
