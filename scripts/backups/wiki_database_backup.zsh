#!/usr/bin/env zsh
# Attu Project Wiki - Automatic database backups script
# This file is licensed under the MIT License; See LICENSE for full text.

# wiki config
backup_path="$APP_HOME/backups"
min_backup_size=10000
db_host='database'

current_date=$(date +%Y-%m-%d)
db_backup_file="${backup_path}/attu-wiki-backup_${current_date}.sql.bz2"

# ensure backup directory exists
sudo zsh -c "mkdir -vp $backup_path && chown -c doom:doom $backup_path"

# dump db and compress
mariadb-dump --user=attu --password="$ATTU_DB_PASSWORD" --host="$db_host" --databases attu_wiki --single-transaction --quick \
    | bzip2 > "$db_backup_file"

# verify backup size
backup_size=$(wc -c < "$db_backup_file")
if [ ! "$backup_size" -ge "$min_backup_size" ]; then
    printf '%s\n' "failure: wiki backup too small ($backup_size bytes)"
    exit 1
fi
