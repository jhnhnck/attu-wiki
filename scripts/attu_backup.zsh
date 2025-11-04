#!/usr/bin/env zsh
# Attu Project Wiki - What's left of the system backups script, currently only for jhnhnck/attu-bot
# This file is licensed under the MIT License; See LICENSE for full text.

# I can't seem to stop systend from running this at boot
boot_secs=$(printf '%.0f\n' "$(cut -d' ' -f1 </proc/uptime)")
if [ "$boot_secs" -lt 300 ]; then
    printf '%s\n' "Script caught running ${boot_secs}s after boot; exiting"
    exit 0
fi

SCRIPT_SOURCE=${0%/*}
cd $SCRIPT_SOURCE/..
source .env

exit_trap() {
    printf '%s\n' "caught error; sending fail hook"
    curl -fsS "${heartbeat_url}/fail" >/dev/null
    exit 1
}

trap 'exit_trap' ZERR
set -eu

current_date="$(date +%Y-%-m-%-d)"

# doom-bot config
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${TASKS_HEARTBEAT_KEY}"
bot_backup_path='/srv/backups/attu-bot'
bot_path='/srv/services/doom-bot'
bot_database_path='assets/markers.db'
bot_container='core'

mkdir -p "$bot_backup_path"

# keep doom bot backup here for now, but probably should be in its repo not here
if [[ $(date +%u) -eq 6 ]]; then
    printf '%s\n' "backup: doom-bot database"
    sqlite_backup_file="${bot_backup_path}/markers-${current_date}.sql"

    docker compose -f "$bot_path/docker-compose.yml" \
        exec "$bot_container" sqlite3 "$bot_database_path" .dump \
        > "$sqlite_backup_file"
fi
