#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

echo "========================================"
echo "🚀 Strapi Build & Restart PM2 Script"
echo "⏱️  Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

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

# Set npm cache explicitly to master's location (accessible to www-data group)
export NPM_CONFIG_CACHE="${MASTER_HOME}/.npm"

# Override HOME to public_html (parent of APP_ROOT) because:
# - App user's $HOME (/home/master/applications/appuser1/) is owned by root
# - public_html/ is the effective home for app user (writable)
# - Project is at public_html/gocomm-strapi/ (APP_ROOT)
# - Strapi creates $HOME/.config/com.strapi/config.json (unique UUID per app user)
# - .config should be at public_html level (shared by all projects under same app user)
export HOME="$(dirname "${APP_ROOT}")"

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
echo "🔧 Checking app directory permissions..."

# Check if app root has correct permissions (775 with www-data group and setgid bit)
APP_ROOT_PERMS=$(stat -c "%a" "${APP_ROOT}" 2>/dev/null || stat -f "%Lp" "${APP_ROOT}" 2>/dev/null)
APP_ROOT_GROUP=$(stat -c "%G" "${APP_ROOT}" 2>/dev/null || stat -f "%Sg" "${APP_ROOT}" 2>/dev/null)
APP_ROOT_SETGID=$(stat -c "%A" "${APP_ROOT}" 2>/dev/null | grep -q 's' && echo "yes" || echo "no")
# Linux fallback for setgid check
if [ "$APP_ROOT_SETGID" = "no" ]; then
    APP_ROOT_SETGID=$(ls -ld "${APP_ROOT}" | awk '{print $1}' | grep -q 's' && echo "yes" || echo "no")
fi

# Permissions are correct if: 2775 or 775, group is www-data, and setgid bit is set
PERMS_OK="no"
if ([ "$APP_ROOT_PERMS" = "2775" ] || [ "$APP_ROOT_PERMS" = "775" ]) && \
   [ "$APP_ROOT_GROUP" = "www-data" ] && \
   [ "$APP_ROOT_SETGID" = "yes" ]; then
    PERMS_OK="yes"
fi

if [ "$PERMS_OK" = "yes" ]; then
    echo "✅ App directory permissions already correct (775, www-data, setgid)"
else
    echo "⚠️  App directory permissions need fixing"
    echo "   Current: ${APP_ROOT_PERMS} (group: ${APP_ROOT_GROUP}, setgid: ${APP_ROOT_SETGID})"
    echo "   Expected: 2775 or 775 (group: www-data, setgid: yes)"
    echo ""

    if [ -f "${APP_ROOT}/strapi-toolkit/cloudways/init-app-permissions.sh" ]; then
        echo "🔧 Running init-app-permissions.sh to fix permissions..."
        bash "${APP_ROOT}/strapi-toolkit/cloudways/init-app-permissions.sh"
        echo ""
    else
        echo "⚠️  Warning: init-app-permissions.sh not found in toolkit"
        echo "   Permissions may cause issues. Consider running manually:"
        echo "   bash strapi-toolkit/cloudways/init-app-permissions.sh"
        echo ""
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
        echo "   Trying with group write permissions fix..."

        # Fix group permissions (www-data group needs write access)
        chmod -R g+w "${APP_ROOT}/node_modules" 2>/dev/null || true
        rm -rf "${APP_ROOT}/node_modules" 2>/dev/null || true

        if [ -d "${APP_ROOT}/node_modules" ]; then
            echo "❌ Error: Failed to fully remove node_modules"
            echo "   npm ci may fail with ENOTEMPTY errors"
            echo "   This may require manual cleanup or fix-permissions.sh"
        else
            echo "✅ node_modules removed (after permission fix)"
        fi
    else
        echo "✅ node_modules removed"
    fi
fi

INSTALL_START=$(date +%s)

# Verify .env file exists and has correct permissions
if [ ! -f "${APP_ROOT}/.env" ]; then
    echo "❌ Error: .env file not found!"
    echo "   Please ensure .env exists on the server before deploying."
    exit 1
fi

# Ensure .env is readable by PM2 process (needs 644 or 664)
echo "🔒 Checking .env file permissions..."
CURRENT_PERMS=$(stat -c "%a" "${APP_ROOT}/.env" 2>/dev/null || stat -f "%Lp" "${APP_ROOT}/.env" 2>/dev/null)

if [ "$CURRENT_PERMS" != "644" ] && [ "$CURRENT_PERMS" != "664" ]; then
    echo "   Current permissions: $CURRENT_PERMS (needs to be 644 or 664)"
    echo "   Fixing .env permissions to 644..."
    chmod 644 "${APP_ROOT}/.env"
    echo "✅ .env permissions fixed"
else
    echo "✅ .env permissions correct ($CURRENT_PERMS)"
fi

# Set umask to ensure group write permissions (002 = rwxrwxr-x for directories)
umask 002

# Clean install with production dependencies only
if npm ci --omit=dev --loglevel=error; then
    INSTALL_END=$(date +%s)
    INSTALL_DURATION=$((INSTALL_END - INSTALL_START))
    echo "✅ Dependencies installed in ${INSTALL_DURATION}s"
else
    echo "❌ Error: npm ci failed"
    exit 1
fi

echo ""
echo "🏗️  Building Strapi admin panel..."
echo "   (App remains running during build - zero downtime deployment)"
BUILD_START=$(date +%s)

# Ensure directories exist (permissions should be set by master user via fix-permissions.sh)
echo "📁 Ensuring required directories exist..."
mkdir -p "${HOME}/.config" 2>/dev/null || true
mkdir -p "${HOME}/.config/com.strapi" 2>/dev/null || true
mkdir -p "${APP_ROOT}/.cache" 2>/dev/null || true
mkdir -p "${APP_ROOT}/.strapi" 2>/dev/null || true

if NODE_ENV=production npm run build; then
    BUILD_END=$(date +%s)
    BUILD_DURATION=$((BUILD_END - BUILD_START))
    echo "✅ Build completed in ${BUILD_DURATION}s"
else
    echo "❌ Error: Build failed"
    echo "   App continues running with old version (no downtime)"
    exit 1
fi

echo ""
echo "📊 Disk Usage:"
echo "   App Directory: $(du -sh "${APP_ROOT}" | cut -f1)"
echo "   node_modules: $(du -sh "${APP_ROOT}"/node_modules 2>/dev/null | cut -f1 || echo 'N/A')"
echo "   Build Output: $(du -sh "${APP_ROOT}"/dist 2>/dev/null | cut -f1 || du -sh "${APP_ROOT}"/build 2>/dev/null | cut -f1 || echo 'N/A')"

echo ""
echo "♻️  Restarting PM2 with new build..."
# Restart only after successful build to minimize downtime
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
