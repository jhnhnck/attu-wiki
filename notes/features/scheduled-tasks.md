scheduled-task catalog for the wiki: every task runs via Supercronic in the `scheduler` container and routes through `scripts/entry.zsh`, which handles Discord failure alerts and BetterStack heartbeat pings.

## tasks

| identifier | schedule | script / command | description |
|---|---|---|---|
| `task:run-jobs` | every 2 min | `php maintenance/run.php runJobs` (3× parallel) | drains MediaWiki Redis job queue; 300s max per worker, 300M memory limit |
| `task:error-rate-monitor` | every 15 min | `tasks/attu_error_rate.py` | reads Caddy access logs from journald; alerts Discord on >1.5% 5xx rate (min 10 errors) |
| `backup:database` | daily 18:00 | `backups/wiki_database_backup.zsh` | `mariadb-dump` piped to bzip2; validates result ≥10KB |
| `backup:images` | every 3 days 18:00 | `backups/wiki_images_backup.zsh` | tar of uploads dir; excludes `thumb/` and `deleted/`; only files modified in last 3 days |
| `chore:bundle-backups` | 1st of month 20:00 | `chores/bundle_db_backups.zsh` | decompresses and re-bundles daily SQL backups from prior month into one `tar.bz2` |
| `chore:clean-upload-stash` | daily 00:30 | `php maintenance/run.php cleanupUploadStash` | removes abandoned upload stash files |
| `chore:regenerate-sitemap` | daily 20:00 | `php maintenance/run.php generateSitemap` | writes XML sitemaps to `/app/mediawiki/sitemap/`; skips redirects |
| `chore:spam-list-refresh` | every 3 days 20:00 | `chores/spam_list_refresh.zsh` | downloads fresh StopForumSpam blocklist to `resources/listed_ip_30_all.txt` |
| `chore:templates-refresh` | every 7 days 20:00 | `chores/templates_refresh.zsh` | imports 9 Wikipedia templates via `Special:Export` + `importDump` maintenance script |
| `chore:acme-renew` | daily 03:00 + 15:00 | `chores/acme_renew.zsh` | runs `acme.sh --issue --dns dns_cf` (Let's Encrypt, Cloudflare DNS-01); issues/renews a single multi-SAN cert for all three domains; installs to `/srv/services/certificates/attuproject.org/`; fixes `.pem` ownership to GID 976 (caddy); exit 2 from acme.sh = not yet due, treated as success |

## dispatcher

all tasks are invoked as:

```zsh
zsh $USER_HOME/entry.zsh "<identifier>"
```

the dispatcher does the following, in order:

1. checks `BUILD_TYPE=dev` + absence of `--allow-dev` flag; prints simulated message and exits 0
1. sets `trap 'exit_trap' ZERR`; any non-zero exit fires a Discord failure alert then exits 1
1. sets `set -eu`; unset variables and failed commands propagate immediately
1. runs the task via a `case "$1"` match
1. calls `send_success` at the end of successful tasks; pings the BetterStack heartbeat URL

the ZERR trap fires on any command failure, not just the final command. sub-scripts propagate their failures back via their own `set -eu`.

## dev mode

in dev (`BUILD_TYPE=dev`), every task short-circuits:

```zsh
print "Dev Build: Simulating [${1}]"
sleep 5
exit 0
```

exception: `task:run-jobs` is the only entry in `wiki.crontab` that passes `--allow-dev`, so it actually runs the job queue drainer in dev.

to run any other task for real in dev:

```bash
docker compose exec scheduler zsh "$USER_HOME/entry.zsh" "task:error-rate-monitor" --allow-dev
```

## environment variables

| variable | used by |
|---|---|
| `BUILD_TYPE` | dispatcher; controls dev simulation |
| `TASKS_HEARTBEAT_KEY` | `send_success`; constructs BetterStack heartbeat URL |
| `ATTU_SCRIPTS_WEBHOOK` | Discord alert on task failure |
| `ATTU_WEBHOOK_ICON` | Discord alert avatar URL |
| `ATTU_DB_PASSWORD` | database backup scripts (via `MYSQL_PWD=`) |
| `APP_HOME` | path to `/app`; used to locate `mediawiki/` |
| `USER_HOME` | path to scripts dir inside container |

## adding a new task

1. add a `case` entry in `scripts/entry.zsh`:

   ```zsh
   'task:my-new-task')
   print 'Running task: my new task'
   python3 "$USER_HOME/tasks/my_task.py" && send_success
   ;;
   ```

1. add a line to `config/wiki.crontab`:

   ```
   0 6 * * *   zsh $USER_HOME/entry.zsh "task:my-new-task"
   ```

1. rebuild the scheduler container so it picks up the updated crontab:

   ```bash
   docker compose up -d --build scheduler
   ```

use `send_success` only for tasks where completion is worth pinging BetterStack (i.e. health-monitored tasks). chores that run silently on a best-effort basis can omit it.

## see also

- [../agents.md](../agents.md) - root agent guide, including the rule that dev tasks simulate by default
- [../style/commit_style.md](../style/commit_style.md) - commit conventions for changes to tasks and scripts

---

## metadata

```yaml
last_updated: 24 May 2026
```
