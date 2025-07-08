#!/usr/bin/zsh

backup_path='/srv/backups/attu-wiki'

db_backup_file="${backup_path}/attu-wiki-backup_$(date +%Y-%m-%d).sql.gz"
images_backup_file="${backup_path}/attu-images-backup_$(date +%Y-%m-%d).tar.gz"
day_of_week=$(date '+%u')
day_of_month=$(date '+%d')
heartbeat_url='https://uptime.betterstack.com/api/v1/heartbeat/REDACTED'

printf 'Backing up attu wiki database to [%s]\n' "$db_backup_file"

docker exec -i attu-database-1 mariadb-dump --user=attu --password='REDACTED' --lock-tables --databases attu_wiki | gzip > $db_backup_file

if [ "${day_of_week}" -eq 5 ]; then
    printf 'Backing up new attu wiki images to [%s]\n' "$images_backup_file"

    cd '/srv/attu'
    find images -mtime '-7' -type f -exec tar czf $images_backup_file "{}" +
else
    printf 'Skipping Image Backup: %s != 5\n' "${day_of_week}"
fi

if [ "${day_of_month}" -eq 01 ]; then
    prev_datestamp=$(date -d 'yesterday 13:00' '+%Y-%m')
    compact_prefix="attu-wiki-backup_${prev_datestamp}"
    cd $backup_path

    printf 'Compacting backups from previous month to [%s]\n' "$PWD/${compact_prefix}.tar.bz2"

    gunzip -v ${compact_prefix}-*.sql.gz
    tar --remove-files -cjvf "${compact_prefix}.tar.bz2" *.sql
fi

chown attu:attu -Rc $backup_path

# Status

backup_size="$(wc -c < $db_backup_file)"
min_size=10000
if [ "$backup_size" -ge $min_size ]; then
    curl "$heartbeat_url"
else
    curl "${heartbeat_url}/fail"
fi
