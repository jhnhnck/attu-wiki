#!/usr/bin/env zsh
# Attu Project Wiki - Automatic backups script
# This file is licensed under the MIT License; See LICENSE for full text.

set -eu

# wiki config
current_date=$(date +%Y-%m-%d)
backup_path="$APP_HOME/backups"
images_backup_name="attu-images-backup_${current_date}"

cd "$APP_HOME/mediawiki"

# make sure everything is readable by us
sudo chown --recursive --changes www-data:www-data './images'
sudo chmod --recursive --changes g+r './images'

# remove old temp directory if it is still there
sudo rm --recursive --verbose --force './images/folk-vending-cucumber'

# ensure backup directory exists
sudo zsh -c 'mkdir --verbose --parents "$1" && chown --changes doom:doom "$1"' -- "$backup_path"

# -daystart: measure times from start of today; -mtime -3: modified in last 3 days
new_files_count="$(find ./images -path ./images/thumb -prune -o -daystart -mtime -3 -type f -print | wc --lines)"

if (( new_files_count > 0 )); then
    tar --create --bzip2 --file="${backup_path}/${images_backup_name}.tar.bz2" \
        --exclude='images/thumb' --exclude='images/deleted' \
        images/
fi
