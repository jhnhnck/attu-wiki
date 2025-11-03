#!/usr/bin/env zsh
# Attu Project Wiki - Job runner container entry script
# This file is licensed under the MIT License; See LICENSE for full text.

set -eu

case "${RUNNER_TYPE:-runner}" in
    "chron")
    cd "$APP_HOME/jobrunner"
    php ./redisJobChronService --config-file=config.json
    ;;

    "runner")
    cd "$APP_HOME/jobrunner"
    php ./redisJobRunnerService --config-file=config.json
    ;;

    "scheduler")
    exec supercronic $USER_HOME/wiki.crontab
    ;;

    "update")
    cd "$APP_HOME/mediawiki"
    php maintenance/run.php update --quick
    ;;
esac
