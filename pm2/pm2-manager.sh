#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Script: PM2 Process Manager
# Description: Manages PM2 operations (start, stop, restart, status)
# Usage: ./pm2-manager.sh [start|stop|restart|status|delete]
# Note: Can be called directly or from other scripts (inherits parent environment)

# Define paths (same as build-and-restart.sh)
MASTER_HOME="/home/master"
APP_ROOT="$(pwd)"

# Only setup environment if not already configured by parent script
# This allows the script to be called standalone or from build-and-restart.sh
if [ -z "${NVM_DIR:-}" ] || ! command -v nvm &> /dev/null; then
    # Standalone mode: Use Cloudways paths (same as build-and-restart.sh)
    export NVM_DIR="${MASTER_HOME}/.nvm"

    if [ -s "$NVM_DIR/nvm.sh" ]; then
        \. "$NVM_DIR/nvm.sh"
    else
        echo "❌ Error: NVM not found at $NVM_DIR/nvm.sh"
        echo "   This script requires Node.js (installed via NVM on Cloudways)"
        exit 1
    fi

    # Use Node version from .nvmrc if present
    if [ -f "${APP_ROOT}/.nvmrc" ]; then
        NODE_VERSION=$(cat "${APP_ROOT}"/.nvmrc | tr -d '[:space:]')
        nvm use "${NODE_VERSION}" 2>/dev/null || nvm install "${NODE_VERSION}"
    fi

    # Setup PM2 environment (same as build-and-restart.sh)
    export PATH="${MASTER_HOME}/bin:${MASTER_HOME}/bin/npm/lib/node_modules/bin:${PATH}"
    export PM2_HOME="${MASTER_HOME}/.pm2"
    export NPM_CONFIG_CACHE="${MASTER_HOME}/.npm"
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

        # Get app name from ecosystem config for verification
        if command -v node &> /dev/null && [ -f "${ECOSYSTEM_CONFIG}" ]; then
            APP_NAME=$(node -p "try { const config = require('./${ECOSYSTEM_CONFIG}'); config.apps?.[0]?.name || '' } catch(e) { '' }" 2>/dev/null)
        fi

        # Try graceful restart first
        if pm2 restart ${ECOSYSTEM_CONFIG} 2>/dev/null; then
            pm2 save --force
            echo "✅ PM2 process restarted"
        else
            # If restart fails (process not found), try delete + start for this app only
            echo "🧹 Process not running, starting fresh..."
            pm2 delete ${ECOSYSTEM_CONFIG} 2>/dev/null || true

            if pm2 start ${ECOSYSTEM_CONFIG}; then
                pm2 save --force

                # Verify app is actually running (not just started and crashed)
                sleep 2
                if [ -n "$APP_NAME" ] && pm2 list | grep -q "$APP_NAME.*online"; then
                    echo "✅ PM2 process started and running"
                else
                    echo "❌ Error: PM2 started but app is not online"
                    echo "   Run 'bash $0 logs' to see error details"
                    exit 1
                fi
            else
                echo "❌ Error: PM2 start command failed"
                exit 1
            fi
        fi
        ;;

    delete)
        echo "🗑️  Deleting PM2 process..."
        pm2 delete ${ECOSYSTEM_CONFIG} || true
        pm2 save --force
        echo "✅ PM2 process deleted"
        ;;

    cleanup)
        echo "⚠️  WARNING: This will delete ALL PM2 processes on this server!"
        echo "   This affects all apps sharing the same PM2 instance."
        echo ""
        read -p "Are you sure you want to continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cleanup cancelled."
            exit 0
        fi

        echo "🧹 Cleaning up PM2 (fixes stale PID errors)..."
        pm2 delete all 2>/dev/null || true
        pm2 cleardump 2>/dev/null || true
        pm2 kill 2>/dev/null || true
        echo "✅ PM2 cleaned up - all processes removed"
        echo "   ⚠️  All PM2 apps on this server were stopped!"
        echo "   Run 'start' or 'restart' in each app directory to restart them"
        ;;

    status|list)
        echo "📊 PM2 Status (all processes on this server):"
        pm2 list
        echo ""

        # Get app name from ecosystem config to show details for current app only
        if command -v node &> /dev/null && [ -f "${ECOSYSTEM_CONFIG}" ]; then
            APP_NAME=$(node -p "try { const config = require('./${ECOSYSTEM_CONFIG}'); config.apps?.[0]?.name || '' } catch(e) { '' }" 2>/dev/null)

            if [ -n "$APP_NAME" ]; then
                echo "💾 Memory & Uptime for '${APP_NAME}' (current app):"
                pm2 info "$APP_NAME" 2>/dev/null | grep -E 'memory|uptime|cpu|status' || echo "   App not running"
            fi
        fi
        ;;

    logs)
        LINES=${2:-50}

        # Get app name from ecosystem config (not from pm2 list, which could match other apps)
        if command -v node &> /dev/null && [ -f "${ECOSYSTEM_CONFIG}" ]; then
            APP_NAME=$(node -p "try { const config = require('./${ECOSYSTEM_CONFIG}'); config.apps?.[0]?.name || '' } catch(e) { '' }" 2>/dev/null)
        fi

        if [ -n "$APP_NAME" ]; then
            echo "📝 PM2 Logs for '${APP_NAME}' (last ${LINES} lines):"
            pm2 logs "$APP_NAME" --lines ${LINES} --nostream
        else
            echo "⚠️  Could not detect app name from ${ECOSYSTEM_CONFIG}"
            echo "   Showing all logs (may include other apps on this server):"
            pm2 logs --lines ${LINES} --nostream
        fi
        ;;

    *)
        echo "Usage: $0 [start|stop|restart|delete|cleanup|status|logs]"
        echo ""
        echo "Commands:"
        echo "  start    - Start PM2 process for current app"
        echo "  stop     - Stop PM2 process for current app"
        echo "  restart  - Restart PM2 process for current app (graceful)"
        echo "  delete   - Delete PM2 process for current app"
        echo "  cleanup  - ⚠️  DANGEROUS: Delete ALL PM2 processes on server (requires confirmation)"
        echo "  status   - Show PM2 status (all processes on server)"
        echo "  logs [N] - Show PM2 logs for current app only (default: 50 lines)"
        echo ""
        echo "Examples:"
        echo "  $0 restart     # Restart current app only"
        echo "  $0 status      # Check all PM2 processes"
        echo "  $0 logs        # Show last 50 lines"
        echo "  $0 logs 100    # Show last 100 lines"
        echo ""
        echo "Current config: ${ECOSYSTEM_CONFIG}"
        exit 1
        ;;
esac
