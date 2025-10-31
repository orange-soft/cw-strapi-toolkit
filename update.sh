#!/bin/bash
set -e

# Cloudways Strapi Toolkit Updater
# Usage: bash strapi-toolkit/update.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/orange-soft/cw-strapi-toolkit.git"
REPO_BRANCH="master"

echo "========================================"
echo "🔄 Cloudways Strapi Toolkit Updater"
echo "========================================"
echo ""
echo "Toolkit location: $SCRIPT_DIR"
echo ""

# Check if we're in the toolkit directory
if [ ! -f "$SCRIPT_DIR/install.sh" ]; then
    echo "❌ Error: This doesn't appear to be the toolkit directory"
    echo "   Expected to find install.sh"
    exit 1
fi

# Check current version (last commit)
if [ -d "$SCRIPT_DIR/.git" ]; then
    CURRENT_VERSION=$(cd "$SCRIPT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "📌 Current version: $CURRENT_VERSION"
else
    echo "📌 Current version: (non-git installation)"
fi

# Fetch latest version info
echo ""
echo "🔍 Checking for updates..."

if [ -d "$SCRIPT_DIR/.git" ]; then
    # Git-tracked installation - use git operations then remove .git
    cd "$SCRIPT_DIR"

    # Fetch latest changes
    git fetch origin "$REPO_BRANCH" 2>/dev/null || {
        echo "❌ Error: Failed to fetch updates from remote"
        exit 1
    }

    # Check if updates are available
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/"$REPO_BRANCH")

    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "✅ Already up to date!"
        echo ""
        echo "📌 Current version: $(git rev-parse --short HEAD)"

        # Even if up-to-date, ensure .git is removed (for submodule compatibility)
        if [ -d ".git" ]; then
            echo ""
            echo "🧹 Removing .git folder (prevents git submodule conflicts)..."
            rm -rf .git
        fi

        exit 0
    fi

    echo "📦 Updates available!"
    echo "   Local:  $(git rev-parse --short HEAD)"
    echo "   Remote: $(git rev-parse --short origin/$REPO_BRANCH)"
    echo ""

    # Show what changed
    echo "📝 Recent changes:"
    git log --oneline HEAD..origin/"$REPO_BRANCH" | head -5
    echo ""

    echo "⚠️  Update method: Hard reset (ensures exact match with repository)"
    echo "   - Any local modifications will be removed"
    echo "   - Deleted files from repo will be removed locally"
    echo "   - New files will be added"
    echo "   - .git folder will be removed (prevents submodule conflicts)"
    echo ""

    read -p "Update to latest version? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Update cancelled."
        exit 0
    fi

    # Save version before removing .git
    NEW_VERSION=$(git rev-parse --short origin/"$REPO_BRANCH")

    echo ""
    echo "🔄 Updating..."

    # Use git reset --hard to ensure clean update
    # This removes any local changes and ensures exact match with remote
    git reset --hard origin/"$REPO_BRANCH"

    # Clean up any untracked files that might have been removed from repo
    git clean -fd

    echo "🧹 Removing .git folder (prevents git submodule conflicts)..."
    rm -rf .git

    echo ""
    echo "✅ Update complete!"
    echo "📌 New version: $NEW_VERSION"
    echo ""
    echo "⚠️  Note: .git folder removed to prevent conflicts with parent repository"

else
    # Non-git installation - need to re-download
    echo "⚠️  This is a non-git installation"
    echo "   To update, the toolkit will be re-downloaded"
    echo ""
    read -p "Continue with update? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Update cancelled."
        exit 0
    fi

    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    TOOLKIT_NAME="$(basename "$SCRIPT_DIR")"

    echo ""
    echo "🗑️  Removing old version..."
    rm -rf "$SCRIPT_DIR"

    echo "📥 Downloading latest version..."
    cd "$PARENT_DIR"
    git clone --depth 1 "$REPO_URL" "$TOOLKIT_NAME"

    echo "🧹 Cleaning up git metadata..."
    rm -rf "$SCRIPT_DIR/.git"

    echo ""
    echo "✅ Update complete!"
fi

echo ""
echo "========================================"
echo "✅ Toolkit Updated Successfully!"
echo "========================================"
echo ""
echo "💡 Next steps:"
echo "   - Review changes: cat $SCRIPT_DIR/FEATURES.md"
echo "   - Test scripts: bash $SCRIPT_DIR/pm2/pm2-manager.sh status"
echo ""
