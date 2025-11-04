#!/usr/bin/env zsh
# Attu Project Wiki - Automatic backups script
# This file is licensed under the MIT License; See LICENSE for full text.

backup_path="$APP_HOME/backups"
prev_datestamp=$(date -d '1 month ago' '+%Y-%m')
compact_prefix="${backup_path}/attu-wiki-backup_${prev_datestamp}"

cd "$backup_path"

bunzip2 "${compact_prefix}-"*.sql.bz2
tar --remove-files -cjf "${compact_prefix}.tar.bz2" *.sql
