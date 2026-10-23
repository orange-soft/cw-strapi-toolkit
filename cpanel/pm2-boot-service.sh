#!/bin/bash
# Server-wide PM2 boot recovery for every cPanel user's Strapi site (root).
#
# Replaces the per-user "@reboot pm2 resurrect" cron, which left sites down
# after reboots because:
#   1. many site users never had the cron at all
#   2. the cron only loads ~/.nvm, but pm2 may be installed under /opt/nvm
#      ("pm2: command not found", nothing logged)
#   3. it ran a few seconds after boot, before MySQL accepted connections
#
# This runs once per boot as a systemd service ordered after MySQL. For every
# user with a saved PM2 process list (~/.pm2/dump.pm2, written by 'pm2 save'
# on every deploy) it finds that user's pm2 itself and runs 'pm2 resurrect'
# as that user, then logs each app's status to the journal.
#
# Usage (as root):
#   bash pm2-boot-service.sh install   # install + enable the service, remove old crons
#   bash pm2-boot-service.sh run       # restore every user's PM2 apps now
#   journalctl -u pm2-boot-resurrect   # what happened at the last boot

set -u

INSTALL_PATH="/usr/local/sbin/pm2-boot-resurrect"
UNIT_NAME="pm2-boot-resurrect.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"
CRON_TAG="# pm2-boot-resurrect"
DB_WAIT_SECONDS=180
# Gap between users so a dozen Strapi apps don't all boot at the same moment
STAGGER_SECONDS=5

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: run this as root (sudo bash $0 $*)"
        exit 1
    fi
}

# Prints the Node bin directory holding pm2 for a user: their own NVM first,
# then the shared /opt/nvm, newest Node version first within each
find_pm2_bin() {
    local home="$1" root dir
    for root in "$home/.nvm" "/opt/nvm"; do
        for dir in $(ls -d "$root"/versions/node/*/bin 2>/dev/null | sort -rV); do
            if [ -x "$dir/pm2" ]; then
                echo "$dir"
                return 0
            fi
        done
    done
    return 1
}

# Runs pm2 as the given user with a clean environment
run_pm2() {
    local user="$1" home="$2" bin="$3"
    shift 3
    runuser -u "$user" -- env -i \
        HOME="$home" USER="$user" LOGNAME="$user" \
        PATH="$bin:/usr/local/bin:/usr/bin:/bin" \
        PM2_HOME="$home/.pm2" \
        "$bin/pm2" "$@"
}

# Waits until MySQL answers. mysqladmin ping exits 0 whenever the server is
# up, even if it refuses the login, so no credentials are needed
wait_for_db() {
    local waited=0
    if ! command -v mysqladmin >/dev/null 2>&1; then
        echo "mysqladmin not found, not waiting for MySQL"
        return 0
    fi
    until mysqladmin ping >/dev/null 2>&1; do
        if [ "$waited" -ge "$DB_WAIT_SECONDS" ]; then
            echo "WARNING: MySQL not answering after ${DB_WAIT_SECONDS}s, starting apps anyway"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    echo "MySQL is up (waited ${waited}s)"
}

# Prints "name=status" for each of a user's PM2 apps
app_statuses() {
    local user="$1" home="$2" bin="$3"
    run_pm2 "$user" "$home" "$bin" jlist 2>/dev/null | "$bin/node" -e '
        let s = "";
        process.stdin.on("data", (d) => (s += d)).on("end", () => {
            try {
                // jlist prints the JSON on one line; skip any PM2 notices before it
                const apps = JSON.parse(s.split("\n").filter((l) => l.startsWith("[")).pop());
                console.log(apps.map((a) => `${a.name}=${a.pm2_env.status}`).join(" ") || "(no apps)");
            } catch (e) {
                console.log("(could not read pm2 status)");
            }
        });'
}

restore_all() {
    require_root "run"
    # Start from / as at boot; a user can't always enter the caller's directory
    cd / || exit 1
    wait_for_db

    local user home bin output restored=()
    while IFS=: read -r user home; do
        [ -f "$home/.pm2/dump.pm2" ] || continue
        # Only trust a dump file owned by the account it belongs to
        [ "$(stat -c %U "$home/.pm2/dump.pm2")" = "$user" ] || continue

        if ! bin=$(find_pm2_bin "$home"); then
            echo "[$user] FAILED: pm2 not found under $home/.nvm or /opt/nvm"
            continue
        fi

        # Don't resurrect on top of apps that are already running (e.g. started
        # by hand); that would launch duplicates
        if run_pm2 "$user" "$home" "$bin" jlist 2>/dev/null | grep -q '"pm_id"'; then
            echo "[$user] PM2 already has apps, skipping resurrect"
        elif output=$(run_pm2 "$user" "$home" "$bin" resurrect 2>&1); then
            echo "[$user] resurrected with $bin/pm2"
            sleep "$STAGGER_SECONDS"
        else
            echo "[$user] FAILED: $bin/pm2 resurrect exited with an error:"
            echo "$output" | tail -n 8 | sed "s/^/[$user]   /"
            continue
        fi
        restored+=("$user:$home:$bin")
    done < <(getent passwd | awk -F: '$3 >= 1000 && $6 != "" { print $1 ":" $6 }')

    if [ ${#restored[@]} -eq 0 ]; then
        echo "No users with a saved PM2 process list"
        return 0
    fi

    # Give Strapi time to boot (or burn through its restarts) before reporting
    sleep 60
    local entry
    for entry in "${restored[@]}"; do
        IFS=: read -r user home bin <<< "$entry"
        echo "[$user] $(app_statuses "$user" "$home" "$bin")"
    done
}

install_service() {
    require_root "install"
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "Error: systemd is required"
        exit 1
    fi

    install -m 755 "$0" "$INSTALL_PATH"
    echo "Installed $INSTALL_PATH"

    cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Restore every user's PM2 apps (Strapi sites) after boot
Wants=network-online.target
After=network-online.target mysql.service mysqld.service mariadb.service

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} run
RemainAfterExit=yes
# The PM2 daemons started here must outlive this one-shot unit
KillMode=process
TimeoutStartSec=20min

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$UNIT_NAME"
    echo "Enabled $UNIT_NAME"

    # The old per-user crons would race this service (and start apps before
    # MySQL is up), so remove them. Only lines carrying the tag are touched.
    local user
    for user in $(getent passwd | awk -F: '$3 >= 1000 { print $1 }'); do
        if crontab -u "$user" -l 2>/dev/null | grep -qF "$CRON_TAG"; then
            crontab -u "$user" -l 2>/dev/null | grep -vF "$CRON_TAG" | crontab -u "$user" -
            echo "Removed old @reboot pm2 cron for $user"
        fi
    done

    echo ""
    echo "Done. To bring sites up now without rebooting: sudo $INSTALL_PATH run"
    echo "After a reboot, check: journalctl -u pm2-boot-resurrect -b"
}

case "${1:-}" in
    install) install_service ;;
    run) restore_all ;;
    *)
        echo "Usage: $0 install|run"
        exit 1
        ;;
esac
