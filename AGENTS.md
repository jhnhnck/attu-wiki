# Attu Wiki - Agent Guide

## 1. Project Overview

Self-hosted MediaWiki 1.44 wiki for the [Attu Project](https://attuproject.org), running on Docker via FrankenPHP (Caddy + PHP 8.4). Multi-container Compose stack: `mediawiki`, `database` (MariaDB 12), `redis`, `scheduler` (Supercronic), `job-update` init container; `yourls` in production only. All containers log to journald.

---

## 2. Rules

- Don't commit secrets - `.env` is gitignored; all credentials live there
- Don't push or deploy without asking first
- MediaWiki maintenance scripts must run as `www-data` via `sudo --preserve-env -u www-data`; running as root breaks file ownership
- Don't edit files inside `repos/` directly - they hold patched upstream sources applied at build time
- Don't edit `devel/NovaDiscord/` inside the container - it's a read-only bind mount for live editing on the host
- All containers log to journald; don't redirect logs elsewhere
- In dev, all scheduled tasks are simulated (print-and-sleep) except `task:run-jobs`, which uses `--allow-dev` in the crontab

---

## 3. Architecture

| Module | Role |
| :--- | :--- |
| `mediawiki` | FrankenPHP app server (Caddy + PHP 8.4) on port 8080; serves wiki at `/wiki/$1` |
| `database` | MariaDB 12; dev is ephemeral (loaded from SQL dump), prod uses persistent volume |
| `redis` | Object cache, session store, parser cache, and job queue backend |
| `scheduler` | Supercronic cron runner; dispatches all background tasks via `attu_tasks.zsh` |
| `job-update` | Init container; runs `update --quick` DB migrations before `mediawiki` and `scheduler` start |
| `yourls` | URL shortener at `links.attuproject.org` (prod only, port 6009) |
| `config/` | Caddyfile, LocalSettings.php, wiki.crontab, robots.txt, yourls config |
| `scripts/` | All operational scripts: task dispatcher, backups, chores, error monitor |
| `devel/` | Local development copies of extensions; `NovaDiscord` is bind-mounted into containers |
| `patches/` | Patch files applied to upstream code at build time |
| `repos/` | Cloned upstream repos (Citizen skin, Drafts extension) with patches applied |
| `files/` | Static assets: spam IP list, fonts, favicon, dotfiles served by the wiki |

---

## 4. Configuration System

| File | Purpose |
| :--- | :--- |
| `.env` | All secrets and toggle values; loaded by Docker Compose via `env_file`; never committed |
| `config/LocalSettings.php` | MediaWiki config; reads secrets from `$_ENV`; `$attuDevMode` gates dev-only overrides |
| `config/wiki.crontab` | Supercronic schedule; read at container runtime by the scheduler |
| `config/Caddyfile` | Caddy/FrankenPHP rules; 100M upload limit, 300s max wait, JSON access logs |
| `docker-compose.dev.yml` | Dev stack; ephemeral DB and Redis, bind-mounted NovaDiscord, port 6008 |
| `docker-compose.prod.yml` | Prod stack; persistent volumes, backup mount, port 6010, includes yourls |
| `docker-compose.yml` | Symlink to the active compose file; set via `ln -s docker-compose.${BUILD_TYPE}.yml` |

**`BUILD_TYPE` propagation:** set in Docker Compose `environment:` (runtime) *and* `build.args` (build-time) so it reaches both `LocalSettings.php` and the Dockerfile stages.

**`$attuDevMode`** in LocalSettings.php: `true` when `BUILD_TYPE=dev`; enables debug logging, disables email, switches webhook to alt URL.

---

## 5. Coding Conventions

### Shell (ZSH)

- `set -eu` at the top of every script
- Double-quote all variable expansions in path contexts: `"$APP_HOME/..."`, `"$USER_HOME/..."`
- Use `MYSQL_PWD="$ATTU_DB_PASSWORD"` prefix - never `--password=` CLI arg (exposes in `ps aux`)
- Pass paths to `sudo zsh -c '...'` as positional args, not interpolated into the string:

  ```zsh
  sudo zsh -c 'mkdir -vp "$1"' -- "$backup_path"
  ```

- Scripts invoked from `attu_tasks.zsh` are called with `zsh -eu` - no need to re-declare `set -eu` unless the script is also run standalone

### Python

- Linter: **ruff** (`pyproject.toml` at repo root); type checker: **basedpyright** (standard mode)
- Single quotes for strings, double quotes for docstrings
- Google docstring convention
- Target Python 3.13
- Catch `Exception`, not bare `except:`
- Run: `ruff check scripts/` and `ruff format scripts/`

### PHP

- No linter configured; follow existing MediaWiki conventions
- Read all secrets from `$_ENV`; never hardcode credentials
- Guard the file top with `if (!defined('MEDIAWIKI')) { exit; }`

---

## 7. Running Locally

```bash
# 1. ensure .env exists with all required variables (see README for list)

# 2. place attu-wiki-backup.sql in repo root (dev DB loads from this on first start)

# 3. symlink compose file
ln -s docker-compose.dev.yml docker-compose.yml

# 4. build and start
docker compose up -d --build

# wiki available at https://dev.attuproject.org (requires reverse proxy on host → port 6008)
```

Dev DB is ephemeral - it reinitializes from `attu-wiki-backup.sql` every fresh start. Redis is also ephemeral in dev. NovaDiscord is bind-mounted from `./devel/NovaDiscord/` (read-only inside containers) for live editing.

To rebuild after config changes: `docker compose up -d --build --force-recreate`

---

## 8. Patterns & Pitfalls

1. **`task:run-jobs` is the only task that runs in dev** - it uses `--allow-dev` in `wiki.crontab`; all other tasks simulate (print-and-sleep) unless you pass `--allow-dev` manually
2. **DB password must use `MYSQL_PWD=` env prefix** - not `--password=`; the CLI arg is visible in `ps aux`
3. **`BUILD_TYPE` must appear in both `environment:` and `build.args`** - missing from either breaks runtime or build-time behaviour
4. **MediaWiki maintenance scripts need `sudo --preserve-env -u www-data`** - running as root corrupts upload directory ownership
5. **Session cookie is `brch_session`** - was `brch_sesssion` (triple s) before the 2026-02-09 audit; changing it invalidates existing sessions
6. **`$wgJobRunRate = 0`** - jobs never run on page load; the scheduler drains the queue every 2 minutes via `task:run-jobs`
7. **Custom namespace IDs:** Story=100/101, Record=102/103, Dict=104/105; Talk namespace is renamed to "Meta" (alias `Talk` preserved for compatibility)
8. **`job-update` must complete successfully** before `mediawiki` or `scheduler` start; if it fails, the wiki won't come up - check `docker compose logs job-update`
9. **Scheduler mounts journald sockets read-only** (`/run/log/journal`, `/var/log/journal`, `/run/systemd/journal/socket`, `/etc/machine-id`) so `attu_error_rate.py` can read Caddy access logs via `cysystemd`
10. **`discord.sh` is SHA256-verified at build time** - used by wiki scripts (not by NovaDiscord, which uses HttpRequestFactory); if upgrading the binary, update the checksum in `mediawiki.Dockerfile`
11. **`PageMoveComplete` not `TitleMoveComplete`** is the correct hook name for NovaDiscord; using the wrong name silently disables the hook without errors
12. **Wikipedia template imports use username prefix `'w'`** - maintain this when adding new templates to `templates_refresh.zsh`
13. **Certbot renewal uses hardcoded GID `976` for `chown :caddy`** - the `caddy` group doesn't exist inside the Debian container, so `certbot_renew.zsh` uses the numeric GID from the host; if it changes, update the script. Certbot volume mounts (`/srv/services/certbot/config`, `cloudflare.ini`) are prod-only - dev simulates the task

---

## 9. Reference Notes

| File | Contents |
| :--- | :--- |
| `notes/scheduled-tasks.md` | Full task table, dispatcher pattern, dev mode, how to add or run a task |
| `notes/audit-2026-02-09.md` | Security audit results, rationale for skipped items, list of all fixed issues |
| `notes/.meta.md` | Guide to this documentation system - when to create notes, writing style |

---

## 10. File & Directory Layout

```txt
attu-wiki-dev/
├── AGENTS.md                        ← this file
├── LICENSE.md
├── README.md
├── mediawiki.Dockerfile             ← multi-stage: php-base, mediawiki, scheduler
├── docker-compose.dev.yml
├── docker-compose.prod.yml
├── docker-compose.yml               ← symlink to active compose file
├── pyproject.toml                   ← ruff + basedpyright config
├── attu-wiki-backup.sql             ← gitignored;  SQL dump for dev DB init
├── config/
│   ├── Caddyfile                    ← FrankenPHP/Caddy web server rules
│   ├── LocalSettings.php            ← MediaWiki config; reads secrets from $_ENV
│   ├── robots.txt
│   ├── wiki.crontab                 ← Supercronic schedule
│   └── yourls/                      ← YOURLS config (prod only)
├── scripts/
│   ├── attu_tasks.zsh               ← task dispatcher; all scheduled tasks route through here
│   ├── attu_backup.zsh              ← host-side backup orchestrator (runs via systemd on host)
│   ├── entry.zsh                    ← container entrypoint (scheduler or update mode)
│   ├── requirements.txt             ← Python deps for scripts
│   ├── backups/
│   │   ├── wiki_database_backup.zsh
│   │   └── wiki_images_backup.zsh
│   ├── chores/
│   │   ├── bundle_db_backups.zsh
│   │   ├── certbot_renew.zsh            ← renews all LE certs; uses certbot config outside repo
│   │   ├── spam_list_refresh.zsh
│   │   └── templates_refresh.zsh
│   ├── misc/
│   │   └── bundle_backups.zsh       ← manual backup compaction tool
│   └── tasks/
│       └── attu_error_rate.py       ← reads journald, calculates Caddy 5xx rate, alerts Discord
├── devel/
│   └── NovaDiscord/                 ← custom MediaWiki extension; bind-mounted :ro in dev
├── patches/
│   ├── citizen-viewport.patch
│   ├── drafts-namespaced-types.patch
│   ├── drafts-url-expand.patch
│   ├── jobrunner-e_strict.patch
│   └── mediawiki-deprecated-sidebar.patch
├── repos/
│   ├── mediawiki-extensions-Drafts/ ← patched upstream; copied into image at build
│   └── mediawiki-skins-Citizen/     ← patched upstream; copied into image at build
├── files/
│   ├── assets/                      ← favicon and other static assets
│   ├── dotfiles/                    ← .well-known and similar served files
│   ├── freefont-ttf/                ← fonts for EasyTimeline extension
│   ├── listed_ip_30_all.txt         ← StopForumSpam IP blocklist (refreshed every 3 days)
│   └── ploticus                     ← binary for EasyTimeline
├── notes/
│   ├── .meta.md                     ← documentation system guide

│   └── scheduled-tasks.md
├── images/                          ← gitignored; MediaWiki user uploads
└── sitemap/                         ← gitignored; generated XML sitemaps
```

---

## 11. Personality / Style

- lowercase inline comments; no trailing periods
- link non-obvious references inline: `# not well documented; code reference: <url>`
- personal attribution: `# btw this ones mine -jhn`
- terse - prefer one short comment over a paragraph
- use semicolons or regular dashes (-); never em-dashes
- use american english spelling and grammar
