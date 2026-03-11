#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

echo "========================================"
echo "♻️  Strapi Install & Restart PM2 Script"
echo "⏱️  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""
echo "ℹ️  This script installs dependencies and restarts PM2"
echo "   Build was already completed on GitHub Actions"
echo ""

START_TIME=$(date +%s)

# Define paths
MASTER_HOME="/home/master"
APP_ROOT="$(pwd)"

# Validate we're in the correct directory
if [ ! -f "${APP_ROOT}/package.json" ]; then
    echo "❌ Error: package.json not found in ${APP_ROOT}"
    echo "   Please run this script from the application root directory"
    exit 1
fi

# Check if this is a Strapi project
if ! grep -q "\"@strapi/strapi\"" "${APP_ROOT}/package.json"; then
    echo "⚠️  Warning: This doesn't appear to be a Strapi project"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Validate toolkit installation
if [ ! -d "${APP_ROOT}/strapi-toolkit" ]; then
    echo "❌ Error: strapi-toolkit directory not found"
    echo "   Please install the toolkit first:"
    echo "   curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/install.sh | bash"
    exit 1
fi

if [ ! -f "${APP_ROOT}/strapi-toolkit/pm2/pm2-manager.sh" ]; then
    echo "❌ Error: strapi-toolkit/pm2/pm2-manager.sh not found"
    echo "   The toolkit installation appears to be incomplete"
    exit 1
fi

echo "✅ Toolkit installation verified"

# Load nvm from master user's home
export NVM_DIR="${MASTER_HOME}/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    \. "$NVM_DIR/nvm.sh"
    echo "✅ NVM loaded successfully"
else
    echo "❌ Error: NVM not found at $NVM_DIR/nvm.sh"
    exit 1
fi

