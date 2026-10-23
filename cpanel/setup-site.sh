#!/bin/bash
# ============================================
# New Site Setup (run as the cPanel user)
# ============================================
# Prerequisites (done once in WHM by admin):
#   1. Create cPanel account
#   2. Enable shell access: WHM > Account Functions > Manage Shell Access
#
# Usage: SSH into the server as the cPanel user, then run:
#   bash setup-site.sh <git_repo_url>
#
# Example:
#   bash setup-site.sh git@github.com:orange-soft/calvary-church-strapi.git

set -e

GIT_REPO="$1"

if [ -z "$GIT_REPO" ]; then
    echo "Usage: bash $0 <git_repo_url>"
    echo "Example: bash $0 git@github.com:orange-soft/calvary-church-strapi.git"
    exit 1
fi

# Must NOT be run as root
if [ "$(id -u)" -eq 0 ]; then
    echo "Error: Do not run this script as root or with sudo."
    echo "SSH into the server as the cPanel user and run it directly."
    exit 1
fi

CPANEL_USER="$(whoami)"
CPANEL_HOME="$HOME"
PUBLIC_HTML="$CPANEL_HOME/public_html"
SSH_DIR="$CPANEL_HOME/.ssh"
NVM_DIR="$CPANEL_HOME/.nvm"

# Extract repo name from URL (e.g., calvary-church-strapi from .../calvary-church-strapi.git)
REPO_NAME=$(basename "$GIT_REPO" .git)
APP_DIR="$PUBLIC_HTML/$REPO_NAME"
GITHUB_HOST_ALIAS="github.com-${REPO_NAME}"
GIT_REPO_ALIASED=$(echo "$GIT_REPO" | sed "s|github.com|${GITHUB_HOST_ALIAS}|")

echo "============================================"
echo "Setting up new site"
echo "============================================"
echo "  User:       $CPANEL_USER"
echo "  Repository: $GIT_REPO"
echo "  App folder: $APP_DIR"
echo ""

# ---- Step 1: Setup SSH keys ----
echo "[1/5] Setting up SSH keys..."

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# authorized_keys: allow GitHub Actions to SSH in as this user
# The public key here must match the DEPLOY_SSH_PRIVATE_KEY secret in GitHub
AUTH_KEYS="$SSH_DIR/authorized_keys"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

echo ""
echo "  GitHub Actions needs to SSH into this account to deploy."
echo "  Paste the PUBLIC KEY that corresponds to your DEPLOY_SSH_PRIVATE_KEY GitHub secret."
echo "  (It's a single line starting with ssh-ed25519 or ssh-rsa)"
echo ""
read -rp "  Paste public key: " PASTED_KEY

if [ -z "$PASTED_KEY" ]; then
    echo "  Warning: No key entered. Add it manually later:"
    echo "    echo '<public-key>' >> $AUTH_KEYS"
else
    if grep -qF "$PASTED_KEY" "$AUTH_KEYS" 2>/dev/null; then
        echo "  authorized_keys: key already present"
    else
        echo "$PASTED_KEY" >> "$AUTH_KEYS"
        echo "  authorized_keys: key added"
    fi
fi

# Generate a unique deploy key for this repo (server → GitHub for git clone/pull)
DEPLOY_KEY_PATH="$SSH_DIR/deploy_${REPO_NAME}"

if [ -f "$DEPLOY_KEY_PATH" ]; then
    echo "  Deploy key already exists: $DEPLOY_KEY_PATH"
else
    ssh-keygen -t ed25519 -f "$DEPLOY_KEY_PATH" -N "" -C "${CPANEL_USER}@${REPO_NAME}" >/dev/null 2>&1
    echo "  Deploy key generated: $DEPLOY_KEY_PATH"
fi

# Configure SSH host alias so git uses the correct deploy key per repo
SSH_CONFIG="$SSH_DIR/config"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if ! grep -q "Host $GITHUB_HOST_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" <<SSHEOF

# Deploy key for $REPO_NAME
Host $GITHUB_HOST_ALIAS
    HostName github.com
    User git
    IdentityFile $DEPLOY_KEY_PATH
    IdentitiesOnly yes
