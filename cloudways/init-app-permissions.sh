#!/bin/bash
# Script: Initialize App Directory Permissions
# Purpose: Set correct permissions for a new Cloudways app directory before first deployment
# Context: Cloudways creates public_html/app-name with potentially restrictive permissions
# Usage: Run this ONCE after creating a new app, BEFORE first deployment

set -e

echo "========================================"
echo "🎬 Initialize App Directory Permissions"
echo "⏱️  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

# Define paths
APP_ROOT="$(pwd)"
GROUP="www-data"

echo "🔍 Environment Check:"
echo "   App Root: ${APP_ROOT}"
echo "   Group: ${GROUP}"
echo "   Current User: $(whoami)"
echo "   Current Groups: $(groups)"
echo ""

# Validate we're in the right directory
if [ ! -f "${APP_ROOT}/package.json" ]; then
    echo "⚠️  WARNING: No package.json found in ${APP_ROOT}"
    echo "   Are you sure you're in the app root directory?"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Check if user is in www-data group
if groups | grep -q "\b${GROUP}\b"; then
    echo "✅ Current user is in ${GROUP} group"
else
    echo "⚠️  WARNING: Current user is NOT in ${GROUP} group"
    echo "   You may not have permission to set group ownership"
    echo ""
fi

echo "========================================"
echo "Fixing App Directory Permissions"
echo "========================================"
echo ""

echo "📁 App Root Directory..."
echo "   Path: ${APP_ROOT}"
echo "   Current: $(ls -ld "${APP_ROOT}" | awk '{print $1, $3, $4}')"

# Fix app root directory permissions
if chmod 775 "${APP_ROOT}" 2>/dev/null; then
    echo "   ✅ Permissions set to 775 (rwxrwxr-x)"
else
    echo "   ⚠️  Cannot change permissions"
fi

# Ensure group is www-data
if chgrp "${GROUP}" "${APP_ROOT}" 2>/dev/null; then
    echo "   ✅ Group set to ${GROUP}"
else
    echo "   ⚠️  Cannot change group"
fi

echo ""
echo "📁 Recursively fixing all subdirectories and files..."
echo "   This ensures everything inherits proper permissions"

# Fix all existing files and directories recursively
# Directories: 775 (rwxrwxr-x)
# Files: 664 (rw-rw-r--)
if find "${APP_ROOT}" -type d -exec chmod 775 {} \; 2>/dev/null; then
    echo "   ✅ All directories set to 775"
else
    echo "   ⚠️  Some directories could not be changed"
fi

if find "${APP_ROOT}" -type f -exec chmod 664 {} \; 2>/dev/null; then
    echo "   ✅ All files set to 664"
else
    echo "   ⚠️  Some files could not be changed"
fi

# Set group recursively
if chgrp -R "${GROUP}" "${APP_ROOT}" 2>/dev/null; then
    echo "   ✅ Group set to ${GROUP} recursively"
else
    echo "   ⚠️  Some files/directories could not change group"
fi

echo ""
echo "📁 Setting setgid bit on app root..."
echo "   This ensures new files/dirs inherit www-data group"

# Set setgid bit (g+s) on directories so new files inherit group
if chmod g+s "${APP_ROOT}" 2>/dev/null; then
    echo "   ✅ setgid bit set (new files will inherit www-data group)"
else
    echo "   ⚠️  Cannot set setgid bit"
fi

if find "${APP_ROOT}" -type d -exec chmod g+s {} \; 2>/dev/null; then
    echo "   ✅ setgid bit set on all subdirectories"
else
    echo "   ⚠️  Some directories could not set setgid bit"
fi

echo ""
echo "========================================"
echo "Creating Standard Directories"
echo "========================================"
echo ""

# Create standard directories with correct permissions
for dir in ".cache" ".strapi" ".tmp" "node_modules"; do
    if [ ! -d "${APP_ROOT}/${dir}" ]; then
        echo "📁 Creating ${dir}..."
        if mkdir -p "${APP_ROOT}/${dir}" 2>/dev/null; then
            chmod 775 "${APP_ROOT}/${dir}" 2>/dev/null || true
            chmod g+s "${APP_ROOT}/${dir}" 2>/dev/null || true
            chgrp "${GROUP}" "${APP_ROOT}/${dir}" 2>/dev/null || true
            echo "   ✅ Created with correct permissions"
        else
            echo "   ⚠️  Could not create ${dir}"
        fi
    else
        echo "📁 ${dir} already exists"
    fi
done

echo ""
echo "========================================"
echo "Permission Summary"
echo "========================================"
echo ""
echo "App root directory:"
ls -ld "${APP_ROOT}" 2>/dev/null || echo "  ERROR: Cannot read"
echo ""

echo "Standard directories:"
for dir in ".cache" ".strapi" ".tmp" "node_modules"; do
    if [ -d "${APP_ROOT}/${dir}" ]; then
        ls -ld "${APP_ROOT}/${dir}"
    fi
done

echo ""
echo "========================================"
echo "✅ App Initialization Complete!"
echo "========================================"
echo ""
echo "Next Steps:"
echo ""
echo "1. Verify permissions look correct above (should see 'drwxrwsr-x' with www-data group)"
echo "2. Run your first deployment:"
echo "   bash strapi-toolkit/deploy/build-and-restart.sh"
echo ""
echo "Note: You only need to run this script ONCE per app (at initialization)"
echo "Future deployments will inherit these permissions automatically."
echo ""
