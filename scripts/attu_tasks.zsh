#!/usr/bin/env zsh
# Attu Project Wiki - Scheduled tasks script
# This file is licensed under the MIT License; See LICENSE for full text.

zparseopts -D -E -- -allow-dev=ALLOW_DEV_FLAG

if [[ "${BUILD_TYPE:-}" = "dev" && ${#ALLOW_DEV_FLAG} -eq 0 ]]; then
    printf 'Dev Build: Simulating [%s]\n' "$1"
    sleep 5
    exit 0
fi

# task alerts
heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${TASKS_HEARTBEAT_KEY}"

send_success() {
    printf '%s\n' "Success!"
    curl -fsS "${heartbeat_url}" > /dev/null
    exit 0
}

exit_trap() {
    printf '%s\n' "caught error; sending fail notification"
    discord.sh --webhook-url="$ATTU_SCRIPTS_WEBHOOK" \
        --username 'Wiki Service Alert' \
        --avatar "$ATTU_WEBHOOK_ICON" \
        --title 'An error occurred running a scheduled task.' \
        --description "**Identifier:** \`${1}\`" \
        --field "Build Type;${BUILD_TYPE:-prod}" \
        --field "Hostname;${HOSTNAME}" \
        --color "0xff4941" \
        --footer "${0}" \
        --timestamp
    exit 1
}

trap 'exit_trap' ZERR
set -eu

case "$1" in
    'backup:database')
    printf '%s\n' "Running backup: wiki database"
    zsh -eu "$USER_HOME/backups/wiki_database_backup.zsh" && send_success
    ;;

    'backup:images')
    printf '%s\n' "Running backup: wiki images"
    zsh -eu "$USER_HOME/backups/wiki_images_backup.zsh" && send_success
    ;;

    'chore:bundle-backups')
    printf '%s\n' "Running chore: bundle database backups"
    zsh -eu "$USER_HOME/chores/bundle_db_backups.zsh"
    ;;

    'chore:clean-upload-stash')
    printf '%s\n' "Running chore: maintenance script cleanupUploadStash"
    cd "$APP_HOME/mediawiki";
    sudo --preserve-env -u www-data -- \
        php maintenance/run.php cleanupUploadStash
    ;;

    'chore:regenerate-sitemap')
    printf '%s\n' "Running chore: maintenance script generateSitemap"
    cd "$APP_HOME/mediawiki";
    sudo --preserve-env -u www-data -- \
        php maintenance/run.php generateSitemap \
            --fspath="$APP_HOME/mediawiki/sitemap/" \
            --identifier=attuproject.org \
            --urlpath=/sitemap/ \
            --compress=no \
            --skip-redirects \
            --server='https://attuproject.org'
    ;;

    'chore:spam-list-refresh')
    printf '%s\n' "Running chore: update StopForumSpam list"
    zsh -eu "$USER_HOME/chores/spam_list_refresh.zsh"
    ;;

    'chore:templates-refresh')
    printf '%s\n' "Running chore: update templates from wikipedia"
    zsh -eu "$USER_HOME/chores/templates_refresh.zsh"
    ;;

    'task:error-rate-monitor')
    printf '%s\n' "Running task: error rate monitor"
    python3 "$USER_HOME/tasks/attu_error_rate.py"
    ;;

    'task:run-jobs')
    printf '%s\n' "Running task: job runner"
    cd "$APP_HOME/mediawiki";
    for i in {1..3}; do
        sudo --preserve-env -u www-data -- \
            php maintenance/run.php runJobs \
                --maxtime 300 \
                --memory-limit 300M &
    done
    wait
    ;;

    'chore:certbot-renew')
    printf '%s\n' "Running chore: renew SSL certificates"
    zsh -eu "$USER_HOME/chores/certbot_renew.zsh" && send_success
    ;;

    *)
    printf 'Caught invalid task: %s\n' "$1"
    exit 1
    ;;
esac