SSHEOF
    echo "  SSH config: added entry for $GITHUB_HOST_ALIAS"
else
    echo "  SSH config: entry for $GITHUB_HOST_ALIAS already exists"
fi

# Add GitHub to known_hosts
ssh-keyscan github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
chmod 644 "$SSH_DIR/known_hosts"
echo "  known_hosts: github.com added"

echo ""
echo "  ============================================"
echo "  DEPLOY KEY (add this to GitHub as a deploy key):"
echo "  Repo: $GIT_REPO"
echo "  Go to: Settings > Deploy keys > Add deploy key"
echo "  ============================================"
echo ""
cat "${DEPLOY_KEY_PATH}.pub"
echo ""
echo "  ============================================"
echo ""

read -rp "  Press Enter after you've added the deploy key to GitHub..."

# ---- Step 2: Install per-user NVM ----
echo ""
echo "[2/5] Setting up NVM..."

if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "  NVM already installed at $NVM_DIR"
else
    echo "  Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    echo "  NVM installed at $NVM_DIR"
fi

# Load NVM for the rest of this script
export NVM_DIR="$NVM_DIR"
\. "$NVM_DIR/nvm.sh"

# ---- Step 3: Clone repository ----
echo ""
echo "[3/5] Cloning repository..."

if [ -d "$APP_DIR" ]; then
    echo "  Directory $APP_DIR already exists, skipping clone"
else
    git clone "$GIT_REPO_ALIASED" "$APP_DIR"
    echo "  Cloned to $APP_DIR"
fi

# Install Node version from .nvmrc (available now that repo is cloned)
if [ -f "$APP_DIR/.nvmrc" ]; then
    NODE_VERSION_NEEDED=$(cat "$APP_DIR/.nvmrc" | tr -d '[:space:]')
    echo "  Installing Node $NODE_VERSION_NEEDED from .nvmrc..."
    nvm install "$NODE_VERSION_NEEDED"
    nvm use "$NODE_VERSION_NEEDED"
    echo "  Node $(node --version) ready"
fi
echo ""

# ---- Step 4: Setup .env ----
echo "[4/5] Setting up .env..."

if [ -f "$APP_DIR/.env" ]; then
    echo "  .env already exists, skipping"
elif [ -f "$APP_DIR/.env.example" ]; then
    cp "$APP_DIR/.env.example" "$APP_DIR/.env"
    chmod 644 "$APP_DIR/.env"
    echo "  Created .env from .env.example"

    # Generate secrets using Node.js (already loaded via NVM above)
    if command -v node &>/dev/null; then
        echo "  Generating APP_KEYS and secrets..."
        GEN_KEY="node -e \"console.log(require('crypto').randomBytes(32).toString('base64'))\""

        APP_KEY_1=$(eval $GEN_KEY)
        APP_KEY_2=$(eval $GEN_KEY)
        API_TOKEN_SALT=$(eval $GEN_KEY)
        ADMIN_JWT_SECRET=$(eval $GEN_KEY)
        TRANSFER_TOKEN_SALT=$(eval $GEN_KEY)
        JWT_SECRET=$(eval $GEN_KEY)
        ENCRYPTION_KEY=$(eval $GEN_KEY)
        ADMIN_ENCRYPTION_KEY=$(eval $GEN_KEY)

        sed -i "s|^APP_KEYS=.*|APP_KEYS=\"${APP_KEY_1},${APP_KEY_2}\"|" "$APP_DIR/.env"
        sed -i "s|^API_TOKEN_SALT=.*|API_TOKEN_SALT=${API_TOKEN_SALT}|" "$APP_DIR/.env"
        sed -i "s|^ADMIN_JWT_SECRET=.*|ADMIN_JWT_SECRET=${ADMIN_JWT_SECRET}|" "$APP_DIR/.env"
        sed -i "s|^TRANSFER_TOKEN_SALT=.*|TRANSFER_TOKEN_SALT=${TRANSFER_TOKEN_SALT}|" "$APP_DIR/.env"
        sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" "$APP_DIR/.env"

        grep -q "^ENCRYPTION_KEY=" "$APP_DIR/.env" && \
            sed -i "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=${ENCRYPTION_KEY}|" "$APP_DIR/.env" || \
            echo "ENCRYPTION_KEY=${ENCRYPTION_KEY}" >> "$APP_DIR/.env"
        grep -q "^ADMIN_ENCRYPTION_KEY=" "$APP_DIR/.env" && \
            sed -i "s|^ADMIN_ENCRYPTION_KEY=.*|ADMIN_ENCRYPTION_KEY=${ADMIN_ENCRYPTION_KEY}|" "$APP_DIR/.env" || \
            echo "ADMIN_ENCRYPTION_KEY=${ADMIN_ENCRYPTION_KEY}" >> "$APP_DIR/.env"

        echo "  Secrets generated and written to .env"
    else
        echo "  Warning: Node.js not found, skipping key generation"
        echo "  Run manually: bash $APP_DIR/strapi-toolkit/setup/setup-env-keys.sh"
    fi

    echo "  >>> IMPORTANT: Edit $APP_DIR/.env with your database and R2 credentials <<<"
