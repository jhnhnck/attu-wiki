#!/usr/bin/env zsh
# Attu Project Wiki - Manual backups compaction script
# This file is licensed under the MIT License; See LICENSE for full text.
# Usage: ./compact_backups.zsh <year> <month>

set -eu

if (( $# != 2 )); then
    print -u2 -- "usage: $0 <year> <month>"
    exit 2
fi

year="$1"
typeset -Z2 month=$2

# Configuration
backup_path='/srv/backups/attu-wiki'

compact_prefix="${backup_path}/attu-wiki-backup_${year}-${month}"
cd "$backup_path" || {
    print -u2 -- "failed to cd to $backup_path"
    exit 1
}

print "Compacting backups from ${year}-${month} to [${compact_prefix}.tar.bz2]"

bunzip2 --verbose "${compact_prefix}-"*.sql.bz2 || {
    print -u2 -- "failed to unzip .bz2 SQL backups"
    exit 1
}

tar --remove-files --create --bzip2 --verbose --file="${compact_prefix}.tar.bz2" *.sql || {
    print -u2 -- "failed to create compacted archive"
    exit 1
}
