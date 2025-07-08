#!/usr/bin/zsh

WIKI=/srv/services/attu-wiki-prod

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
    'Template:Main'
}

printf '%s\n' "Fetching new templates"
curl -d "&pages=`template_list`&curonly=1&action=submit&templates=1" 'https://en.wikipedia.org/w/index.php?title=Special:Export' -o "$WIKI/files/templates.xml"

docker compose -f "$WIKI/docker-compose.yml" cp "$WIKI/files/templates.xml" mediawiki:/tmp/

docker compose -f "$WIKI/docker-compose.yml" exec mediawiki php maintenance/run.php importDump --username-prefix 'w' /tmp/templates.xml

