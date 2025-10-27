#!/usr/bin/env zsh
# Attu Project Wiki - Automatic backups script
# This file is licensed under the MIT License; See LICENSE for full text.

# wiki config
current_date=$(date +%Y-%m-%d)
backup_path="$APP_HOME/backups"
images_backup_name="attu-images-backup_${current_date}"

cd "$APP_HOME/mediawiki"
new_files_count="$(find images -daystart -mtime -3 -type f | wc -l)"
# ^ TODO: that could probably do with excluding thumbnails

if [ "new_files_count" -gt 0 ]; then
    tar -cjf "${backup_path}/${images_backup_name}.tar.bz2" images/
fi

