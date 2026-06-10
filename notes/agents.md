root agent guide for the Attu Project wiki repo: rules, architecture, conventions, and pointers to the rest of `notes/`.

## overview

self-hosted MediaWiki 1.44 wiki for the [Attu Project](https://attuproject.org), running on Docker via FrankenPHP (Caddy + PHP 8.4). multi-container Compose stack: `mediawiki`, `database` (MariaDB 12), `redis`, `scheduler` (Supercronic), `job-update` init container; `yourls` in production only. all containers log to journald.

## rules

1. do not edit the rules
1. do not push or deploy without asking first
1. do not create commits without being explicitly asked to
1. do not perform any interactions with Discord without asking
1. do not commit secrets; `.env` is gitignored and holds all credentials
1. do not edit files inside `repos/` directly; they hold patched upstream sources applied at build time
1. do not edit `devel/NovaDiscord/` inside the container; it is a read-only bind mount for live editing on the host
1. all `# noqa` comments must include a valid reason
1. MediaWiki maintenance scripts must run as `www-data` via `sudo --preserve-env -u www-data`; running as root breaks file ownership
1. all containers log to journald; do not redirect logs elsewhere
1. in dev, all scheduled tasks are simulated (print-and-sleep) except `task:run-jobs`, which uses `--allow-dev` in the crontab
1. check the current time at the start of each conversation; if it is past 12:30 AM ET, suggest a natural stopping point before continuing any task

## architecture

| module | role |
|---|---|
| `mediawiki` | FrankenPHP app server (Caddy + PHP 8.4) on port 8080; serves the wiki at `/wiki/$1` |
| `database` | MariaDB 12; dev is ephemeral (loaded from SQL dump), prod uses a persistent volume |
| `redis` | object cache, session store, parser cache, and job queue backend |
| `scheduler` | Supercronic cron runner; dispatches all background tasks via `entry.zsh` |
| `job-update` | init container; runs `update --quick` DB migrations before `mediawiki` and `scheduler` start |
| `yourls` | URL shortener at `links.attuproject.org` (prod only, port 6009) |
| `config/` | Caddyfile, LocalSettings.php, wiki.crontab, robots.txt, yourls config |
| `scripts/` | operational scripts: task dispatcher, backups, chores, error monitor |
| `devel/` | reference checkouts and bind-mounts: `Citizen`, `Drafts`, `MediaWiki`, `NovaDiscord` (bind-mounted into dev), `FamilyTreeEditor` |
| `patches/` | patch files applied to upstream code at build time |
| `files/` | static assets: spam IP list, fonts, favicon, dotfiles served by the wiki |

## configuration

| file | purpose |
|---|---|
| `.env` | all secrets and toggle values; loaded by Docker Compose via `env_file`; never committed |
| `config/LocalSettings.php` | MediaWiki config; reads secrets from `$_ENV`; `$attuDevMode` gates dev-only overrides |
| `config/wiki.crontab` | Supercronic schedule; read at container runtime by the scheduler |
| `config/Caddyfile` | Caddy/FrankenPHP rules; 100M upload limit, 300s max wait, JSON access logs |
| `docker-compose.dev.yml` | dev stack; ephemeral DB and Redis, bind-mounted NovaDiscord, port 6008 |
| `docker-compose.prod.yml` | prod stack; persistent volumes, backup mount, port 6010, includes yourls |
| `docker-compose.yml` | symlink to the active compose file; set via `ln -s docker-compose.${BUILD_TYPE}.yml` |

`BUILD_TYPE` propagation: set in Docker Compose `environment:` (runtime) *and* `build.args` (build-time) so it reaches both `LocalSettings.php` and the Dockerfile stages.

`$attuDevMode` in `LocalSettings.php`: `true` when `BUILD_TYPE=dev`; enables debug logging, disables email, switches webhook to alt URL.

## conventions: shell (zsh)

- `set -eu` at the top of every script
- double-quote all variable expansions in path contexts: `"$APP_HOME/..."`, `"$USER_HOME/..."`
- use `MYSQL_PWD="$ATTU_DB_PASSWORD"` prefix; never `--password=` CLI arg (exposes in `ps aux`)
- pass paths to `sudo zsh -c '...'` as positional args, not interpolated into the string:

  ```zsh
  sudo zsh -c 'mkdir -vp "$1"' -- "$backup_path"
  ```

- all scripts declare `set -eu` internally; callers do not need to pass `-eu` on the command line

## conventions: python

- linter: **ruff** (`pyproject.toml` at repo root); type checker: **basedpyright** (standard mode)
- single quotes for strings, double quotes for docstrings
- google docstring convention
- target python 3.13
- catch `Exception`, not bare `except:`
- run: `ruff check scripts/` and `ruff format scripts/`

## conventions: php

- no linter configured; follow existing MediaWiki conventions
- read all secrets from `$_ENV`; never hardcode credentials
- guard the file top with `if (!defined('MEDIAWIKI')) { exit; }`

## running locally

```bash
# 1. ensure .env exists with all required variables (see README for the list)

# 2. place attu-wiki-backup.sql in repo root (dev DB loads from this on first start)

# 3. symlink compose file
ln -s docker-compose.dev.yml docker-compose.yml

# 4. build and start
docker compose up -d --build
```

wiki available at `https://dev.attuproject.org` (requires reverse proxy on host → port 6008).

dev DB is ephemeral; it reinitializes from `attu-wiki-backup.sql` every fresh start. Redis is also ephemeral in dev. NovaDiscord is bind-mounted from `./devel/NovaDiscord/` (read-only inside containers) for live editing.

to rebuild after config changes:

```bash
docker compose up -d --build --force-recreate
```

## patterns and pitfalls

1. **`task:run-jobs` is the only task that runs in dev**: it uses `--allow-dev` in `wiki.crontab`; all other tasks simulate (print-and-sleep) unless you pass `--allow-dev` manually
1. **DB password must use `MYSQL_PWD=` env prefix**: not `--password=`; the CLI arg is visible in `ps aux`
1. **`BUILD_TYPE` must appear in both `environment:` and `build.args`**: missing from either breaks runtime or build-time behaviour
1. **MediaWiki maintenance scripts need `sudo --preserve-env -u www-data`**: running as root corrupts upload directory ownership
1. **session cookie is `brch_session`**: was `brch_sesssion` (triple s) before the 2026-02-09 audit; changing it invalidates existing sessions
1. **`$wgJobRunRate = 0`**: jobs never run on page load; the scheduler drains the queue every 2 minutes via `task:run-jobs`
1. **custom namespace ids**: Story=100/101, Record=102/103, Dict=104/105; the Talk namespace is renamed to "Meta" (alias `Talk` preserved for compatibility)
1. **`job-update` must complete successfully** before `mediawiki` or `scheduler` start; if it fails, the wiki will not come up; check `docker compose logs job-update`
1. **scheduler mounts journald sockets read-only** (`/run/log/journal`, `/var/log/journal`, `/run/systemd/journal/socket`, `/etc/machine-id`) so `attu_error_rate.py` can read Caddy access logs via `cysystemd`
1. **`discord.sh` is SHA256-verified at build time**: used by wiki scripts (not by NovaDiscord, which uses `HttpRequestFactory`); if upgrading the binary, update the checksum in `mediawiki.Dockerfile`
1. **`PageMoveComplete` not `TitleMoveComplete`** is the correct hook name for NovaDiscord; using the wrong name silently disables the hook without errors
1. **Wikipedia template imports use username prefix `'w'`**: maintain this when adding new templates to `templates_refresh.zsh`
1. **certbot renewal uses hardcoded GID `976` for `chown :caddy`**: the `caddy` group does not exist inside the Debian container, so `certbot_renew.zsh` uses the numeric GID from the host; if it changes, update the script. certbot volume mounts (`/srv/services/certbot/config`, `cloudflare.ini`) are prod-only; dev simulates the task

## reference notes

`notes/style/`: conventions

- [`notes/style/commit_style.md`](style/commit_style.md) - commit message format, types, and tone

`notes/features/`: feature and system docs

- [`notes/features/scheduled-tasks.md`](features/scheduled-tasks.md) - full task table, dispatcher pattern, dev mode, how to add or run a task

`notes/issues/`: bug reports and post-mortems

- [`notes/issues/mediawiki-search-precondition.md`](issues/mediawiki-search-precondition.md) - Special:Search crash from invalid Title rows
- [`notes/issues/drafts-stash-not-the-cause.md`](issues/drafts-stash-not-the-cause.md) - root cause of the NWE "no stashed content found" 412

`notes/`

- [`notes/.meta.md`](.meta.md) - notes-system conventions
- [`notes/to-do.md`](to-do.md) - open work items
- [`notes/.template.to-do.md`](.template.to-do.md) - starter template for new to-do lists

NovaDiscord extension (in `devel/NovaDiscord/`)

- [`devel/NovaDiscord/notes/agents.md`](../devel/NovaDiscord/notes/agents.md) - extension dev guide (class architecture, coding conventions, testing)
- [`devel/NovaDiscord/notes/features/novadiscord.md`](../devel/NovaDiscord/notes/features/novadiscord.md) - wiki integration config (LocalSettings.php, config reference, hook catalog)

## file and directory layout

```txt
attu-wiki-dev/
├── notes/agents.md                  ← this file
├── LICENSE.md
├── README.md
├── mediawiki.Dockerfile             ← multi-stage: php-base, mediawiki, scheduler
├── docker-compose.dev.yml
├── docker-compose.prod.yml
├── docker-compose.yml               ← symlink to active compose file
├── pyproject.toml                   ← ruff + basedpyright config
├── attu-wiki-backup.sql             ← gitignored; SQL dump for dev DB init
├── config/
│   ├── Caddyfile                    ← FrankenPHP/Caddy web server rules
│   ├── Caddyfile.trees              ← dev-only trees route snippet (imported via glob)
│   ├── LocalSettings.php            ← MediaWiki config; reads secrets from $_ENV
│   ├── robots.txt
│   ├── wiki.crontab                 ← Supercronic schedule
│   └── yourls/                      ← YOURLS config (prod only)
├── scripts/
│   ├── entry.zsh                    ← container entrypoint and task dispatcher
│   ├── requirements.txt             ← Python deps for scripts
│   ├── migrate.zsh                  ← host migration orchestrator (source-side)
│   ├── migration/
│   │   ├── override.dev.yml         ← compose override applied on target (dev stack)
│   │   ├── override.prod.yml        ← compose override applied on target (prod stack)
│   │   └── remote.zsh               ← target-side runner invoked by migrate.zsh
│   ├── backups/
│   │   ├── wiki_database_backup.zsh
│   │   └── wiki_images_backup.zsh
│   ├── chores/
│   │   ├── bundle_db_backups.zsh
│   │   ├── certbot_renew.zsh        ← renews all LE certs; uses certbot config outside repo
│   │   ├── spam_list_refresh.zsh
│   │   └── templates_refresh.zsh
│   ├── misc/
│   │   ├── bundle_backups.zsh       ← manual backup compaction tool
│   │   └── rotate_env_secrets.zsh   ← rotates ATTU_DB_PASSWORD; writes .env.bak
│   └── tasks/
│       └── attu_error_rate.py       ← reads journald, calculates Caddy 5xx rate, alerts Discord
├── devel/
│   ├── Citizen/                     ← reference checkout of Citizen skin (patched at build)
│   ├── Drafts/                      ← reference checkout of Drafts extension
│   ├── FamilyTreeEditor/            ← active dev; included into dev stack via include:
│   ├── MediaWiki/                   ← reference checkout of MediaWiki core
│   └── NovaDiscord/                 ← custom extension; bind-mounted :ro in dev
│       └── notes/                   ← extension dev notes; agents.md is the primary guide
├── patches/
│   ├── citizen-viewport.patch
│   ├── listfiles-pagination-form.patch
│   ├── listfiles-pagination-order.patch
│   ├── mediawiki-deprecated-sidebar.patch
│   └── search-skip-invalid-title.patch
├── files/
│   ├── assets/                      ← favicon and other static assets
│   ├── dotfiles/                    ← .well-known and similar served files
│   ├── freefont-ttf/                ← fonts for EasyTimeline extension
│   ├── listed_ip_30_all.txt         ← StopForumSpam IP blocklist (refreshed every 3 days)
│   └── ploticus                     ← binary for EasyTimeline (planned: phase 3 reorg)
├── notes/
│   ├── agents.md                    ← this file
│   ├── .meta.md                     ← documentation system guide
│   ├── .template.to-do.md           ← to-do list template
│   ├── to-do.md                     ← open items
│   ├── style/
│   │   └── commit_style.md
│   ├── features/
│   │   └── scheduled-tasks.md
│   ├── issues/
│   │   ├── mediawiki-search-precondition.md
│   │   └── drafts-stash-not-the-cause.md
│   └── plans/
│       └── wiki-root-reorg.md
├── images/                          ← gitignored; MediaWiki user uploads
└── sitemap/                         ← gitignored; generated XML sitemaps
```

## personality and style

- lowercase inline comments; no trailing periods
- link non-obvious references inline: `# not well documented; code reference: <url>`
- personal attribution: `# btw this ones mine -jhn`
- terse; prefer one short comment over a paragraph; prefer brief statements over long explanations
- use semicolons or regular dashes (`-`); never em-dashes
- do not include any extraneous punctuation
- use american english spelling and grammar
- use spaces for indentation always; avoid formats that require tabs

## see also

- [.meta.md](.meta.md) - notes-system conventions
- [to-do.md](to-do.md) - open work items
- [features/scheduled-tasks.md](features/scheduled-tasks.md) - scheduled task reference
- [style/commit_style.md](style/commit_style.md) - commit message conventions

---

## metadata

```yaml
last_updated: 24 May 2026
```
