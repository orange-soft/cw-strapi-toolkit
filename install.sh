#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Cloudways Strapi Toolkit Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash
# Or: bash install.sh [--yes]
# Non-interactive: curl -fsSL .../install.sh | bash -s -- --yes
#
# Downloads into a temp dir, verifies, then moves into ./strapi-toolkit. An existing
# install is only replaced after a verified download, and restored on failure.

# Everything runs inside main(), so a truncated `curl | bash` download never runs
# half a script, and bash has parsed the whole file before anything is changed
main() {
    PARENT_DIR="$(pwd)"
    TOOLKIT_NAME="strapi-toolkit"
    INSTALL_DIR="./${TOOLKIT_NAME}"
    SCRIPT_DIR="${PARENT_DIR}/${TOOLKIT_NAME}"
    REPO_URL="https://github.com/orange-soft/cw-strapi-toolkit.git"
    REPO_BRANCH="master"
    TMP_PREFIX=".${TOOLKIT_NAME}-update."
    TMP_DIR=""
    ASSUME_YES=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes) ASSUME_YES=1; shift ;;
            *) echo "❌ Error: Unknown option: $1"; exit 1 ;;
        esac
    done

    echo "========================================"
    echo "📦 Cloudways Strapi Toolkit Installer"
    echo "========================================"
    echo ""
    echo "Installing to: ${SCRIPT_DIR}"
    echo ""

    # Check if git is installed
    if ! command -v git &> /dev/null; then
        echo "❌ Error: git is not installed"
        echo "   Please install git first"
        exit 1
    fi

    if [ -e "$SCRIPT_DIR" ]; then
        echo "⚠️  Toolkit already installed at: $INSTALL_DIR"
        if ! confirm "Update to latest version?"; then
            echo "Installation cancelled."
            exit 0
        fi
    fi

    remove_stale_temp_dirs

    trap cleanup EXIT
    trap 'exit 130' INT TERM

    if ! TMP_DIR="$(mktemp -d "${PARENT_DIR}/${TMP_PREFIX}XXXXXX")"; then
        echo "❌ Error: Cannot create temp dir in ${PARENT_DIR}"
        exit 1
    fi

    echo "📥 Downloading toolkit..."
    if ! git clone --quiet --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMP_DIR/new"; then
        echo "❌ Error: Failed to download the toolkit"
        exit 1
    fi

    # Remove .git folder to allow versioning in parent repo (prevents submodule conflicts)
    rm -rf "$TMP_DIR/new/.git"

    verify_toolkit "$TMP_DIR/new"

    if [ -e "$SCRIPT_DIR" ]; then
        swap_in "$TMP_DIR/new"
        echo "✅ Toolkit updated!"
    else
        mv "$TMP_DIR/new" "$SCRIPT_DIR"
        echo "✅ Toolkit installed!"
    fi

    echo ""
    echo "========================================"
    echo "📋 Available Scripts:"
    echo "========================================"
    echo ""
    echo "Deployment:"
    echo "  ${INSTALL_DIR}/deploy/build-and-restart.sh"
    echo "  ${INSTALL_DIR}/deploy/restart-only.sh"
    echo ""
    echo "PM2 Management:"
    echo "  ${INSTALL_DIR}/pm2/pm2-manager.sh"
    echo ""
    echo "Backup/Restore:"
    echo "  ${INSTALL_DIR}/backup/export.sh"
    echo "  ${INSTALL_DIR}/backup/import.sh"
    echo ""
    echo "Database:"
    echo "  ${INSTALL_DIR}/database/check-and-fix-encoding.sh"
    echo ""
    echo "Setup:"
    echo "  ${INSTALL_DIR}/setup/generate-env-keys.sh"
    echo "  ${INSTALL_DIR}/setup/setup-env-keys.sh"
    echo ""
    echo "Cloudways Utilities:"
    echo "  ${INSTALL_DIR}/cloudways/init-app-permissions.sh"
    echo "  ${INSTALL_DIR}/cloudways/fix-master-permissions.sh"
    echo "  ${INSTALL_DIR}/cloudways/check-ports.sh"
    echo "  ${INSTALL_DIR}/cloudways/sync-to-cloudways.sh"
    echo ""
    echo "cPanel Utilities (server setup, see cpanel/README.md):"
    echo "  ${INSTALL_DIR}/cpanel/setup-site.sh"
    echo "  ${INSTALL_DIR}/cpanel/generate-deploy-key.sh"
    echo "  ${INSTALL_DIR}/cpanel/pm2-boot-service.sh"
    echo ""
    echo "========================================"
    echo "💡 Quick Start:"
    echo "========================================"
    echo ""
    echo "1. Use scripts directly from current directory:"
    echo "   bash ${INSTALL_DIR}/backup/export.sh"
    echo ""
    echo "2. Or create an alias in your shell profile:"
    echo "   alias strapi-backup='bash ${SCRIPT_DIR}/backup/export.sh'"
    echo ""
    echo "3. Read the documentation:"
    echo "   cat ${INSTALL_DIR}/README.md"
    echo ""
    echo "4. Update toolkit later:"
    echo "   bash ${INSTALL_DIR}/update.sh"
    echo ""
    echo "✅ Installation complete!"
}

