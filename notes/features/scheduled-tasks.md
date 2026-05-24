# Scheduled Tasks

All tasks run via Supercronic in the `scheduler` container. Every invocation routes through `scripts/attu_tasks.zsh`, which handles Discord failure alerts and BetterStack heartbeat pings.

---

## Task Table

| Identifier | Schedule | Script / Command | Description |
| :--- | :--- | :--- | :--- |
| `task:run-jobs` | Every 2 min | `php maintenance/run.php runJobs` (3× parallel) | Drains MediaWiki Redis job queue; 300s max per worker, 300M memory limit |
| `task:error-rate-monitor` | Every 15 min | `tasks/attu_error_rate.py` | Reads Caddy access logs from journald; alerts Discord on >1.5% 5xx rate (min 10 errors) |
| `backup:database` | Daily 18:00 | `backups/wiki_database_backup.zsh` | `mariadb-dump` piped to bzip2; validates result ≥10KB |
| `backup:images` | Every 3 days 18:00 | `backups/wiki_images_backup.zsh` | Tar of uploads dir, excludes `thumb/` and `deleted/`, only files modified in last 3 days |
| `chore:bundle-backups` | 1st of month 20:00 | `chores/bundle_db_backups.zsh` | Decompresses and re-bundles daily SQL backups from prior month into one tar.bz2 |
| `chore:clean-upload-stash` | Daily 00:30 | `php maintenance/run.php cleanupUploadStash` | Removes abandoned upload stash files |
| `chore:regenerate-sitemap` | Daily 20:00 | `php maintenance/run.php generateSitemap` | Writes XML sitemaps to `/app/mediawiki/sitemap/`; skips redirects |
| `chore:spam-list-refresh` | Every 3 days 20:00 | `chores/spam_list_refresh.zsh` | Downloads fresh StopForumSpam blocklist to `resources/listed_ip_30_all.txt` |
| `chore:templates-refresh` | Every 7 days 20:00 | `chores/templates_refresh.zsh` | Imports 9 Wikipedia templates via Special:Export + `importDump` maintenance script |
| `chore:certbot-renew` | Daily 03:00 + 15:00 | `chores/certbot_renew.zsh` | Runs `certbot renew` against mounted `/srv/services/certbot/config`; fixes `.pem` ownership to GID 976 (caddy); prod-only volume mounts |

---

## Dispatcher: `scripts/attu_tasks.zsh`

All tasks are invoked as:

```
zsh $USER_HOME/attu_tasks.zsh "<identifier>"
```

The dispatcher:

1. Checks `BUILD_TYPE=dev` + absence of `--allow-dev` flag → prints simulated message and exits 0
2. Sets `trap 'exit_trap' ZERR` — any non-zero exit fires a Discord failure alert then exits 1
3. Sets `set -eu` — unset variables and failed commands propagate immediately
4. Runs the task via a `case "$1"` match
5. Calls `send_success` at the end of successful tasks — pings BetterStack heartbeat URL

**ZERR trap fires on any command failure**, not just the final command. Sub-scripts called with `zsh -eu` propagate their failures back correctly.

---

## Dev Mode

In dev (`BUILD_TYPE=dev`), every task short-circuits:

```zsh
printf 'Dev Build: Simulating [%s]\n' "$1"
sleep 5
exit 0
```

**Exception:** `task:run-jobs` is the only entry in `wiki.crontab` that passes `--allow-dev`, so it actually runs the job queue drainer in dev.

To run any other task for real in dev:

```bash
docker compose exec scheduler zsh "$USER_HOME/attu_tasks.zsh" "task:error-rate-monitor" --allow-dev
```

---

## Environment Variables

| Variable | Used by |
| :--- | :--- |
| `BUILD_TYPE` | Dispatcher; controls dev simulation |
| `TASKS_HEARTBEAT_KEY` | `send_success`; constructs BetterStack heartbeat URL |
| `ATTU_SCRIPTS_WEBHOOK` | Discord alert on task failure |
| `ATTU_WEBHOOK_ICON` | Discord alert avatar URL |
| `ATTU_DB_PASSWORD` | Database backup scripts (via `MYSQL_PWD=`) |
| `APP_HOME` | Path to `/app`; used to locate `mediawiki/` |
| `USER_HOME` | Path to scripts dir inside container |

---

## Adding a New Task

1. Add a `case` entry in `scripts/attu_tasks.zsh`:
   ```zsh
   'task:my-new-task')
   printf '%s\n' "Running task: my new task"
   python3 "$USER_HOME/tasks/my_task.py" && send_success
   ;;
   ```

2. Add a line to `config/wiki.crontab`:
   ```
   0 6 * * *   zsh $USER_HOME/attu_tasks.zsh "task:my-new-task"
   ```

3. Rebuild the scheduler container so it picks up the updated crontab:
   ```bash
   docker compose up -d --build scheduler
   ```

Use `send_success` only for tasks where completion is worth pinging BetterStack (i.e. health-monitored tasks). Chores that run silently on a best-effort basis can omit it.

---

## metadata

```yaml
last_updated: 30 March 2026
```
