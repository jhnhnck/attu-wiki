# Attu Project Wiki

This repository includes the scripts, configs, and other bits that run the [Attu Project](https://attuproject.org) wiki — a self-hosted MediaWiki 1.44 deployment on Docker.

## Architecture

The wiki runs as a multi-container Docker Compose application:

| Service | Description |
|---|---|
| **mediawiki** | FrankenPHP (Caddy + PHP 8.4) application server on port 8080 |
| **database** | MariaDB 12 |
| **redis** | Object cache, session store, parser cache, and job queue backend |
| **scheduler** | Cron runner (Supercronic) for background jobs, backups, and maintenance |
| **job-update** | Init container that runs DB migrations before the wiki starts |
| **yourls** | URL shortener at `links.attuproject.org` (production only) |

Web jobs are fully decoupled from page loads (`$wgJobRunRate = 0`) — the scheduler drains the Redis-backed job queue every 2 minutes. All containers log to journald.

## Setup

### Environment Variables

```env
# Wiki Secrets
ATTU_SECRET_KEY
ATTU_UPGRADE_KEY

# Webhooks
ATTU_WIKI_WEBHOOK
ATTU_WIKI_WEBHOOK_ALT
ATTU_SCRIPTS_WEBHOOK
ATTU_WEBHOOK_ICON

# BetterStack
TASKS_HEARTBEAT_KEY

# Database
ATTU_DB_PASSWORD

# Proton (SMTP)
SMTP_USERNAME
SMTP_PASSWORD

# Cloudflare Turnstile (CAPTCHA)
TURNSTILE_SITE_KEY
TURNSTILE_SECRET_KEY

# Yourls (URL Shortener)
YOURLS_PASS
```

### Building

```bash
BUILD_TYPE='dev' ln -s docker-compose.${BUILD_TYPE}.yml docker-compose.yml
docker compose up -d --build
```

The `BUILD_TYPE` variable controls which compose file is symlinked and toggles dev-specific behavior in the Dockerfile and `LocalSettings.php`.

### Dev vs. Production

| | Dev | Prod |
|---|---|---|
| Wiki port | `127.0.0.1:6008` | `127.0.0.1:6010` |
| Server URL | `dev.attuproject.org` | `attuproject.org` |
| Database | Ephemeral (loaded from backup SQL) | Persistent volume |
| Redis | Ephemeral | Periodic save, persistent volume |
| Composer | Includes dev dependencies | `--no-dev` |
| NovaDiscord | Bind-mounted from `./devel/` for live editing | Cloned at build time |
| Backups | Not mounted | `/srv/backups/attu-wiki` |
| Scheduled tasks | Simulated (printed, not run) | Active |
| YOURLS | Not included | Included (`127.0.0.1:6009`) |

## Scheduled Tasks

All tasks run via Supercronic in the scheduler container and route through `attu_tasks.zsh`, which sends Discord alerts on failure and pings BetterStack on success.

| Schedule | Task | Description |
|---|---|---|
| Every 2 min | `task:run-jobs` | Drains MediaWiki job queue (3 parallel workers) |
| Every 15 min | `task:error-rate-monitor` | Reads Caddy access logs from journald, alerts on >1.5% 5xx rate |
| Daily 18:00 | `backup:database` | MariaDB dump compressed with bzip2 |
| Every 3 days 18:00 | `backup:images` | Tar archive of uploaded images (excludes thumbs) |
| 1st of month 20:00 | `chore:bundle-backups` | Compacts daily SQL backups into monthly archives |
| Daily 00:30 | `chore:clean-upload-stash` | Cleans abandoned upload stash files |
| Daily 20:00 | `chore:regenerate-sitemap` | Regenerates XML sitemap |
| Every 3 days 20:00 | `chore:spam-list-refresh` | Downloads fresh StopForumSpam IP blocklist |
| Every 7 days 20:00 | `chore:templates-refresh` | Imports templates from English Wikipedia |

## Tech

- **FrankenPHP** — Caddy-based PHP application server (no separate Nginx/Apache)
- **Supercronic** — Container-friendly cron daemon, built from source in a Go build stage
- **Redis** — Handles object cache, sessions, parser cache, and job queue
- **Citizen** — Default skin, from StarCitizenTools
- **Cloudflare Turnstile** — CAPTCHA for account creation
- **ProtonMail** — SMTP provider for wiki notifications
- **discord.sh** — Formatted Discord webhook alerts for operational events
- **NovaDiscord** — Custom MediaWiki extension for posting wiki activity to Discord
- **cysystemd + pydantic** — Used by the error rate monitor to read and parse journald entries

### Custom Namespaces

The wiki defines three custom content namespaces: **Story** (100), **Record** (102), and **Dict** (104), each with an associated talk namespace. The default `Talk` namespace is renamed to `Meta`.

### Local Patches

A small set of patches are applied at build time to upstream code:

- `mediawiki-deprecated-sidebar.patch` — MediaWiki core
- `citizen-viewport.patch` — Citizen skin
- `jobrunner-e_strict.patch` — Job runner

## Credits

This repository took heavy inspiration from [StarCitizenTools/sct-docker-images](https://github.com/StarCitizenTools/sct-docker-images),
although much has been gutted, modified, and refactored to fit our needs and scale.

## License

The code found within this repository is available under the MIT license. You can [see here](LICENSE) for more information.
