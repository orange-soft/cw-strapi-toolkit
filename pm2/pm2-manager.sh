#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Script: PM2 Process Manager
# Description: Manages PM2 operations (start, stop, restart, status)
# Usage: ./pm2-manager.sh [start|stop|restart|status|delete]
# Note: Can be called directly or from other scripts (inherits parent environment)

APP_ROOT="$(pwd)"

# Only setup environment if not already configured by parent script
# This allows the script to be called standalone or from build-and-restart.sh
if [ -z "${NVM_DIR:-}" ] || ! command -v nvm &> /dev/null; then
    # Standalone mode: Auto-detect NVM location
    if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        # NVM_DIR already set and valid
        \. "$NVM_DIR/nvm.sh"
    elif [ -s "$HOME/.nvm/nvm.sh" ]; then
        # Standard location (macOS/Linux local)
        export NVM_DIR="$HOME/.nvm"
        \. "$NVM_DIR/nvm.sh"
    elif [ -s "/home/master/.nvm/nvm.sh" ]; then
        # Cloudways location
        export NVM_DIR="/home/master/.nvm"
        \. "$NVM_DIR/nvm.sh"
        # Setup Cloudways-specific paths
        export PATH="/home/master/bin:/home/master/bin/npm/lib/node_modules/bin:${PATH}"
        export PM2_HOME="/home/master/.pm2"
    else
        echo "⚠️  Warning: NVM not found, using system Node/NPM"
    fi

    # Use Node version from .nvmrc if present and NVM is loaded
    if [ -f "${APP_ROOT}/.nvmrc" ] && command -v nvm &> /dev/null; then
        NODE_VERSION=$(cat "${APP_ROOT}"/.nvmrc | tr -d '[:space:]')
        nvm use "${NODE_VERSION}" 2>/dev/null || nvm install "${NODE_VERSION}"
    fi
fi

# Ensure PM2_HOME is set (use default if not set by parent or Cloudways detection)
if [ -z "${PM2_HOME:-}" ]; then
    export PM2_HOME="${HOME}/.pm2"
fi

# Detect ecosystem config file
detect_ecosystem_config() {
    if [ -f "${APP_ROOT}/ecosystem.config.cjs" ]; then
        echo "ecosystem.config.cjs"
    elif [ -f "${APP_ROOT}/ecosystem.config.js" ]; then
        echo "ecosystem.config.js"
    else
        echo ""
    fi
}

ECOSYSTEM_CONFIG=$(detect_ecosystem_config)

if [ -z "$ECOSYSTEM_CONFIG" ]; then
    echo "❌ Error: No ecosystem.config file found (looking for .js or .cjs)"
    exit 1
fi

# Get command (default to status if not provided)
COMMAND=${1:-status}

case $COMMAND in
    start)
        echo "▶️  Starting PM2 process..."
        pm2 start ${ECOSYSTEM_CONFIG}
        pm2 save --force
        echo "✅ PM2 process started"
        ;;

    stop)
        echo "⏹️  Stopping PM2 process..."
        pm2 stop ${ECOSYSTEM_CONFIG} || true
        echo "✅ PM2 process stopped"
        ;;

    restart)
        echo "♻️  Restarting PM2 process..."
        if pm2 restart ${ECOSYSTEM_CONFIG}; then
            pm2 save --force
            echo "✅ PM2 process restarted"
        else
            echo "❌ Error: PM2 restart failed"
            exit 1
        fi
        ;;

    delete)
        echo "🗑️  Deleting PM2 process..."
        pm2 delete ${ECOSYSTEM_CONFIG} || true
        pm2 save --force
        echo "✅ PM2 process deleted"
        ;;

    status|list)
        echo "📊 PM2 Status:"
        pm2 list
        echo ""
        echo "💾 Memory & Uptime:"
        pm2 info $(pm2 list | grep 'strapi' | awk '{print $2}' | head -1) | grep -E 'memory|uptime' || true
        ;;

    logs)
        LINES=${2:-50}
        echo "📝 PM2 Logs (last ${LINES} lines):"
        pm2 logs --lines ${LINES} --nostream
        ;;

    *)
        echo "Usage: $0 [start|stop|restart|delete|status|logs]"
        echo ""
        echo "Commands:"
        echo "  start    - Start PM2 process"
        echo "  stop     - Stop PM2 process"
        echo "  restart  - Restart PM2 process"
        echo "  delete   - Delete PM2 process"
        echo "  status   - Show PM2 status (default)"
        echo "  logs     - Show PM2 logs (default: 50 lines)"
        echo ""
        echo "Current config: ${ECOSYSTEM_CONFIG}"
        exit 1
        ;;
esac
