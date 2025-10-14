#!/usr/bin/env zsh
# Attu Project Wiki - Job runner container entry script
# This file is licensed under the MIT License; See LICENSE for full text.

set -eu

case "${RUNNER_TYPE:-runner}" in
    "chron")
    cd "$APP_HOME/jobrunner"
    exec php ./redisJobChronService --config-file=config.json
    ;;

    "runner")
    cd "$APP_HOME/jobrunner"
    exec php ./redisJobRunnerService --config-file=config.json
    ;;

    "scheduler")
    cd "$APP_HOME/scheduler"
    exec supercronic ./wiki.crontab
    ;;

    "sshd")
    echo "www-data:$ATTU_SSH_PASSWORD" | chpasswd
    exec /usr/sbin/sshd -D
    ;;

    "update")
    cd "$APP_HOME/mediawiki"
    exec php maintenance/run.php update --quick
    ;;
esac