# Remove temp dirs left by an install that was killed (e.g. SIGKILL) over an hour ago
remove_stale_temp_dirs() {
    find "$PARENT_DIR" -maxdepth 1 -type d -name "${TMP_PREFIX}*" -mmin +60 \
        -exec rm -rf {} + 2>/dev/null || true
}

# Runs on every exit: restore the old version if interrupted mid-swap, then
# remove the temp dir (holds the download and, after a swap, the old version)
cleanup() {
    local status=$?
    trap - EXIT

    if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
        if [ ! -e "$SCRIPT_DIR" ] && [ -d "$TMP_DIR/old" ]; then
            if mv "$TMP_DIR/old" "$SCRIPT_DIR"; then
                echo "↩️  Restored previous version"
            else
                echo "❌ Could not restore previous version; it is at: $TMP_DIR/old"
                exit "$status"
            fi
        fi

        if ! rm -rf "$TMP_DIR" 2>/dev/null; then
            echo "⚠️  Could not fully remove ${TMP_DIR} (check file ownership); delete it manually"
        fi
    fi

    exit "$status"
}

# Ask for confirmation; reads from the terminal even under `curl | bash`,
# where stdin is the script itself
confirm() {
    local reply=""
    [ "$ASSUME_YES" = 1 ] && return 0

    if [ -t 0 ]; then
        read -p "$1 (y/n) " -n 1 -r reply
    elif { : < /dev/tty; } 2>/dev/null; then
        read -p "$1 (y/n) " -n 1 -r reply < /dev/tty
    else
        echo "❌ Error: No terminal to confirm; re-run with --yes (curl ... | bash -s -- --yes)"
        exit 1
    fi
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

# Refuse a download that looks incomplete or broken
verify_toolkit() {
    local dir="$1" file
    for file in install.sh update.sh deploy/build-and-restart.sh pm2/pm2-manager.sh; do
        if [ ! -s "$dir/$file" ]; then
            echo "❌ Error: Downloaded toolkit is missing ${file}"
            exit 1
        fi
    done

    while IFS= read -r file; do
        if ! bash -n "$file" 2>/dev/null; then
            echo "❌ Error: Downloaded script has syntax errors: ${file#"$dir"/}"
            exit 1
        fi
    done < <(find "$dir" -name '*.sh' -type f)

    echo "✅ Download verified"
}

# Two renames on the same filesystem; the old version stays in TMP_DIR until
# cleanup, and is moved back if the second rename fails
swap_in() {
    local new_dir="$1"

    if ! mv "$SCRIPT_DIR" "$TMP_DIR/old"; then
        echo "❌ Error: Cannot move the installed toolkit (check permissions on ${PARENT_DIR})"
        exit 1
    fi

    if ! mv "$new_dir" "$SCRIPT_DIR"; then
        echo "❌ Error: Cannot move the new version into place"
        exit 1  # cleanup restores the old version
    fi
}

main "$@"
exit
