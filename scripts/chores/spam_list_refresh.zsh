#!/usr/bin/env zsh
# Attu Project Wiki - StopForumSpam refresh script
# This file is licensed under the MIT License; See LICENSE for full text.

# config
spam_list_link='https://www.stopforumspam.com/downloads/listed_ip_30_all.zip'
spam_list_output="${APP_HOME}/mediawiki/resources/listed_ip_30_all.txt"

# temp file
spam_list_temp=$(mktemp --suffix=.zip)
trap 'rm -vf "$spam_list_temp"' EXIT

# download file
curl -LsSf "$spam_list_link" -o "$spam_list_temp"
unzip -p "$spam_list_temp" > "$spam_list_output"
sudo chmod a+r "$spam_list_output"
