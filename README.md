# Attu Project Wiki

scripts, configs, and other bits that run the [Attu Project](https://attuproject.org) wiki: a self-hosted MediaWiki 1.44 deployment on Docker.

## architecture

the wiki runs as a multi-container Docker Compose application:

| service | description |
|---|---|
| **mediawiki** | FrankenPHP (Caddy + PHP 8.4) application server on port 8080 |
| **database** | MariaDB 12 |
| **redis** | object cache, session store, parser cache, and job queue backend |
| **scheduler** | cron runner (Supercronic) for background jobs, backups, and maintenance |
| **job-update** | init container that runs DB migrations before the wiki starts |
| **yourls** | URL shortener at `links.attuproject.org` (production only) |

web jobs are fully decoupled from page loads (`$wgJobRunRate = 0`); the scheduler drains the Redis-backed job queue every 2 minutes. all containers log to journald.

## setup

### environment variables

```env
# wiki secrets
ATTU_SECRET_KEY
ATTU_UPGRADE_KEY

# webhooks
ATTU_WIKI_WEBHOOK
ATTU_WIKI_WEBHOOK_ALT
ATTU_SCRIPTS_WEBHOOK
ATTU_WEBHOOK_ICON

# betterstack
TASKS_HEARTBEAT_KEY

# database
ATTU_DB_PASSWORD

# proton (smtp)
SMTP_USERNAME
SMTP_PASSWORD

# cloudflare turnstile (captcha)
TURNSTILE_SITE_KEY
TURNSTILE_SECRET_KEY

# yourls (url shortener)
YOURLS_PASS
```

### building

```bash
BUILD_TYPE='dev' ln -s docker-compose.${BUILD_TYPE}.yml docker-compose.yml
docker compose up -d --build
```

`BUILD_TYPE` controls which compose file is symlinked and toggles dev-specific behavior in the Dockerfile and `LocalSettings.php`.

### dev vs prod

| | dev | prod |
|---|---|---|
| wiki port | `127.0.0.1:6008` | `127.0.0.1:6010` |
| server url | `dev.attuproject.org` | `attuproject.org` |
| database | ephemeral (loaded from backup SQL) | persistent volume |
| redis | ephemeral | periodic save, persistent volume |
| composer | includes dev dependencies | `--no-dev` |
| NovaDiscord | bind-mounted from `./devel/` for live editing | cloned at build time |
| backups | not mounted | `/srv/backups/attu-wiki` |
| scheduled tasks | simulated (printed, not run) | active |
| YOURLS | not included | included (`127.0.0.1:6009`) |

## scheduled tasks

all tasks run via Supercronic in the scheduler container and route through `entry.zsh`, which sends Discord alerts on failure and pings BetterStack on success.

| schedule | task | description |
|---|---|---|
| every 2 min | `task:run-jobs` | drains MediaWiki job queue (3 parallel workers) |
| every 15 min | `task:error-rate-monitor` | reads Caddy access logs from journald, alerts on >1.5% 5xx rate |
| daily 18:00 | `backup:database` | MariaDB dump compressed with bzip2 |
| every 3 days 18:00 | `backup:images` | tar archive of uploaded images (excludes thumbs) |
| 1st of month 20:00 | `chore:bundle-backups` | compacts daily SQL backups into monthly archives |
| daily 00:30 | `chore:clean-upload-stash` | cleans abandoned upload stash files |
| daily 20:00 | `chore:regenerate-sitemap` | regenerates XML sitemap |
| every 3 days 20:00 | `chore:spam-list-refresh` | downloads fresh StopForumSpam IP blocklist |
| every 7 days 20:00 | `chore:templates-refresh` | imports templates from English Wikipedia |

full reference: [notes/features/scheduled-tasks.md](notes/features/scheduled-tasks.md).

## tech

| tool | role |
|---|---|
| FrankenPHP | Caddy-based PHP application server (no separate Nginx/Apache) |
| Supercronic | container-friendly cron daemon, built from source in a Go build stage |
| Redis | object cache, sessions, parser cache, and job queue |
| Citizen | default skin, from StarCitizenTools |
| Cloudflare Turnstile | CAPTCHA for account creation |
| ProtonMail | SMTP provider for wiki notifications |
| discord.sh | formatted Discord webhook alerts for operational events |
| NovaDiscord | custom MediaWiki extension for posting wiki activity to Discord |
| cysystemd + pydantic | used by the error rate monitor to read and parse journald entries |

### custom namespaces

three custom content namespaces: **Story** (100), **Record** (102), and **Dict** (104), each with an associated talk namespace. the default `Talk` namespace is renamed to `Meta`.

### local patches

patches applied at build time to upstream code:

| patch | target |
|---|---|
| `mediawiki-deprecated-sidebar.patch` | MediaWiki core |
| `listfiles-pagination-form.patch` | MediaWiki core (Special:ListFiles next-page) |
| `listfiles-pagination-order.patch` | MediaWiki core (Special:ListFiles next-page) |
| `search-skip-invalid-title.patch` | MediaWiki core (Special:Search precondition) |
| `citizen-viewport.patch` | Citizen skin |

## credits

-[StarCitizenTools/sct-docker-images](https://github.com/StarCitizenTools/sct-docker-images) was used as a basis for this project.

## license

code in this repository is available under the MIT license; see [LICENSE.md](LICENSE.md) for details.

## see also

- [notes/agents.md](notes/agents.md) - agent guide; read first when working in this repo
- [notes/.meta.md](notes/.meta.md) - notes-system conventions
- [notes/features/scheduled-tasks.md](notes/features/scheduled-tasks.md) - full scheduled-task reference
- [notes/style/commit_style.md](notes/style/commit_style.md) - commit message conventions
- [notes/to-do.md](notes/to-do.md) - open work items
