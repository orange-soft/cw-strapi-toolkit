#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Script: PM2 Process Manager
# Description: Manages PM2 operations (start, stop, restart, status)
# Usage: ./pm2-manager.sh [start|stop|restart|status|delete]
# Note: Can be called directly or from other scripts (inherits parent environment)

# Define paths (same as build-and-restart.sh)
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

# Only setup environment if not already configured by parent script
# This allows the script to be called standalone or from build-and-restart.sh
if [ -z "${NVM_DIR:-}" ] || ! command -v nvm &> /dev/null; then
    # Standalone mode: same nvm/PM2 lookup as build-and-restart.sh
    if resolve_node_env; then
        \. "$NVM_DIR/nvm.sh"
    else
        echo "❌ Error: NVM not found (${HOSTING})"
        echo "   This script requires Node.js installed via NVM"
        exit 1
    fi

    # Use Node version from .nvmrc if present ("22" uses the newest installed 22.x)
    if [ -f "${APP_ROOT}/.nvmrc" ]; then
        NODE_VERSION=$(cat "${APP_ROOT}"/.nvmrc | tr -d '[:space:]')
        nvm use "${NODE_VERSION}" >/dev/null 2>&1 || nvm install "${NODE_VERSION}"
    fi

    # Resolve before PATH is extended below, so NODE_BIN is the nvm Node.
    # Keep NODE_BIN if the parent deploy script already resolved it.
    if [ -z "${NODE_BIN:-}" ]; then
        NODE_BIN="$(dirname "$(nvm which current 2>/dev/null || command -v node)")"
    fi

    # Setup PM2 environment (same as build-and-restart.sh; PM2_HOME set by resolve_node_env)
    export PATH="${NODE_HOME}/bin:${NODE_HOME}/bin/npm/lib/node_modules/bin:${PATH}"

    # Use per-app npm cache (set to parent of current directory = public_html)
    export NPM_CONFIG_CACHE="$(dirname "$(pwd)")/.npm"
fi

# Version of the PM2 daemon already running for this PM2_HOME, from its process
# title ("PM2 v6.0.8: God Daemon (/home/master/.pm2)"); empty when none runs.
# Compares real paths, since the daemon may have been started via a symlink
pm2_daemon_version() {
    local want version home
    want="$(cd "${PM2_HOME:-$HOME/.pm2}" 2>/dev/null && pwd -P)" || return 0
    ps -eo args 2>/dev/null \
        | sed -n 's/^PM2 v\([0-9][0-9.]*\): God Daemon (\(.*\))$/\1 \2/p' \
        | while read -r version home; do
            if [ "$(cd "${home}" 2>/dev/null && pwd -P)" = "${want}" ]; then
                echo "${version}"
                break
            fi
        done
}

# NVM keeps global npm packages per Node version, so pm2 is missing right
# after .nvmrc moves to a new version. Install it into the active Node, at the
# running daemon's version: a newer CLI than the daemon prints "In-memory PM2 is
# out-of-date" on every command (move the daemon later with `pm2 update`).
if ! command -v pm2 &> /dev/null; then
    PM2_VERSION="$(pm2_daemon_version)"
    echo "📦 pm2 not found for Node $(node --version), installing pm2@${PM2_VERSION:-latest}..."
    if ! npm install -g "pm2@${PM2_VERSION:-latest}"; then
        echo "❌ Error: Failed to install pm2"
        exit 1
    fi
fi

# ecosystem.config.cjs reads process.env.NODE_BIN to pick interpreter + npm,
# so it must be exported before any `pm2 start/restart <ecosystem>`
export NODE_BIN="${NODE_BIN:-$(dirname "$(command -v node)")}"

# Parse `pm2 jlist` output. The JSON is one line, but pm2 can print other lines
# first (e.g. "In-memory PM2 is out-of-date" with ANSI colours), so take the last
# line that parses as a JSON array instead of searching for the first "["
PM2_JLIST_PARSE_JS='s => { for (const l of s.split("\n").reverse()) { const t = l.trim(); if (t.startsWith("[")) { try { return JSON.parse(t); } catch (e) {} } } return []; }'

