# cPanel Utilities

Server setup tools for running Strapi sites on a cPanel/WHM server, one site per cPanel account. Deploys themselves need nothing from this folder: the GitHub Actions workflow and `deploy/restart-only.sh` work the same on cPanel and Cloudways (see the toolkit README, "Supported Servers").

| Script | Run as | Purpose |
|---|---|---|
| `setup-site.sh` | the site's cPanel user | One-time setup of a new site: authorizes the deploy key, creates a GitHub deploy key, installs NVM + the `.nvmrc` Node, clones the repo into `~/public_html/<repo>`, creates `.env` with generated secrets, suggests a free `STRAPI_PORT` |
| `pm2-boot-service.sh` | root, once per server | Installs a systemd service that restores every user's PM2 apps after a reboot (after MySQL is up) |
| `generate-deploy-key.sh` | the site's cPanel user | Optional helper: generates the deploy keypair (`~/.ssh/deploy_<user>`) and prints what to paste where |

On cPanel each site has its own user, its own NVM (`~/.nvm`) and its own PM2 daemon (`~/.pm2`); nothing is shared between sites.

## One-time server setup (root)

Install both tools from this public repo (no local clone needed):

```bash
# setup-strapi-site command for all cPanel users
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/cpanel/setup-site.sh -o /tmp/setup-site.sh
less /tmp/setup-site.sh                       # inspect it
sudo install -m 755 /tmp/setup-site.sh /usr/local/bin/setup-strapi-site
rm /tmp/setup-site.sh

# PM2 boot recovery
curl -fsSL https://raw.githubusercontent.com/orange-soft/cw-strapi-toolkit/master/cpanel/pm2-boot-service.sh -o /tmp/pm2-boot-service.sh
sudo bash /tmp/pm2-boot-service.sh install
rm /tmp/pm2-boot-service.sh
sudo /usr/local/sbin/pm2-boot-resurrect run   # optional: restore all sites now
```

Run the same commands again to update. `pm2-boot-service.sh install` also removes old per-user `@reboot ... # pm2-boot-resurrect` cron lines. After a reboot: `journalctl -u pm2-boot-resurrect -b`.

Any deployed app also carries these scripts in `strapi-toolkit/cpanel/`, so root can install from there instead.

## Setting up a site (cPanel user)

Prerequisites: the cPanel account exists, shell access is enabled (WHM > Manage Shell Access), and the GitHub repo exists. The full step-by-step guide (VirtualHost, SSL, database, R2, GitHub settings) is in the strapi-boilerplate README, "Setting up a new site".

```bash
ssh <cpanel_user>@<server-ip>

# Deploy keypair for GitHub Actions (or: bash generate-deploy-key.sh <cpanel_user>)
ssh-keygen -t ed25519 -C "deploy-<cpanel_user>" -f ~/.ssh/deploy_<cpanel_user>   # no passphrase
cat ~/.ssh/deploy_<cpanel_user>.pub

setup-strapi-site git@github.com:<org>/<repo_name>.git
```

The script prompts for:
1. **The public key** from above (`ssh-ed25519 ...`) — lets GitHub Actions log in as this user
2. **Adding a deploy key** to the GitHub repo (Settings > Deploy keys) — lets the server clone the repo

At the end it prints the values for the GitHub environment named like the deploy branch: `DEPLOY_SSH_HOST`, `DEPLOY_SSH_USER`, `DEPLOY_PATH`, `STRAPI_PORT`, and the `DEPLOY_SSH_PRIVATE_KEY` secret (`cat ~/.ssh/deploy_<cpanel_user>`).

## Troubleshooting

| Problem | Fix |
|---|---|
| `Permission denied (publickey)` while cloning | The repo's deploy key wasn't added: GitHub repo > Settings > Deploy keys, paste the key the script printed |
| `Could not resolve hostname` / GitHub not trusted | `ssh-keyscan github.com >> ~/.ssh/known_hosts` |
| Suggested port in use | `ss -tlnp \| grep <port>` and pick the next free one |
| Site down after a reboot | `systemctl status pm2-boot-resurrect`, `journalctl -u pm2-boot-resurrect -b`; install it as above if missing |

The script refuses to run as root. Private keys never leave the server; secrets are generated with Node's `crypto.randomBytes`.
