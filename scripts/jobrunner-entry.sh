#!/usr/bin/env bash

set -eu

case "${RUNNER_TYPE:-runner}" in
    "chron")
    exec php ./redisJobChronService --config-file=config.json
    ;;

    "runner")
    exec php ./redisJobRunnerService --config-file=config.json
    ;;

    "update")
    cd "$APP_HOME/mediawiki"
    exec php maintenance/run.php update --quick
    ;;
esac
