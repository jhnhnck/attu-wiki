#!/usr/bin/env zsh

# Import Secrets
SCRIPT_SOURCE=${0%/*}
cd $SCRIPT_SOURCE/..
source .env

# Configuration
backup_path='/srv/backups/attu-wiki'
bot_backup_path='/srv/backups/attu-bot'
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${BACKUPS_HEARTBEAT_KEY}"
min_backup_size=10000
wiki_path="$PWD"
mw_container='mediawiki'
db_container='database'

# Exit Trap
exit_trap() {
    printf '%s\n' "caught error; sending fail hook"
    curl -fsS "${heartbeat_url}/fail" >/dev/null
    exit 1
}

trap 'exit_trap' ZERR

boot_secs=$(printf '%.0f\n' "$(cut -d' ' -f1 </proc/uptime)")
if [ "$boot_secs" -lt 300 ]; then
    printf '%s\n' "Script caught running ${boot_secs}s after boot; exiting"
    exit 0
fi

# set -eux

echo "/usr/bin/zsh ${wiki_path}/scripts/attu_updates.zsh" | at now +8 hours

# Ensure the backup directory exists
mkdir -p "$backup_path" || {
    printf '%s\n' "Failed to create backup directory: $backup_path"
    exit 1
}
mkdir -p "$bot_backup_path" || {
    printf '%s\n' "Failed to create backup directory: $backup_path"
    exit 1
}

# Generate filenames with current date
current_date=$(date +%Y-%m-%d)
db_backup_file="${backup_path}/attu-wiki-backup_${current_date}.sql.bz2"
current_month=$(date +%Y-%m)
images_backup_file="${backup_path}/attu-images-backup_${current_month}.tar.bz2"

# Backup the database
printf '%s\n' "Backing up attu wiki database to [$db_backup_file]"
docker compose -f "$wiki_path/docker-compose.yml" exec "$db_container" mariadb-dump --user=attu --password="$ATTU_DB_PASSWORD" --lock-tables --databases attu_wiki | bzip2 >"$db_backup_file"

# Check if the database backup succeeded
if [ $? -ne 0 ]; then
    printf '%s\n' "Database backup failed!"
    curl -fsS "${heartbeat_url}/fail" >/dev/null
    exit 1
fi

# Run maintenance scripts
printf '%s\n' "Cleaning up MediaWiki upload stash"
docker compose -f "$wiki_path/docker-compose.yml" exec "$mw_container" php maintenance/run.php cleanupUploadStash

# Backup images daily (update the monthly archive with changes)
printf '%s\n' "Updating monthly image backup for [$current_month] at [$images_backup_file]"
cd "$wiki_path" || {
    printf '%s\n' "Failed to cd to $wiki_path"
    exit 1
}

# Find files modified in the last day and update the archive
find images -mtime -1 -type f -print0 | tar --null -cjf "$images_backup_file" --no-recursion -T - || {
    printf '%s\n' "Failed to update image backup"
    exit 1
}

# Weekly SQLite backup for attu-bot (runs only on Saturdays)
if [[ $(date +%u) -eq 6 ]]; then
    printf '%s\n' "Performing weekly SQLite backup for doom-bot"
    sqlite_backup_file="$bot_backup_path/markers-$(date +%Y-%-m-%-d).sql"
    sqlite3 /srv/services/doom-bot/markers.db .dump >"$sqlite_backup_file" || {
        printf '%s\n' "SQLite backup failed"
        exit 1
    }

    if [[ -s "$sqlite_backup_file" ]]; then
        printf '%s\n' "SQLite backup succeeded (size: $(stat -c%s "$sqlite_backup_file") bytes)"
    else
        printf '%s\n' "SQLite backup failed: file is empty"
        exit 1
    fi
    chown jhn:jhn "$sqlite_backup_file" || {
        printf '%s\n' "Failed to set ownership for $sqlite_backup_file"
        exit 1
    }
fi

# Compact backups on the first day of the month
day_of_month=$(date '+%d')

if [ "$day_of_month" -eq 1 ]; then
    prev_datestamp=$(date -d 'yesterday 13:00' '+%Y-%m')
    compact_prefix="${backup_path}/attu-wiki-backup_${prev_datestamp}"
    cd "$backup_path" || {
        printf '%s\n' "Failed to cd to $backup_path"
        exit 1
    }

    printf '%s\n' "Compacting backups from previous month to [$compact_prefix.tar.bz2]"

    bunzip2 -v "${compact_prefix}-"*.sql.bz2 || {
        printf '%s\n' "Failed to unzip .bz2 SQL backups"
        exit 1
    }

    tar --remove-files -cjvf "${compact_prefix}.tar.bz2" *.sql || {
        printf '%s\n' "Failed to create compacted archive"
        exit 1
    }
fi

# # Set ownership of backup files
# printf '%s\n' "Setting ownership of backup files to jhn:jhn"
# chown -Rc jhn:jhn "$backup_path" || {
#     printf '%s\n' "Failed to set ownership"
#     exit 1
# }

# Verify backup size and send heartbeat
backup_size=$(wc -c <"$db_backup_file")
if [ "$backup_size" -ge "$min_backup_size" ]; then
    printf '%s\n' "Backup succeeded (size: $backup_size bytes). Sending heartbeat."
    curl -fsS "$heartbeat_url" >/dev/null
else
    printf '%s\n' "Backup size is too small (size: $backup_size bytes). Sending failure heartbeat."
    curl -fsS "${heartbeat_url}/fail" >/dev/null
    exit 1
fi
