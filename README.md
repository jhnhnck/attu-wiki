# Attu Project Wiki

This repository includes the scripts, configs, and other bits that run the [Attu Project](https://attuproject.org) wiki.

## Setup

Below is a selection of *vague* instructions on how to get set the wiki built and running (mostly for me, but help yourself)

.env
```env
# Wiki Secrets
ATTU_SECRET_KEY
ATTU_UPGRADE_KEY

# Webooks
ATTU_WIKI_WEBHOOK
ATTU_WIKI_WEBHOOK_ALT
ATTU_SCRIPTS_WEBHOOK

# BetterStack
BACKUPS_HEARTBEAT_KEY
UPDATES_HEARTBEAT_KEY

# Database
ATTU_DB_PASSWORD

# Proton
SMTP_USERNAME
SMTP_PASSWORD

# Cloudflare
TURNSTILE_SITE_KEY
TURNSTILE_SECRET_KEY

# Yourls (URL Shortener)
YOURLS_PASS

# SSH
ATTU_SSH_PASSWORD
```

```
BUILD_TYPE=
$ ln -s docker-compose.${BUILD_TYPE}.yml docker-compose.yml
$ docker compose up -d --build
```

### Scripts

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
```

## Credits

This repository took heavy inspiration from [StarCitizenTools/sct-docker-images](https://github.com/StarCitizenTools/sct-docker-images),
although much has been gutted, modified, and refactored to fit our needs and scale.

## License

The code found within this repository is available under the MIT license. You can [see here](LICENSE) for more information.
