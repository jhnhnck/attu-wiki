#!/usr/bin/env zsh
# Attu Project Wiki - Automatic backups script
# This file is licensed under the MIT License; See LICENSE for full text.

# wiki config
current_date=$(date +%Y-%m-%d)
backup_path="$APP_HOME/backups"
images_backup_name="attu-images-backup_${current_date}"

cd "$APP_HOME/mediawiki"

# make sure everything is readable by us
sudo chown www-data:www-data -Rc './images'
sudo chmod g+r -Rc './images'

# remove old temp directory if it is still there
sudo rm -rvf './images/folk-vending-cucumber'

# ensure backup directory exists
sudo zsh -c "mkdir -vp $backup_path && chown -c doom:doom $backup_path"

new_files_count="$(find ./images -path ./images/thumb -prune -o -daystart -mtime -3 -type f -print | wc -l)"

if [ "$new_files_count" -gt 0 ]; then
    tar -cjf "${backup_path}/${images_backup_name}.tar.bz2" \
    --exclude 'images/thumb' --exclude 'images/deleted' \
    images/
fi
