#!/usr/bin/env zsh
# Attu Project Wiki - Job runner container entry script
# This file is licensed under the MIT License; See LICENSE for full text.

set -eu

case "${RUNNER_TYPE:-runner}" in
    "scheduler")
    exec supercronic -overlapping -json $USER_HOME/wiki.crontab
    ;;

    "update")
    cd "$APP_HOME/mediawiki"
    php maintenance/run.php update --quick
    ;;
esac
