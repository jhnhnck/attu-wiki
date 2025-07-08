#!/usr/bin/zsh

# import Secrets
source /srv/services/attu-wiki/scripts/.attu_secrets

# Configuration
backup_path='/srv/backups/attu-wiki'
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${HEARTBEAT_KEY}"
min_backup_size=10000
wiki_path='/srv/services/attu-wiki'

# Logger
log() {
  printf '%s\n' "$1"
}

# Ensure the backup directory exists
mkdir -p "$backup_path" || { log "Failed to create backup directory: $backup_path"; exit 1; }

# Generate filenames with current date
current_date=$(date +%Y-%m-%d)
db_backup_file="${backup_path}/attu-wiki-backup_${current_date}.sql.bz2"
current_month=$(date +%Y-%m)
images_backup_file="${backup_path}/attu-images-backup_${current_month}.tar.bz2"

# Backup the database
log "Backing up attu wiki database to [$db_backup_file]"
docker exec -i attu-database-1 mariadb-dump --user=attu --password="$ATTU_DB_PASSWORD" --lock-tables --databases attu_wiki | bzip2 > "$db_backup_file"

# Check if the database backup succeeded
if [ $? -ne 0 ]; then
  log "Database backup failed!"
  curl -fsS "${heartbeat_url}/fail" > /dev/null
  exit 1
fi

# Run maintenance scripts
log "Cleaning up MediaWiki upload stash"
docker exec -i attu-mediawiki-1 php maintenance/run.php cleanupUploadStash

log "Regenerating sitemap"
docker exec -i attu-mediawiki-1 php maintenance/run.php generateSitemap --fspath=/var/www/html/sitemap/ --identifier=attuproject.org --urlpath=/sitemap/ --compress=no --skip-redirects --server="https://attuproject.org"

# Backup images daily (update the monthly archive with changes)
log "Updating monthly image backup for [$current_month] at [$images_backup_file]"
cd '/srv/services/attu-wiki' || { log "Failed to cd to /srv/services/attu-wiki"; exit 1; }

# Find files modified in the last day and update the archive
find images -mtime -1 -type f -print0 | tar --null -cjf "$images_backup_file" --no-recursion -T - || { log "Failed to update image backup"; exit 1; }

# Compact backups on the first day of the month
day_of_month=$(date '+%d')
if [ "$day_of_month" -eq 1 ]; then
  prev_datestamp=$(date -d 'yesterday 13:00' '+%Y-%m')
  compact_prefix="${backup_path}/attu-wiki-backup_${prev_datestamp}"
  cd "$backup_path" || { log "Failed to cd to $backup_path"; exit 1; }

  log "Compacting backups from previous month to [$compact_prefix.tar.bz2]"

# gunzip -v "${compact_prefix}-"*.sql.gz || { log "Failed to unzip .gz SQL backups"; exit 1; }
  bunzip2 -v "${compact_prefix}-"*.sql.bz2 || { log "Failed to unzip .bz2 SQL backups"; exit 1; }

  tar --remove-files -cjvf "${compact_prefix}.tar.bz2" *.sql || { log "Failed to create compacted archive"; exit 1; }
fi

# Set ownership of backup files
log "Setting ownership of backup files to attu:attu"
chown -Rc jhn:jhn "$backup_path" || { log "Failed to set ownership"; exit 1; }


# Verify backup size and send heartbeat
backup_size=$(wc -c < "$db_backup_file")
if [ "$backup_size" -ge "$min_backup_size" ]; then
  log "Backup succeeded (size: $backup_size bytes). Sending heartbeat."
  curl -fsS "$heartbeat_url" > /dev/null
else
  log "Backup size is too small (size: $backup_size bytes). Sending failure heartbeat."
  curl -fsS "${heartbeat_url}/fail" > /dev/null
  exit 1
fi

log "Backup process completed successfully."

log "Pulling any changes to docker images"
cd "$wiki_path"
docker compose pull
docker compose up -d
