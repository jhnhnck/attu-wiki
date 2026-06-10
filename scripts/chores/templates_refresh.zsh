#!/usr/bin/env zsh
# Attu Project Wiki - Templates refresh script
# This file is licensed under the MIT License; See LICENSE for full text.

set -eu

# temp file
templates_xml=$(mktemp --suffix=.xml)
trap 'rm --verbose --force "$templates_xml"' EXIT

# Disabled:'Template:IPA'
template_list() {
    local -a templates=(
        'Template:Composition bar'
        'Template:Taxobox'
        'Template:Did you mean box'
        'Template:Infobox military unit'
        'Template:Infobox'
        'Template:MessageBox'
        'Template:Color box'
        'Template:Main'
        'Template:Cquote'
    )
    print -rn -- "${(j:%0A:)templates}%0A"
}

# download templates
print 'Fetching new templates'
curl --location --silent --show-error --fail \
    'https://en.wikipedia.org/w/index.php?title=Special:Export' \
    --data "&pages=$(template_list)&curonly=1&action=submit&templates=1" \
    --output "$templates_xml"
sudo chmod a+r "$templates_xml"

# import to wiki
cd "$APP_HOME/mediawiki"
sudo --preserve-env -u www-data -- \
    php maintenance/run.php importDump --username-prefix 'w' "$templates_xml"
