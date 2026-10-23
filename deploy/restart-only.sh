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
APP_ROOT="$(pwd)"

# Locate nvm and PM2 for either server type:
# - cPanel: each site user has its own ~/.nvm and ~/.pm2 (or the legacy shared,
#   root-owned /opt/nvm with the user's own ~/.pm2)
# - Cloudways: every app shares the master user's ~/.nvm and ~/.pm2. Deploys log in
#   as the app user, whose home has no nvm, so the master home is used:
#   /home/master, or /mnt/BLOCKSTORAGE/home/master on block storage servers.
#   Override with MASTER_HOME.
# DEPLOY_SERVER_TYPE (cpanel|cloudways) forces the type; otherwise Cloudways is
# detected from the app path (.../applications/<app>/... or
# .../<server>.cloudwaysapps.com/<app>/...) and anything else is cPanel.
# Sets NVM_DIR, PM2_HOME, NODE_HOME (the home holding them), HOSTING (cpanel|cloudways)
# and HOSTING_SOURCE (set|detected)
resolve_node_env() {
    HOSTING="$(echo "${DEPLOY_SERVER_TYPE:-}" | tr '[:upper:]' '[:lower:]')"
    HOSTING_SOURCE="set"
    case "${HOSTING}" in
        cpanel|cloudways) ;;
        "")
            HOSTING_SOURCE="detected"
            HOSTING="cpanel"
            case "${APP_ROOT}" in
                */applications/*|*.cloudwaysapps.com/*) HOSTING="cloudways" ;;
            esac
            ;;
        *)
            echo "❌ Error: DEPLOY_SERVER_TYPE must be cpanel or cloudways (or unset), got: ${DEPLOY_SERVER_TYPE}"
            exit 1
            ;;
    esac

    # Real home of the login user: HOME may already be overridden to public_html
    local user_home
    user_home="$(eval echo "~$(id -un)")"

    local candidates=()
    [ -n "${MASTER_HOME:-}" ] && candidates+=("${MASTER_HOME}")
    if [ "${HOSTING}" = "cloudways" ]; then
        case "${APP_ROOT}" in
            */applications/*) candidates+=("${APP_ROOT%%/applications/*}") ;;
        esac
        candidates+=("/home/master" "/mnt/BLOCKSTORAGE/home/master")
    else
        candidates+=("${user_home}")
    fi

    local dir
    NODE_HOME=""
    for dir in "${candidates[@]}"; do
        if [ -s "${dir}/.nvm/nvm.sh" ]; then
            NODE_HOME="${dir}"
            NVM_DIR="${dir}/.nvm"
            break
        fi
    done
    if [ -z "${NODE_HOME}" ] && [ "${HOSTING}" = "cpanel" ] && [ -s "/opt/nvm/nvm.sh" ]; then
        NODE_HOME="${user_home}"
        NVM_DIR="/opt/nvm"
    fi
    [ -n "${NODE_HOME}" ] || return 1

    # Use real paths: on block storage servers /home/master is a symlink to
    # /mnt/BLOCKSTORAGE/home/master, and nvm refuses to switch Node ("nvm is not
    # compatible with the npm config prefix option") when NVM_DIR goes through it
    NVM_DIR="$(cd "${NVM_DIR}" && pwd -P)"
    NODE_HOME="$(cd "${NODE_HOME}" 2>/dev/null && pwd -P || echo "${NODE_HOME}")"

    PM2_HOME="${NODE_HOME}/.pm2"
    export NVM_DIR PM2_HOME NODE_HOME HOSTING HOSTING_SOURCE
}

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

# Load nvm (cPanel: the user's own; Cloudways: the master user's, shared by all apps)
if resolve_node_env; then
    \. "$NVM_DIR/nvm.sh"
    echo "✅ NVM loaded successfully (${HOSTING}, ${HOSTING_SOURCE}: ${NVM_DIR})"
else
    echo "❌ Error: NVM not found"
    if [ "${HOSTING}" = "cloudways" ]; then
        echo "   Tried: ${MASTER_HOME:+${MASTER_HOME}/.nvm, }/home/master/.nvm, /mnt/BLOCKSTORAGE/home/master/.nvm"
    else
        echo "   Tried: ~/.nvm, /opt/nvm"
    fi
    exit 1
fi

# Install and use the Node version specified in .nvmrc
if [ -f "${APP_ROOT}/.nvmrc" ]; then
    NODE_VERSION=$(cat "${APP_ROOT}"/.nvmrc | tr -d '[:space:]')
    echo "📌 Node version required: ${NODE_VERSION}"

    # Validate Node version format. A major-only version (e.g. "22") tracks the
    # latest patch release of that line, so security fixes land on the next deploy.
    if [[ ! $NODE_VERSION =~ ^v?[0-9]+(\.[0-9]+){0,2}$ ]]; then
        echo "❌ Error: Invalid Node version in .nvmrc: ${NODE_VERSION} (use 22, 22.23 or 22.23.4)"
        exit 1
    fi

    # Install the version if not already installed ("22" installs the latest 22.x if newer exists)
    echo "📦 Installing Node ${NODE_VERSION} (if needed)..."
    if ! nvm install "${NODE_VERSION}"; then
        echo "❌ Error: Failed to install Node ${NODE_VERSION}"
        exit 1
    fi

    # Use the version
    echo "✅ Switching to Node ${NODE_VERSION}"
    nvm use "${NODE_VERSION}"

    # On cPanel, make it the user's default too, so anything that only sources
    # nvm.sh (new shells, the PM2 boot service) finds the pm2 for this Node.
    # Cloudways nvm (and the legacy /opt/nvm) is shared, so its default is left alone.
    if [ "${HOSTING}" = "cpanel" ] && [ "${NVM_DIR}" != "/opt/nvm" ]; then
        nvm alias default "${NODE_VERSION}"
    fi
else
    echo "⚠️  No .nvmrc found, using default Node version"
fi

# Single source of truth for the runtime Node: pm2-manager.sh and ecosystem.config.cjs
# read NODE_BIN, so PM2 runs the same Node that installed/built the app
NODE_BIN="$(dirname "$(nvm which current 2>/dev/null || command -v node)")"
export NODE_BIN
echo "📌 Resolved Node: $(node --version) at ${NODE_BIN}"

# Setup PM2 environment (PM2_HOME was set by resolve_node_env)
export PATH="${NODE_HOME}/bin:${NODE_HOME}/bin/npm/lib/node_modules/bin:${PATH}"

# Override HOME to public_html (parent of APP_ROOT) because:
# - Cloudways app user's $HOME (/home/master/applications/appuser1/) is owned by root
# - public_html/ is the effective home for app user (writable)
# - Project is at public_html/gocomm-strapi/ (APP_ROOT)
# - Strapi creates $HOME/.config/com.strapi/config.json (unique UUID per app user)
# - .config should be at public_html level (shared by all projects under same app user)
export HOME="$(dirname "${APP_ROOT}")"

# Use per-app npm cache to avoid permission conflicts in multi-tenant environment
# A shared cache (e.g. /home/master/.npm on Cloudways) causes EACCES errors when different apps
# create cache entries with different owners/permissions
# IMPORTANT: This must be set AFTER HOME is overridden above
export NPM_CONFIG_CACHE="${HOME}/.npm"

echo ""
echo "🔍 Environment Info:"
echo "   Server Type: ${HOSTING} (${HOSTING_SOURCE})"
echo "   Login User: $(id -un) on $(hostname) (groups: $(id -Gn))"
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
        if [ "${HOSTING}" = "cloudways" ]; then
            echo "   Run: bash strapi-toolkit/cloudways/init-app-permissions.sh"
        else
            echo "   Run: chmod 644 ${APP_ROOT}/.env"
        fi
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
    if [ "${HOSTING}" = "cloudways" ]; then
        echo "   Fix by running: bash strapi-toolkit/cloudways/init-app-permissions.sh"
    else
        echo "   Fix by running: chown $(whoami):www-data ${APP_ROOT} && chmod 775 ${APP_ROOT}"
    fi
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
echo "ℹ️  Build was done on GitHub Actions, but node_modules is not synced"
echo "   (installed here so native modules match this server's Node and OS)"
INSTALL_START=$(date +%s)

# Set umask to ensure group write permissions (002 = rwxrwxr-x for directories)
umask 002

# Clean install with production dependencies only
if ! npm ci --omit=dev --no-audit --no-fund; then
    echo "❌ Error: npm ci failed"
    echo "   Try running: rm -rf ${APP_ROOT}/node_modules && npm ci --omit=dev"
    exit 1
fi

INSTALL_END=$(date +%s)
echo "✅ Dependencies installed in $((INSTALL_END - INSTALL_START))s"

# Verify strapi binary exists (required for runtime)
if [ ! -f "${APP_ROOT}/node_modules/.bin/strapi" ]; then
    echo "❌ Error: strapi binary not found after npm ci"
    echo "   Expected: ${APP_ROOT}/node_modules/.bin/strapi"
    echo "   This indicates an incomplete or corrupted installation"
    exit 1
fi

echo "✅ strapi binary verified"

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
    echo "✅ PM2 restarted and Strapi serving again after ${RESTART_DURATION}s"
    echo "   Downtime: up to ~${RESTART_DURATION}s (restart + Strapi startup)"
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
