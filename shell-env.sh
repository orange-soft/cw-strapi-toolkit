#!/bin/bash
# Script: Shell Environment for manual work on the server
# Description: Sets up the current SSH shell the way the deploy scripts do, so
#   node, npm, npx strapi ... and pm2 work by hand: the app's Node from .nvmrc,
#   the right PM2 (Cloudways: master's shared one; cPanel: the user's own), and
#   a writable HOME / npm cache in public_html.
# Usage (from anywhere; must be sourced, not run):
#   source strapi-toolkit/shell-env.sh               # in the app folder
#   source <app>/strapi-toolkit/shell-env.sh --keep-home
# Options:
#   --keep-home   Don't point HOME at public_html (npm cache still goes there)
# Sourcing it again is harmless. DEPLOY_SERVER_TYPE / MASTER_HOME work as in
# the deploy scripts.

# Refuse to run as a separate process: nothing would stay set in your shell
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "❌ Run this with source, so it can set up your current shell:"
    echo "   source $0"
    exit 1
fi

# Same lookup as deploy/restart-only.sh (atomic design: each script carries its
# own copy), except it returns instead of exiting, which would close your shell
_strapi_resolve_node_env() {
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
            echo "❌ DEPLOY_SERVER_TYPE must be cpanel or cloudways (or unset), got: ${DEPLOY_SERVER_TYPE}"
            return 2
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

    # Real paths: nvm refuses to switch Node through the /home/master symlink
    NVM_DIR="$(cd "${NVM_DIR}" && pwd -P)"
    NODE_HOME="$(cd "${NODE_HOME}" 2>/dev/null && pwd -P || echo "${NODE_HOME}")"

    PM2_HOME="${NODE_HOME}/.pm2"
    export NVM_DIR PM2_HOME NODE_HOME HOSTING HOSTING_SOURCE
}

_strapi_shell_env() {
    local keep_home=false arg
    for arg in "$@"; do
        case "$arg" in
            --keep-home) keep_home=true ;;
            *) echo "❌ Unknown option: $arg (only --keep-home)"; return 1 ;;
        esac
    done

    # The app folder is the one holding this toolkit, wherever you source it from
    local APP_ROOT
    APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ ! -f "${APP_ROOT}/package.json" ]; then
        echo "❌ No package.json in ${APP_ROOT} - source the shell-env.sh inside an app's strapi-toolkit/"
        return 1
    fi

    # A locale the server doesn't have makes nvm's tools print "manpath: can't
    # set the locale"; fall back to C.UTF-8 only when the current one is broken
    if [ -n "$(locale 2>&1 >/dev/null)" ]; then
        export LC_ALL=C.UTF-8
    fi

    _strapi_resolve_node_env
    case $? in
        0) ;;
        2) return 1 ;;  # invalid DEPLOY_SERVER_TYPE, already reported
        *) echo "❌ NVM not found (${HOSTING})"; return 1 ;;
    esac
    # shellcheck disable=SC1091
    \. "${NVM_DIR}/nvm.sh"

    local node_version=""
    if [ -f "${APP_ROOT}/.nvmrc" ]; then
        node_version="$(tr -d '[:space:]' < "${APP_ROOT}/.nvmrc")"
        if ! nvm use "${node_version}" >/dev/null 2>&1; then
            echo "❌ Node ${node_version} (from .nvmrc) is not installed in ${NVM_DIR}"
            echo "   A deploy installs it; to install by hand: nvm install ${node_version}"
            return 1
        fi
    fi
    # Same variable the deploy exports: a manual pm2 start of ecosystem.config.cjs
    # then runs this Node too
    NODE_BIN="$(dirname "$(nvm which current 2>/dev/null || command -v node)")"
    export NODE_BIN

    # Cloudways keeps pm2 in master's ~/bin/npm; on cPanel it lives under the nvm
    # Node. Add each folder once, so sourcing again doesn't grow PATH.
    local p
    for p in "${NODE_HOME}/bin/npm/lib/node_modules/bin" "${NODE_HOME}/bin"; do
        case ":${PATH}:" in
            *":${p}:"*) ;;
            *) [ -d "${p}" ] && PATH="${p}:${PATH}" ;;
        esac
    done
    export PATH

    # npm cache and Strapi's .config in public_html (a Cloudways app user's own
    # home is owned by root). The real home stays in REAL_HOME.
    local public_html
    public_html="$(dirname "${APP_ROOT}")"
    export NPM_CONFIG_CACHE="${public_html}/.npm"
    if [ "${keep_home}" != true ] && [ "${HOME}" != "${public_html}" ]; then
        export REAL_HOME="${REAL_HOME:-$HOME}"
        export HOME="${public_html}"
    fi

    echo "✅ Shell ready for $(basename "${APP_ROOT}") (${HOSTING}, ${HOSTING_SOURCE})"
    echo "   Node:     $(node --version)${node_version:+ (.nvmrc: ${node_version})}, npm $(npm --version)"
    echo "   pm2:      $(command -v pm2 || echo 'not found')"
    echo "   PM2_HOME: ${PM2_HOME}"
    echo "   HOME:     ${HOME}${REAL_HOME:+ (real home: ${REAL_HOME})}"
    if [ "${HOSTING}" = "cloudways" ]; then
        echo "   ⚠️  PM2 and NVM are shared by every app on this server: use"
        echo "      bash strapi-toolkit/pm2/pm2-manager.sh ... for this app, never"
        echo "      pm2 delete all / pm2 kill / npm install -g / nvm alias default"
    fi
}

_strapi_shell_env "$@"
# Keep the status without leaving a variable behind in your shell
set -- "$?"
unset -f _strapi_shell_env _strapi_resolve_node_env
return "$1"
