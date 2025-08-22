#!/usr/bin/env bash

set -eu

case "${RUNNER_TYPE:-runner}" in
    "chron")
    php ./redisJobChronService --config-file=config.json
    ;;

    "runner")
    php ./redisJobRunnerService --config-file=config.json
    ;;

    "update")
    cd /var/www/mediawiki
    php maintenance/run.php update --quick
    ;;
esac
