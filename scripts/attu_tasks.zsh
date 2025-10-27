#!/usr/bin/env zsh
# Attu Project Wiki - Scheduled tasks script
# This file is licensed under the MIT License; See LICENSE for full text.

if [ "${BUILD_TYPE:-}" = 'dev' ]; then
    printf 'Dev Build: Simulating [%s]\n' "$1"
    sleep 5
    exit 0
fi

# failed task alerts
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${TASKS_HEARTBEAT_KEY}"

exit_trap() {
    printf '%s\n' "caught error; sending fail hook"
    curl -fsS "${heartbeat_url}/fail" >/dev/null
    exit 1
}

trap 'exit_trap' ZERR
set -eu

case '$1' in
    'backup:database')
    printf '%s\n' "Running backup: wiki database"
    zsh -eu $APP_HOME/scripts/backups/wiki_database_backup.zsh
    ;;

    'backup:images')
    printf '%s\n' "Running backup: wiki images"
    zsh -eu $APP_HOME/scripts/backups/wiki_images_backup.zsh
    ;;

    'chore:bundle-backups')
    printf '%s\n' "Running chore: bundle database backups"
    zsh -eu $APP_HOME/scripts/chores/bundle_db_backups.zsh
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
