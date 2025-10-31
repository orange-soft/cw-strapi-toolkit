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
echo "📦 Installing production dependencies..."
INSTALL_START=$(date +%s)

# Verify .env file exists
if [ ! -f "${APP_ROOT}/.env" ]; then
    echo "❌ Error: .env file not found!"
    echo "   Please ensure .env exists on the server before deploying."
    exit 1
fi

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
echo "🛑 Stopping PM2 process..."
# Run stop command (ignore error if PM2 process is not running)
bash "${APP_ROOT}"/strapi-toolkit/pm2/pm2-manager.sh stop || true

echo ""
echo "🏗️  Building Strapi admin panel..."
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
    if [ -n "$ECOSYSTEM_CONFIG" ]; then
        echo "   Rolling back to previous PM2 state..."
        pm2 restart "${ECOSYSTEM_CONFIG}" || true
    fi
    exit 1
fi

echo ""
echo "📊 Disk Usage:"
echo "   App Directory: $(du -sh "${APP_ROOT}" | cut -f1)"
echo "   node_modules: $(du -sh "${APP_ROOT}"/node_modules 2>/dev/null | cut -f1 || echo 'N/A')"
echo "   Build Output: $(du -sh "${APP_ROOT}"/dist 2>/dev/null | cut -f1 || du -sh "${APP_ROOT}"/build 2>/dev/null | cut -f1 || echo 'N/A')"

echo ""
echo "♻️  Restarting PM2 process..."
RESTART_START=$(date +%s)

if bash "${APP_ROOT}"/strapi-toolkit/pm2/pm2-manager.sh restart; then
    RESTART_END=$(date +%s)
    RESTART_DURATION=$((RESTART_END - RESTART_START))
    echo "✅ PM2 restarted in ${RESTART_DURATION}s"
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
