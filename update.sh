#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Cloudways Strapi Toolkit Updater
# Usage: bash strapi-toolkit/update.sh [--yes]
#
# Safe self-update:
#   1. Download the latest version into a temp dir next to the toolkit
#   2. Verify it (required files present, all scripts pass `bash -n`)
#   3. Swap it in with two renames; the old version is only deleted after the swap
# On any failure or Ctrl+C the installed toolkit stays untouched (or is restored)
# and the temp dir is removed.

# Everything runs inside main(), so bash has parsed the whole file before this
# script replaces its own directory
main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    TOOLKIT_NAME="$(basename "$SCRIPT_DIR")"
    REPO_URL="https://github.com/orange-soft/cw-strapi-toolkit.git"
    REPO_BRANCH="master"
    TMP_PREFIX=".${TOOLKIT_NAME}-update."
    TMP_DIR=""
    ASSUME_YES=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes) ASSUME_YES=1; shift ;;
            -h|--help)
                echo "Usage: bash ${TOOLKIT_NAME}/update.sh [--yes]"
                echo ""
                echo "  -y, --yes   Update without asking (for CI / non-interactive shells)"
                exit 0
                ;;
            *) echo "❌ Error: Unknown option: $1"; exit 1 ;;
        esac
    done

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

    if ! command -v git &> /dev/null; then
        echo "❌ Error: git is not installed"
        exit 1
    fi

    # Leave the toolkit dir, so moving it never strands our working directory
    cd "$PARENT_DIR"

    remove_stale_temp_dirs

    trap cleanup EXIT
    trap 'exit 130' INT TERM

    if ! TMP_DIR="$(mktemp -d "${PARENT_DIR}/${TMP_PREFIX}XXXXXX")"; then
        echo "❌ Error: Cannot create temp dir in ${PARENT_DIR}"
        exit 1
    fi

    echo "📥 Downloading latest version..."
    if ! git clone --quiet --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMP_DIR/new"; then
        echo "❌ Error: Failed to download the toolkit (installed version left untouched)"
        exit 1
    fi

    NEW_VERSION="$(git -C "$TMP_DIR/new" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
    rm -rf "$TMP_DIR/new/.git"

    verify_toolkit "$TMP_DIR/new"

    # Compare file contents instead of keeping version state
    if diff -rq "$SCRIPT_DIR" "$TMP_DIR/new" > /dev/null 2>&1; then
        echo "✅ Already up to date! (version ${NEW_VERSION})"
        exit 0
    fi

    echo ""
    echo "📦 Update available: version ${NEW_VERSION}"
    echo "📝 Changed files:"
    diff -rq "$SCRIPT_DIR" "$TMP_DIR/new" 2>/dev/null \
        | sed -e "s#${TMP_DIR}/new#[new]#g" -e "s#${SCRIPT_DIR}#[installed]#g" \
        | head -20 | sed 's/^/   /' || true
    echo ""
    echo "⚠️  Update replaces the whole toolkit directory:"
    echo "   - Any local modifications will be removed"
    echo "   - Files deleted from the repository will be removed locally"
    echo ""

    if ! confirm "Update to latest version?"; then
        echo "Update cancelled."
        exit 0
    fi

    echo ""
    echo "🔄 Installing..."
    swap_in "$TMP_DIR/new"

    echo ""
    echo "========================================"
    echo "✅ Toolkit Updated Successfully! (version ${NEW_VERSION})"
    echo "========================================"
    echo ""
    echo "💡 Next steps:"
    echo "   - Review changes: cat ${SCRIPT_DIR}/README.md"
    echo "   - Test scripts: bash ${SCRIPT_DIR}/pm2/pm2-manager.sh status"
    echo ""
}

# Remove temp dirs left by an update that was killed (e.g. SIGKILL) over an hour ago
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

# Ask for confirmation; reads from the terminal even under `curl | bash`
confirm() {
    local reply=""
    [ "$ASSUME_YES" = 1 ] && return 0

    if [ -t 0 ]; then
        read -p "$1 (y/n) " -n 1 -r reply
    elif { : < /dev/tty; } 2>/dev/null; then
        read -p "$1 (y/n) " -n 1 -r reply < /dev/tty
    else
        echo "❌ Error: No terminal to confirm the update; re-run with --yes"
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
            echo "❌ Error: Downloaded toolkit is missing ${file} (installed version left untouched)"
            exit 1
        fi
    done

    while IFS= read -r file; do
        if ! bash -n "$file" 2>/dev/null; then
            echo "❌ Error: Downloaded script has syntax errors: ${file#"$dir"/} (installed version left untouched)"
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
