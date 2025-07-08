#!/usr/bin/env zsh

# Usage: ./compact_backups.zsh <year> <month>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <year> <month>"
    exit 1
fi

year="$1"
month=$(printf "%02d" "$2")

# Configuration
backup_path='/srv/backups/attu-wiki'

compact_prefix="${backup_path}/attu-wiki-backup_${year}-${month}"
cd "$backup_path" || {
    printf '%s\n' "Failed to cd to $backup_path"
    exit 1
}

printf '%s\n' "Compacting backups from ${year}-${month} to [${compact_prefix}.tar.bz2]"

bunzip2 -v "${compact_prefix}-"*.sql.bz2 || {
    printf '%s\n' "Failed to unzip .bz2 SQL backups"
    exit 1
}

tar --remove-files -cjvf "${compact_prefix}.tar.bz2" *.sql || {
    printf '%s\n' "Failed to create compacted archive"
    exit 1
}
