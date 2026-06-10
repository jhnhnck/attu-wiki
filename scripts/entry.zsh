#!/usr/bin/env zsh
# Attu Project Wiki - Container entry and task dispatcher
# This file is licensed under the MIT License; See LICENSE for full text.

zparseopts -D -E -F -- -allow-dev=ALLOW_DEV_FLAG

# --- Entry modes (no dev-simulation; run unconditionally) ----------------

case "${1:-}" in
    'task:scheduler')
    set -eu
    # -overlapping: don't skip a job if the previous run is still in progress
    # -json: structured log output
    exec supercronic -overlapping -json "$USER_HOME/wiki.crontab"
    ;;

    'task:update')
    set -eu
    cd "$APP_HOME/mediawiki"
    php maintenance/run.php update --quick
    zsh "$USER_HOME/chores/load_modules.zsh"
    sudo chown --changes doom:doom "$APP_HOME/mediawiki/images"
    sudo chown --changes doom:doom "$APP_HOME/mediawiki/sitemap"
    exit 0
    ;;
esac

# --- Task dispatcher -----------------------------------------------------

if [[ "${BUILD_TYPE:-}" = "dev" && ${#ALLOW_DEV_FLAG} -eq 0 ]]; then
    print "Dev Build: Simulating [${1}]"
    sleep 5
    exit 0
fi

heartbeat_url="https://uptime.betterstack.com/api/v1/heartbeat/${TASKS_HEARTBEAT_KEY}"

send_success() {
    print 'Success!'
    curl --fail --silent --show-error "${heartbeat_url}" > /dev/null
    exit 0
}

exit_trap() {
    print 'caught error; sending fail notification'
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
    print 'Running backup: wiki database'
    zsh "$USER_HOME/backups/wiki_database_backup.zsh" && send_success
    ;;

    'backup:images')
    print 'Running backup: wiki images'
    zsh "$USER_HOME/backups/wiki_images_backup.zsh" && send_success
    ;;

    'chore:bundle-backups')
    print 'Running chore: bundle database backups'
    zsh "$USER_HOME/chores/bundle_db_backups.zsh"
    ;;

    'chore:clean-upload-stash')
    print 'Running chore: maintenance script cleanupUploadStash'
    cd "$APP_HOME/mediawiki"
    sudo --preserve-env -u www-data -- \
        php maintenance/run.php cleanupUploadStash
    ;;

    'chore:regenerate-sitemap')
    print 'Running chore: maintenance script generateSitemap'
    cd "$APP_HOME/mediawiki"
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
    print 'Running chore: update StopForumSpam list'
    zsh "$USER_HOME/chores/spam_list_refresh.zsh"
    ;;

    'chore:templates-refresh')
    print 'Running chore: update templates from wikipedia'
    zsh "$USER_HOME/chores/templates_refresh.zsh"
    ;;

    'task:error-rate-monitor')
    print 'Running task: error rate monitor'
    python3 "$USER_HOME/tasks/attu_error_rate.py"
    ;;

    'task:run-jobs')
    print 'Running task: job runner'
    cd "$APP_HOME/mediawiki"
    for i in {1..3}; do
        sudo --preserve-env -u www-data -- \
            php maintenance/run.php runJobs \
                --maxtime 300 \
                --memory-limit 300M &
    done
    wait
    ;;

    'chore:certbot-renew')
    print 'Running chore: renew SSL certificates'
    zsh "$USER_HOME/chores/certbot_renew.zsh" && send_success
    ;;

    'chore:load-modules')
    print 'Running chore: sync wiki modules from repo'
    zsh "$USER_HOME/chores/load_modules.zsh" && send_success
    ;;

    *)
    print -u2 -- "caught invalid task: ${1}"
    exit 1
    ;;
esac
