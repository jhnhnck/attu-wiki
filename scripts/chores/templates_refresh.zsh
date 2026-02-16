#!/usr/bin/env zsh
# Attu Project Wiki - Templates refresh script
# This file is licensed under the MIT License; See LICENSE for full text.

# temp file
templates_xml=$(mktemp --suffix=.xml)
trap 'rm -vf "$templates_xml"' EXIT

# Disabled:'Template:IPA'
template_list() {
    printf '%s%%0A' \
        'Template:Composition bar' \
        'Template:Taxobox' \
        'Template:Did you mean box' \
        'Template:Infobox military unit' \
        'Template:Infobox' \
        'Template:MessageBox' \
        'Template:Color box' \
        'Template:Main' \
        'Template:Cquote'
}

# download templates
printf '%s\n' "Fetching new templates"
curl -LsSf 'https://en.wikipedia.org/w/index.php?title=Special:Export' \
    -d "&pages=$(template_list)&curonly=1&action=submit&templates=1" \
    -o "$templates_xml"
sudo chmod a+r "$templates_xml"

# import to wiki
cd "$APP_HOME/mediawiki";
sudo --preserve-env -u www-data -- \
    php maintenance/run.php importDump --username-prefix 'w' "$templates_xml"