# Install and use the Node version specified in .nvmrc
if [ -f "${APP_ROOT}/.nvmrc" ]; then
    NODE_VERSION=$(cat "${APP_ROOT}"/.nvmrc | tr -d '[:space:]')
    echo "📌 Node version required: ${NODE_VERSION}"

    # Validate Node version format
    if [[ ! $NODE_VERSION =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "❌ Error: Invalid Node version format in .nvmrc: ${NODE_VERSION}"
        exit 1
    fi

    # Install the version if not already installed
    echo "📦 Installing Node ${NODE_VERSION} (if needed)..."
    if ! nvm install "${NODE_VERSION}"; then
        echo "❌ Error: Failed to install Node ${NODE_VERSION}"
        exit 1
    fi

    # Use the version
    echo "✅ Switching to Node ${NODE_VERSION}"
    nvm use "${NODE_VERSION}"
else
    echo "⚠️  No .nvmrc found, using default Node version"
fi

# Setup PM2 environment
export PATH="${MASTER_HOME}/bin:${MASTER_HOME}/bin/npm/lib/node_modules/bin:${PATH}"
export PM2_HOME="${MASTER_HOME}/.pm2"

# Override HOME to public_html (parent of APP_ROOT) because:
# - App user's $HOME (/home/master/applications/appuser1/) is owned by root
# - public_html/ is the effective home for app user (writable)
# - Project is at public_html/gocomm-strapi/ (APP_ROOT)
# - Strapi creates $HOME/.config/com.strapi/config.json (unique UUID per app user)
# - .config should be at public_html level (shared by all projects under same app user)
export HOME="$(dirname "${APP_ROOT}")"

# Use per-app npm cache to avoid permission conflicts in multi-tenant environment
# Shared cache at /home/master/.npm causes EACCES errors when different apps
# create cache entries with different owners/permissions
# IMPORTANT: This must be set AFTER HOME is overridden above
export NPM_CONFIG_CACHE="${HOME}/.npm"

echo ""
echo "🔍 Environment Info:"
echo "   Working Directory: ${APP_ROOT}"
echo "   HOME Override: ${HOME}"
echo "   Node Version: $(node --version)"
echo "   NPM Version: $(npm --version)"
echo "   PM2 Path: $(which pm2)"
echo "   PM2 Home: ${PM2_HOME}"
echo "   NPM Cache: ${NPM_CONFIG_CACHE}"

echo ""
echo "🔧 Checking critical directories and permissions..."

# Ensure npm cache directory exists with correct permissions
if [ ! -d "${NPM_CONFIG_CACHE}" ]; then
    echo "📁 Creating npm cache directory: ${NPM_CONFIG_CACHE}"
    mkdir -p "${NPM_CONFIG_CACHE}" 2>/dev/null || {
        echo "❌ Error: Cannot create npm cache directory"
        exit 1
    }
fi

# Set correct permissions on npm cache directory
chmod 775 "${NPM_CONFIG_CACHE}" 2>/dev/null || echo "⚠️  Warning: Cannot set npm cache permissions"
echo "✅ npm cache directory ready: ${NPM_CONFIG_CACHE}"

# Check .env file exists and has correct permissions
if [ ! -f "${APP_ROOT}/.env" ]; then
    echo "❌ Error: .env file not found!"
    echo "   Please ensure .env exists on the server before deploying."
    exit 1
fi

ENV_PERMS=$(stat -c "%a" "${APP_ROOT}/.env" 2>/dev/null || stat -f "%Lp" "${APP_ROOT}/.env" 2>/dev/null)
if [ "$ENV_PERMS" != "644" ] && [ "$ENV_PERMS" != "664" ]; then
    echo "⚠️  Warning: .env has restrictive permissions ($ENV_PERMS)"
    echo "   Fixing to 644 (readable by PM2)..."
    if chmod 644 "${APP_ROOT}/.env" 2>/dev/null; then
        echo "✅ .env permissions fixed"
    else
        echo "❌ Error: Cannot change .env permissions"
        echo "   Run: bash strapi-toolkit/cloudways/init-app-permissions.sh"
        exit 1
    fi
else
    echo "✅ .env permissions correct ($ENV_PERMS)"
fi

# Check app root directory permissions
APP_ROOT_PERMS=$(stat -c "%a" "${APP_ROOT}" 2>/dev/null || stat -f "%Lp" "${APP_ROOT}" 2>/dev/null)
APP_ROOT_GROUP=$(stat -c "%G" "${APP_ROOT}" 2>/dev/null || stat -f "%Sg" "${APP_ROOT}" 2>/dev/null)

if [ "$APP_ROOT_GROUP" != "www-data" ] || [[ ! "$APP_ROOT_PERMS" =~ ^[27]7[57]$ ]]; then
    echo "⚠️  Warning: App directory has suboptimal permissions"
    echo "   Current: $APP_ROOT_PERMS (group: $APP_ROOT_GROUP)"
    echo "   Recommended: 775 (group: www-data)"
    echo "   This may cause permission issues during deployment"
    echo "   Fix by running: bash strapi-toolkit/cloudways/init-app-permissions.sh"
fi

# Verify built files exist (should come from GitHub Actions)
echo ""
echo "🔍 Verifying build artifacts from GitHub Actions..."
if [ -d "${APP_ROOT}/dist" ] || [ -d "${APP_ROOT}/build" ]; then
    BUILD_DIR=$([ -d "${APP_ROOT}/dist" ] && echo "dist" || echo "build")
    BUILD_SIZE=$(du -sh "${APP_ROOT}/${BUILD_DIR}" | cut -f1)
    echo "✅ Build directory found: ${BUILD_DIR}/ (${BUILD_SIZE})"
else
    echo "⚠️  WARNING: No dist/ or build/ directory found!"
    echo "   This means the build from GitHub Actions may have failed"
    echo "   or rsync didn't sync the built files properly."
    echo ""
    read -p "Continue anyway? This may cause the app to fail. (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "📦 Installing production dependencies..."

# Clean node_modules to prevent ENOTEMPTY errors from stale state
if [ -d "${APP_ROOT}/node_modules" ]; then
    echo "🧹 Removing existing node_modules for clean install..."

    # Try to remove with force, suppressing errors initially
    rm -rf "${APP_ROOT}/node_modules" 2>/dev/null || true

    # Check if removal was successful
    if [ -d "${APP_ROOT}/node_modules" ]; then
        echo "⚠️  Warning: Some directories could not be removed"
        echo "   Retrying after 3 seconds (files may be temporarily locked)..."
        sleep 3

        # Retry removal
        rm -rf "${APP_ROOT}/node_modules" 2>/dev/null || true

        if [ -d "${APP_ROOT}/node_modules" ]; then
            echo "❌ Error: Failed to remove node_modules after retry"
            echo "   This may indicate permission issues or locked files"
            echo "   Fix by running: bash strapi-toolkit/cloudways/init-app-permissions.sh"
            exit 1
        else
            echo "✅ node_modules removed (after retry)"
        fi
    else
        echo "✅ node_modules removed"
    fi
fi

INSTALL_START=$(date +%s)

# Set umask to ensure group write permissions (002 = rwxrwxr-x for directories)
umask 002

# Clean install with production dependencies only
if npm ci --omit=dev; then
    INSTALL_END=$(date +%s)
    INSTALL_DURATION=$((INSTALL_END - INSTALL_START))
    echo "✅ Dependencies installed in ${INSTALL_DURATION}s"

    # Verify strapi binary exists (required for runtime)
    if [ ! -f "${APP_ROOT}/node_modules/.bin/strapi" ]; then
        echo "❌ Error: strapi binary not found after npm ci"
        echo "   Expected: ${APP_ROOT}/node_modules/.bin/strapi"
        echo "   This indicates an incomplete or corrupted installation"
        echo ""
        echo "   Checking @strapi/strapi package..."
        if [ -d "${APP_ROOT}/node_modules/@strapi/strapi" ]; then
            echo "   @strapi/strapi package directory exists"
            ls -la "${APP_ROOT}/node_modules/@strapi/strapi/bin" 2>/dev/null || echo "   No bin directory found"
        else
            echo "   @strapi/strapi package directory NOT found"
        fi
        exit 1
    fi
    echo "✅ strapi binary verified"
else
    echo "❌ Error: npm ci failed"
    exit 1
fi

echo ""
echo "📊 Disk Usage:"
echo "   App Directory: $(du -sh "${APP_ROOT}" | cut -f1)"
echo "   node_modules: $(du -sh "${APP_ROOT}"/node_modules 2>/dev/null | cut -f1 || echo 'N/A')"
echo "   Build Output: $(du -sh "${APP_ROOT}"/dist 2>/dev/null | cut -f1 || du -sh "${APP_ROOT}"/build 2>/dev/null | cut -f1 || echo 'N/A')"

echo ""
echo "♻️  Restarting PM2..."
RESTART_START=$(date +%s)

if bash "${APP_ROOT}"/strapi-toolkit/pm2/pm2-manager.sh restart; then
    RESTART_END=$(date +%s)
    RESTART_DURATION=$((RESTART_END - RESTART_START))
    echo "✅ PM2 restarted in ${RESTART_DURATION}s"
    echo "   Downtime: ~${RESTART_DURATION}s (graceful reload)"
else
    echo "❌ Error: PM2 restart failed"
    exit 1
fi

echo ""
bash "${APP_ROOT}"/strapi-toolkit/pm2/pm2-manager.sh status

echo ""
echo "📝 Recent Logs (last 15 lines):"
bash "${APP_ROOT}"/strapi-toolkit/pm2/pm2-manager.sh logs 15

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo ""
echo "========================================"
echo "✅ Deployment Complete!"
echo "⏱️  Total Duration: ${TOTAL_DURATION}s"
echo "🕐 Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""
echo "ℹ️  Note: Build was completed on GitHub Actions"
echo "   This script only installed dependencies and restarted PM2"
echo ""