else
    echo "  Warning: No .env.example found"
fi
echo ""

# ---- Step 5: PM2 boot persistence ----
echo "[5/5] Checking PM2 boot persistence..."

# After a reboot, the server-wide pm2-boot-resurrect service (installed once
# by root from strapi-toolkit/cpanel/pm2-boot-service.sh) restores every user's PM2 apps
# from ~/.pm2/dump.pm2, which 'pm2 save' writes on every deploy. Nothing to
# set up per user; just warn if the service is missing.
if systemctl is-enabled pm2-boot-resurrect.service >/dev/null 2>&1; then
    echo "  Boot service installed: PM2 apps will auto-restore after server reboots"
else
    echo "  WARNING: the pm2-boot-resurrect service is not installed on this server,"
    echo "  so this site will NOT come back after a reboot. Ask root to install it"
    echo "  with: sudo bash strapi-toolkit/cpanel/pm2-boot-service.sh install (see strapi-toolkit/cpanel/README.md)"
fi
echo ""

# ---- Port detection ----
# Use ss to list all listening TCP ports server-wide (available without sudo)
LISTENING_PORTS=()
while IFS= read -r port; do
    [ -n "$port" ] && LISTENING_PORTS+=("$port")
done < <(ss -tlnp 2>/dev/null | awk '/LISTEN/ {print $4}' | grep -oE ':[0-9]+$' | tr -d ':' | sort -un || true)

# Find next available port starting from 1337
NEXT_PORT=1337
for port in "${LISTENING_PORTS[@]}"; do
    if [ "$port" -eq "$NEXT_PORT" ]; then
        NEXT_PORT=$((NEXT_PORT + 1))
    fi
done

echo "============================================"
echo "Setup complete!"
echo "============================================"
echo ""
echo "Ports currently in use on this server (1337+):"
FOUND=0
for port in "${LISTENING_PORTS[@]}"; do
    if [ "$port" -ge 1337 ]; then
        echo "  $port"
        FOUND=1
    fi
done
[ "$FOUND" -eq 0 ] && echo "  none"
echo ""
echo "Next steps:"
echo "  1. Edit .env with your database and R2 credentials:"
echo "     nano $APP_DIR/.env"
echo ""
echo "  2. In the GitHub repo, go to: Settings > Environments > New environment"
echo "     Name it EXACTLY like the deploy branch (the site's domain, e.g. calvary.cms.my)"
echo ""
echo "     Environment variables:"
echo "     - DEPLOY_SSH_HOST: $(hostname -I 2>/dev/null | awk '{print $1}' || echo '<server-ip>')"
echo "     - DEPLOY_SSH_USER: $CPANEL_USER"
echo "     - DEPLOY_PATH:     $APP_DIR"
echo "     - STRAPI_PORT:     $NEXT_PORT  ← next available port"
echo ""
echo "     Environment secrets:"
echo "     - DEPLOY_SSH_PRIVATE_KEY: the private key matching the public key you pasted above"
echo "                               (view it with: cat ~/.ssh/deploy_${CPANEL_USER})"
echo ""
echo "  3. Push to the deploy branch (same name as the environment) to trigger the first deploy"
echo ""
