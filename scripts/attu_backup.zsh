#!/usr/bin/env zsh

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

current_date=$(date +%Y-%m-%d)
current_month=$(date +%Y-%m)

# attu wiki config
backup_path='/srv/backups/attu-wiki'
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${BACKUPS_HEARTBEAT_KEY}"
min_backup_size=10000
wiki_path="$PWD"  # /srv/services/attu-wiki-prod
mw_container='mediawiki'
db_container='database'

# doom-bot config
bot_backup_path='/srv/backups/attu-bot'
bot_path='/srv/services/doom-bot'
bot_database_path='assets/markers.db'
bot_container='core'

mkdir -p "$backup_path" "$bot_backup_path"  # sanity check

# TODO: any way to store a diff of this?
printf '%s\n' "backup: attu wiki database"
db_backup_file="${backup_path}/attu-wiki-backup_${current_date}.sql.bz2"

docker compose -f "$wiki_path/docker-compose.yml" \
    exec "$db_container" mariadb-dump --user=attu --password="$ATTU_DB_PASSWORD" --lock-tables --databases attu_wiki \
    | bzip2 >"$db_backup_file"

printf '%s\n' "chore: ${mw_container} maintenance tasks"
docker compose -f "$wiki_path/docker-compose.yml" \
    exec "$mw_container" php maintenance/run.php cleanupUploadStash

printf '%s\n' "backup: attu images"
images_backup_file="${backup_path}/attu-images-backup_${current_month}.tar.bz2"

cd "$wiki_path"
find images -mtime -1 -type f -print0 | tar --null -cjf "$images_backup_file" --no-recursion -T -

if [[ $(date +%u) -eq 6 ]]; then
    printf '%s\n' "backup: doom-bot database"
    sqlite_backup_file="$bot_backup_path/markers-$(date +%Y-%-m-%-d).sql"
    docker compose -f "$bot_path/docker-compose.yml" \
        exec "$bot_container" sqlite3 "$bot_database_path" .dump \
        > "$sqlite_backup_file"
fi

# compact backups (monthly)
if [ "$(date '+%d')" -eq 1 ]; then
    printf '%s\n' "bundle: attu wiki database backups"

    prev_datestamp=$(date -d 'yesterday 13:00' '+%Y-%m')
    compact_prefix="${backup_path}/attu-wiki-backup_${prev_datestamp}"
    cd "$backup_path"

    bunzip2 -v "${compact_prefix}-"*.sql.bz2
    tar --remove-files -cjvf "${compact_prefix}.tar.bz2" *.sql
fi

# TODO: give this its own timer
echo "/usr/bin/zsh ${wiki_path}/scripts/attu_updates.zsh" | at now +2 hours

# verify backup size and send heartbeat
backup_size=$(wc -c <"$db_backup_file")
if [ "$backup_size" -ge "$min_backup_size" ]; then
    curl -fsS "$heartbeat_url" >/dev/null
else
    printf '%s\n' "failure: wiki backup too small ($backup_size bytes)"
    exit 1
fi
