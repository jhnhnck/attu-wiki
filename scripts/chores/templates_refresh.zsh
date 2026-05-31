#!/usr/bin/env zsh
# Attu Project Wiki - Templates refresh script
# This file is licensed under the MIT License; See LICENSE for full text.

# temp file
templates_xml=$(mktemp --suffix=.xml)
trap 'rm -vf "$templates_xml"' EXIT

# Disabled:'Template:IPA'
# Moved to wiki/Template/ (managed in repo, synced via load_modules):
#   Composition bar, Taxobox, Did you mean box, Infobox military unit,
#   Infobox, MessageBox, Color box, Main, Cquote
# Add entries here to pull upstream Wikipedia updates for any of the above.
template_list() {
    : # nothing to refresh
}

pages=$(template_list)
if [[ -z "$pages" ]]; then
    printf '%s\n' "No templates to refresh"
    exit 0
fi

# download templates
printf '%s\n' "Fetching new templates"
curl -LsSf 'https://en.wikipedia.org/w/index.php?title=Special:Export' \
    -d "&pages=${pages}&curonly=1&action=submit&templates=1" \
    -o "$templates_xml"
sudo chmod a+r "$templates_xml"

# import to wiki
cd "$APP_HOME/mediawiki";
sudo --preserve-env -u www-data -- \
    php maintenance/run.php importDump --username-prefix 'w' "$templates_xml"
