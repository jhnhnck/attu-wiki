#!/usr/bin/env zsh
# Attu Project Wiki - Scheduled tasks script
# This file is licensed under the MIT License; See LICENSE for full text.

set -eu

if [ "${BUILD_TYPE:-}" = 'dev' ]; then
    printf 'Dev Build: Simulating [%s]\n' "$1"
    sleep 5
    exit 0
fi

case '$1' in
    'backup:database')
    printf '%s\n' "Running backup: wiki database"
    ;;

    'backup:images')
    printf '%s\n' "Running backup: wiki images"

    ;;

    'chore:bundle-backups')
    printf '%s\n' "Running chore: bundle database backups"

    ;;

    'chore:clean-upload-stash')
    printf '%s\n' "Running chore: maintenance script cleanupUploadStash"

    ;;

    'chore:regenerate-sitemap')
    printf '%s\n' "Running chore: maintenance script generateSitemap"

    ;;

    'chore:spam-list-refresh')
    printf '%s\n' "Running chore: update StopForumSpam list"

    ;;

    'chore:templates-refresh')
    printf '%s\n' "Running chore: update templates from wikipedia"

    ;;

    'task:error-rate-monitor')
    printf '%s\n' "Running task: error rate monitor"
    source $APP_HOME/.venv/bin/activate && python $APP_HOME/scripts/tasks/attu_error_rate.py
    ;;

    *)
    printf 'Caught invalid task: %s\n' "$1"
    exit 1
    ;;
esac
