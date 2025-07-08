#!/usr/bin/env zsh

# Import Secrets
SCRIPT_SOURCE=${0%/*}
cd $SCRIPT_SOURCE/..
source .env

# Configuration
backup_path='/srv/backups/attu-wiki'
bot_backup_path='/srv/backups/attu-bot'
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${HEARTBEAT_KEY}"
min_backup_size=10000
wiki_path="$PWD"
mw_container='mediawiki'
db_container='database'

# Exit Trap
exit_trap() {
    printf '%s\n' "caught error; sending fail hook"
    curl -fsS "${heartbeat_url}/fail" >/dev/null
    exit 1
}

trap 'exit_trap' ZERR

boot_secs=$(printf '%.0f\n' "$(cut -d' ' -f1 </proc/uptime)")
if [ "$boot_secs" -lt 300 ]; then
    printf '%s\n' "Script caught running ${boot_secs}s after boot; exiting"
    exit 0
fi

# set -eux

# Download ip ban list
ip_list_url="https://www.stopforumspam.com/downloads/listed_ip_30_all.zip"
ip_list_dest="${wiki_path}/files/listed_ip_30_all.txt"

if [[ -e "$ip_list_dest" && $(($(date +%s) - $(stat -c %Y "$ip_list_dest"))) -gt $((3 * 3600)) ]]; then
    printf '%s\n' "StopForumSpam list is stale; refreshing..."

    ip_temp=$(mktemp --suffix=.zip)
    trap 'rm -vf "$ip_temp"' EXIT

    curl -LsSf "$ip_list_url" -o "$ip_temp"
    unzip -p "$ip_temp" >"$ip_list_dest"
    chmod 644 "$ip_temp"
else
    printf '%s\n' "StopForumSpam list is fresh; skipping step"
fi

# update templates
templates_xml="${wiki_path}/files/templates.xml"

if [[ -e "$templates_xml" && $(($(date +%s) - $(stat -c %Y "$templates_xml"))) -gt $((7 * 3600)) ]]; then
    printf '%s\n' "templates.xml is stale; refreshing..."

    template_list() {
        printf '%s%%0A' \
            'Template:Composition bar' \
            'Template:Taxobox' \
            'Template:Did you mean box' \
            'Template:Infobox military unit' \
            'Template:IPA' \
            'Template:Infobox' \
            'Template:MessageBox' \
            'Template:Color box' \
            'Template:Main' \
            'Template:Cquote'
    }

    printf '%s\n' "Fetching new templates"
    curl -d "&pages=$(template_list)&curonly=1&action=submit&templates=1" 'https://en.wikipedia.org/w/index.php?title=Special:Export' -o "$templates_xml"

    docker compose -f "$wiki_path/docker-compose.yml" cp "$templates_xml" "$mw_container:/tmp/templates.xml"

    docker compose -f "$wiki_path/docker-compose.yml" exec "$mw_container" php maintenance/run.php importDump --username-prefix 'w' /tmp/templates.xml

else
    printf '%s\n' "templates.xml is fresh; skipping step"
fi

# Run maintenance scripts
printf '%s\n' "Regenerating sitemap"
docker compose -f "$wiki_path/docker-compose.yml" exec "$mw_container" php maintenance/run.php generateSitemap --fspath=/var/www/html/sitemap/ --identifier=attuproject.org --urlpath=/sitemap/ --compress=no --skip-redirects --server="https://attuproject.org"

# rebuild docker containers
printf '%s\n' "Pulling any changes to docker images"

docker compose -f "$wiki_path/docker-compose.yml" up -d --build --pull always --quiet-pull