# Extract the nvm Node version (e.g. v22.23.4) from a path like
# /home/master/.nvm/versions/node/v22.23.4/bin/node; prints nothing for non-nvm paths
NODE_VERSION_FROM_PATH_JS='p => (String(p || "").match(/\/versions\/node\/(v[^\/]+)\//) || [])[1] || ""'

# Node version the ecosystem config resolves to (falls back to NODE_BIN when the
# config has no nvm interpreter path)
configured_node_version() {
    local version
    version=$(node -e "
        const v = ${NODE_VERSION_FROM_PATH_JS};
        try { console.log(v((require(process.argv[1]).apps?.[0] || {}).interpreter)); } catch (e) {}
    " "${APP_ROOT}/${ECOSYSTEM_CONFIG}" 2>/dev/null || true)
    if [ -z "$version" ]; then
        version=$(node -e "console.log((${NODE_VERSION_FROM_PATH_JS})(process.argv[1] + '/'))" "${NODE_BIN}" 2>/dev/null || true)
    fi
    echo "$version"
}

# Node versions the running PM2 process for this app actually references.
# PM2 stores the interpreter and the resolved npm script path (pm_exec_path) from
# the first start; `pm2 restart` updates the interpreter but keeps the old npm path.
# Matches by exact app name only, so other apps on the shared PM2 are never touched.
running_node_versions() {
    pm2 jlist 2>/dev/null | node -e "
        const v = ${NODE_VERSION_FROM_PATH_JS};
        let s = '';
        process.stdin.on('data', d => s += d).on('end', () => {
            const list = (${PM2_JLIST_PARSE_JS})(s);
            const p = list.find(x => x.name === process.argv[1]);
            const env = (p && p.pm2_env) || {};
            for (const path of [env.exec_interpreter, env.pm_exec_path]) {
                if (v(path)) console.log(v(path));
            }
        });
    " "$1" 2>/dev/null | sort -u || true
}

# Succeeds when the running process references a different Node than configured,
# i.e. a plain restart would leave it on (part of) the old Node
needs_recreate() {
    local app_name="$1" configured running version
    [ -n "$app_name" ] || return 1
    configured=$(configured_node_version)
    [ -n "$configured" ] || return 1
    running=$(running_node_versions "$app_name")

    for version in $running; do
        if [ "$version" != "$configured" ]; then
            echo "🔄 '${app_name}' is running on Node ${version}, config resolves to ${configured}"
            return 0
        fi
    done
    return 1
}

# Warn when the ecosystem config pins a Node version that differs from .nvmrc,
# which means runtime and build use different Node versions
warn_pinned_node_version() {
    local configured expected
    configured=$(configured_node_version)
    expected=$(node -e "console.log((${NODE_VERSION_FROM_PATH_JS})(process.argv[1] + '/'))" "${NODE_BIN}" 2>/dev/null || true)
    if [ -n "$configured" ] && [ -n "$expected" ] && [ "$configured" != "$expected" ]; then
        echo "⚠️  Warning: ${ECOSYSTEM_CONFIG} runs Node ${configured}, but .nvmrc resolved ${expected}"
        echo "   Remove the hardcoded NODE_VERSION and use process.env.NODE_BIN in ${ECOSYSTEM_CONFIG}"
    fi
}

# Get app name from ecosystem config (never from pm2 list, which could match other apps)
get_app_name() {
    node -p "try { const config = require('./${ECOSYSTEM_CONFIG}'); config.apps?.[0]?.name || '' } catch(e) { '' }" 2>/dev/null || true
}

# Verify app is actually running (not just started and crashed)
verify_online() {
    local app_name="$1" action="$2"
    sleep 2
    if [ -n "$app_name" ] && pm2 list | grep -q "$app_name.*online"; then
        echo "✅ PM2 process ${action} and running"
    else
        echo "❌ Error: PM2 ${action} but app is not online"
        echo "   Run 'bash $0 logs' to see error details"
        exit 1
    fi
}

# delete + start for this app only, so PM2 re-resolves interpreter and script paths
recreate_app() {
    local app_name="$1"
    pm2 delete ${ECOSYSTEM_CONFIG} 2>/dev/null || true

    if pm2 start ${ECOSYSTEM_CONFIG}; then
        pm2 save --force
        verify_online "$app_name" "started"
    else
        echo "❌ Error: PM2 start command failed"
        exit 1
    fi
}

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

# Get command (default to status if not provided)
COMMAND=${1:-status}

# node-versions is a server-wide audit and doesn't need an app config
if [ -z "$ECOSYSTEM_CONFIG" ] && [ "$COMMAND" != "node-versions" ]; then
    echo "❌ Error: No ecosystem.config file found (looking for .js or .cjs)"
    exit 1
fi

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

        APP_NAME=$(get_app_name)
        warn_pinned_node_version

        if needs_recreate "$APP_NAME"; then
            # Node changed: a plain restart would keep the old npm path, so recreate
            echo "🧹 Recreating process so PM2 picks up the new Node paths..."
            recreate_app "$APP_NAME"
        elif pm2 restart ${ECOSYSTEM_CONFIG} 2>/dev/null; then
            # Graceful restart
            pm2 save --force
            verify_online "$APP_NAME" "restarted"
        else
            # If restart fails (process not found), try delete + start for this app only
            echo "🧹 Process not running, starting fresh..."
            recreate_app "$APP_NAME"
        fi
        ;;

    recreate)
        echo "🧹 Recreating PM2 process (delete + start, current app only)..."
        APP_NAME=$(get_app_name)
        warn_pinned_node_version
        recreate_app "$APP_NAME"
        ;;

    node-versions)
        # Read-only audit across the shared PM2: which Node each process runs on,
        # and which nvm versions are no longer referenced (safe to `nvm uninstall`)
        echo "🔍 Node versions used by PM2 processes (all apps on this server):"
        PM2_JSON=$(pm2 jlist 2>/dev/null || echo '[]')
        INSTALLED=$(ls "${NVM_DIR}/versions/node" 2>/dev/null || true)
        printf '%s' "$PM2_JSON" | node -e "
            const v = ${NODE_VERSION_FROM_PATH_JS};
            const installed = process.argv[1].split(/\s+/).filter(Boolean);
            let s = '';
            process.stdin.on('data', d => s += d).on('end', () => {
                const list = (${PM2_JLIST_PARSE_JS})(s);
                const used = new Set();
                const pad = (x, n) => String(x).padEnd(n);
                console.log('   ' + pad('APP', 32) + pad('STATUS', 10) + pad('INTERPRETER', 14) + 'NPM SCRIPT');
                for (const p of list) {
                    const env = p.pm2_env || {};
                    const interp = v(env.exec_interpreter) || env.exec_interpreter || '-';
                    const script = v(env.pm_exec_path) || '-';
                    [v(env.exec_interpreter), v(env.pm_exec_path)].filter(Boolean).forEach(x => used.add(x));
                    const iv = v(env.exec_interpreter);
                    const flag = iv && script !== '-' && iv !== script ? '  ⚠️  stale npm path (run: recreate)' : '';
                    console.log('   ' + pad(p.name, 32) + pad(env.status || '?', 10) + pad(interp, 14) + script + flag);
                }
                console.log('');
                console.log('📦 Installed nvm versions:');
                for (const ver of installed) {
                    console.log('   ' + pad(ver, 14) + (used.has(ver) ? 'in use' : 'unused by PM2 (safe to uninstall)'));
                }
            });
        " "$INSTALLED"
        echo ""
        echo "ℹ️  Daemon: $(pm2 -v 2>/dev/null || echo '?') — run 'pm2 update' after upgrading Node so the daemon moves too"
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
        echo "Usage: $0 [start|stop|restart|recreate|delete|cleanup|status|logs|node-versions]"
        echo ""
        echo "Commands:"
        echo "  start    - Start PM2 process for current app"
        echo "  stop     - Stop PM2 process for current app"
        echo "  restart  - Restart PM2 process for current app (graceful; recreates if Node changed)"
        echo "  recreate - Delete + start current app (re-resolves Node/npm paths)"
        echo "  delete   - Delete PM2 process for current app"
        echo "  node-versions - Show Node version per PM2 process and unused nvm versions (read-only)"
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
