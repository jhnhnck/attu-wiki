#!/usr/bin/env zsh
# Attu Project Wiki - Load wiki modules script
# This file is licensed under the MIT License; See LICENSE for full text.

# Sync wiki/ pages from this image into the live wiki.
# Checksums are generated at build time ($USER_HOME/wiki/.checksums);
# applied checksums are persisted to a volume path so unchanged pages are skipped.

set -eu

cd "$APP_HOME/mediawiki"

wiki_dir="$USER_HOME/wiki"
image_checksums="$wiki_dir/.checksums"
applied_checksums="$APP_HOME/mediawiki/images/load_modules.sha256"

# Derive MediaWiki page title from an absolute file path under $wiki_dir.
# wiki/Main/Foo/Bar.txt    -> Foo/Bar
# wiki/Module/Foo.lua      -> Module:Foo
# wiki/Attu_Project/Home.txt -> Attu_Project:Home
page_title() {
    local file="$1"
    local rel="${file#${wiki_dir}/}"   # strip leading wiki_dir/
    local ns="${rel%%/*}"              # first path component = namespace
    local rest="${rel#*/}"             # remainder after namespace/
    local base="${rest%.*}"            # strip extension
    if [[ "$ns" == "Main" ]]; then
        printf '%s' "$base"
    else
        printf '%s:%s' "$ns" "$base"
    fi
}

updated=0
skipped=0

while IFS= read -r line; do
    # line format: "<sha256>  <path>"
    image_hash="${line%% *}"
    filepath="${line##*  }"

    title=$(page_title "$filepath")

    # compare to last-applied checksum for this path
    applied_hash=""
    if [[ -f "$applied_checksums" ]]; then
        applied_hash=$(grep -F "  $filepath" "$applied_checksums" 2>/dev/null | head -1 | awk '{print $1}')
    fi

    if [[ "$image_hash" == "$applied_hash" ]]; then
        printf 'skipped %s\n' "$title"
        (( skipped++ )) || true
        continue
    fi

    printf 'updating %s\n' "$title"
    sudo --preserve-env -u www-data -- \
        php maintenance/run.php edit \
            -u Doom \
            -b \
            -s "load_modules: sync" \
            "$title" \
            < "$filepath"

    # update applied checksum for this path
    if [[ -f "$applied_checksums" ]]; then
        # remove old entry for this path, append new one
        grep -vF "  $filepath" "$applied_checksums" > "${applied_checksums}.tmp" || true
        mv "${applied_checksums}.tmp" "$applied_checksums"
    fi
    printf '%s  %s\n' "$image_hash" "$filepath" >> "$applied_checksums"

    (( updated++ )) || true
done < "$image_checksums"

printf '%d updated, %d skipped\n' "$updated" "$skipped"
