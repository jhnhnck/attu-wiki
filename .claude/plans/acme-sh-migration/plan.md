# Plan: Switch Cert Renewal from Certbot to acme.sh

## Context

Certbot (bind-mounted from the host into the scheduler container) began failing
Cloudflare DNS-01 authentication with a connection error despite valid credentials.
The root cause is Certbot's reliance on the host's Python environment and network
stack, which is fragile in a containerised setup. Switching to acme.sh — a pure
shell ACME client installed directly inside the container — eliminates the host
dependency and is a better fit for headless Docker cert renewal.

## Goals

- [ ] acme.sh installed inside the scheduler container (Dockerfile)
- [ ] Cloudflare DNS-01 renewal for all three domains: `attuproject.org`,
      `dev.attuproject.org`, `links.attuproject.org` (single multi-domain cert)
- [ ] Certs written to `/srv/services/certificates/` bind mount
- [ ] acme.sh state persisted at `/srv/services/certificates/.acme.sh/` so
      account and domain config survive container restarts
- [ ] Cloudflare credentials moved from `cloudflare.ini` mount to `.env`
      (`CF_Token`, `ACME_EMAIL`)
- [ ] Certbot bind mounts and old script removed

## Out of scope

- Caddy container / Caddyfile changes — **but see coordination note below**
- acme.sh daemon mode (supercronic handles scheduling)
- Docker socket hooks, Proxmox hooks

## Coordination dependency (not in scope but deploy-blocking)

Caddy currently reads certs from `/srv/services/certbot/config/live/attuproject.org/`.
After this migration, it must be updated to read from
`/srv/services/certificates/attuproject.org/`. This Caddy reconfiguration is out of
scope here but **must land before the certbot mounts are removed**, or Caddy loses its
cert source. Phase 2 (cleanup) should not be deployed until this is coordinated.

## Constraints

- GID 976 (caddy group on the host) must still own/read the `.pem` files after
  renewal — same `chown :976` + `chmod g+r` pattern as `certbot_renew.zsh`
- acme.sh default CA changed to ZeroSSL; pass `--server letsencrypt` explicitly on
  every command instead of relying on default
- acme.sh installs via a pinned release URL + checksum (same pattern as `discord.sh`
  in the scheduler stage — no unpinned `curl | sh`)
- Single multi-SAN cert (one cert, primary domain `attuproject.org`, all three as
  SANs) — installed once; mirrors the certbot layout Caddy expects

---

## Phase 0 — Walking skeleton: install + staging cert ✅ / 🔲

**Goal:** prove the full chain works — Dockerfile build → acme.sh binary →
Cloudflare DNS-01 via `CF_Token` env var → all three SANs issued → cert files
installed on bind mount — using the staging CA so production rate limits aren't
consumed. Also validates state persistence across a container restart.

**Files touched:**
- `mediawiki.Dockerfile` — add acme.sh install to the `scheduler` stage
- `scripts/chores/acme_renew.zsh` — new script, staging CA, all three domains
- `docker-compose.prod.yml` — add `/srv/services/certificates/` writable mount
- `.env` — add `CF_Token`, `ACME_EMAIL`

### Dockerfile change (scheduler stage, after existing discord.sh block)

Pin to a specific acme.sh release and verify checksum (find current tag + SHA at
`github.com/acmesh-official/acme.sh/releases`):

```dockerfile
RUN sudo curl -sSL -o /usr/local/bin/acme.sh \
        https://raw.githubusercontent.com/acmesh-official/acme.sh/<TAG>/acme.sh; \
    echo '<SHA256>  /usr/local/bin/acme.sh' | sha256sum -c; \
    sudo chmod a+x /usr/local/bin/acme.sh
```

acme.sh is a single self-contained shell script — copying the script only (not the
installer) avoids modifying `$HOME` at build time; all persistent state goes to the
bind-mounted `ACME_HOME` at runtime.

### compose change

Replace the two certbot lines in `scheduler.volumes`:
```yaml
# remove:
- /srv/services/certbot/config:/srv/services/certbot/config
- /srv/services/certbot/cloudflare.ini:/srv/services/certbot/cloudflare.ini:ro
# add:
- /srv/services/certificates:/srv/services/certificates
```

### Skeleton renewal script (`scripts/chores/acme_renew.zsh`)

```zsh
#!/usr/bin/env zsh
typeset -r acme_home='/srv/services/certificates/.acme.sh'
typeset -r cert_out='/srv/services/certificates'

# Staging CA — proves multi-SAN issuance + install without touching production quota
ACME_HOME="${acme_home}" CF_Token="${CF_Token}" \
acme.sh --issue --dns dns_cf \
    --server letsencrypt_test \
    -d attuproject.org \
    -d dev.attuproject.org \
    -d links.attuproject.org

ACME_HOME="${acme_home}" \
acme.sh --install-cert -d attuproject.org \
    --cert-file      "${cert_out}/attuproject.org/cert.pem" \
    --key-file       "${cert_out}/attuproject.org/key.pem" \
    --fullchain-file "${cert_out}/attuproject.org/fullchain.pem" \
    --ca-file        "${cert_out}/attuproject.org/chain.pem"
```

**DoD:**
- `openssl x509 -in /srv/services/certificates/attuproject.org/fullchain.pem -text -noout | grep -A3 'Subject Alternative'` shows all three domains in a staging cert
- Restart the container; run `acme_renew.zsh` again; confirm it exits 2 ("not due") — state persisted across restart
- Pivot criterion: if staging DNS-01 challenge fails, investigate CF_Token scoping before proceeding

---

## Phase 1 — Full implementation 🔲

**Goal:** switch from staging CA to production, add GID fix, rename chore in
dispatcher and crontab.

**Files touched:**
- `scripts/chores/acme_renew.zsh` — finalised
- `scripts/entry.zsh` — rename `chore:certbot-renew` → `chore:acme-renew` (line 125)
- `config/wiki.crontab` — rename chore key (line 24)

### Final `acme_renew.zsh`

```zsh
#!/usr/bin/env zsh
typeset -r acme_home='/srv/services/certificates/.acme.sh'
typeset -r cert_out='/srv/services/certificates'

# Issue or renew; exit 2 = not yet due, which is fine
ACME_HOME="${acme_home}" CF_Token="${CF_Token}" \
acme.sh --issue --dns dns_cf \
    --server letsencrypt \
    -d attuproject.org \
    -d dev.attuproject.org \
    -d links.attuproject.org \
    || (( $? == 2 ))

# Single cert (all SANs), installed to primary domain directory
ACME_HOME="${acme_home}" \
acme.sh --install-cert -d attuproject.org \
    --cert-file      "${cert_out}/attuproject.org/cert.pem" \
    --key-file       "${cert_out}/attuproject.org/key.pem" \
    --fullchain-file "${cert_out}/attuproject.org/fullchain.pem" \
    --ca-file        "${cert_out}/attuproject.org/chain.pem"

# GID 976 = caddy group on host; verify with `getent group caddy` if host changes
find "${cert_out}" -type f -name '*.pem' \
    -exec sudo chown --changes :976 {} \+ \
    -exec sudo chmod --changes g+r {} \+
```

**DoD:**
- `openssl x509 -in /srv/services/certificates/attuproject.org/fullchain.pem -text -noout | grep -A3 'Subject Alternative'` lists all three domains (production cert)
- BetterStack heartbeat fires after manual `entry.zsh "chore:acme-renew" --allow-dev`

---

## Phase 2 — Cleanup 🔲

**Prerequisite:** Caddy reconfiguration to read from new cert path is deployed
before removing certbot mounts (see coordination dependency above).

**Files touched:**
- `docker-compose.prod.yml` — certbot mounts removed in Phase 0; verify clean
- `scripts/migration/override.prod.yml` — same certbot mounts (lines 40-41); update
- `scripts/migrate.zsh` — rsyncs `/srv/services/certbot/` to remote (~line 295); update to `certificates/`
- `scripts/chores/certbot_renew.zsh` — delete
- `notes/features/scheduled-tasks.md` — update chore row
- `notes/agents.md` — update GID 976 caveat and architecture diagram (~lines 120, 181)

---

## Verification

1. `docker compose -f docker-compose.prod.yml build scheduler` — clean build
2. Exec into scheduler: `acme.sh --version` (no ACME_HOME needed; just confirms binary)
3. Manual trigger: `zsh entry.zsh "chore:acme-renew" --allow-dev`; confirm heartbeat
4. `openssl x509 -in /srv/services/certificates/attuproject.org/fullchain.pem -text -noout | grep -A3 'Subject Alternative'` — all three domains
5. Restart container; re-run — exit 2 (not due), not a fresh issuance
6. After Caddy reconfiguration: HTTPS works externally for all three domains
7. Automated 3:00 AM cron run completes; BetterStack records heartbeat

---

## Files changed

| File | Change |
|---|---|
| `mediawiki.Dockerfile` | Add pinned acme.sh install to scheduler stage |
| `scripts/chores/certbot_renew.zsh` | Delete |
| `scripts/chores/acme_renew.zsh` | New |
| `scripts/entry.zsh` | Rename chore key + script path (line 125) |
| `config/wiki.crontab` | Rename chore key (line 24) |
| `docker-compose.prod.yml` | Swap certbot mounts for certificates mount |
| `scripts/migration/override.prod.yml` | Same mount swap |
| `scripts/migrate.zsh` | Update rsync source certbot/ → certificates/ |
| `.env` | Add `CF_Token`, `ACME_EMAIL` |
| `notes/features/scheduled-tasks.md` | Update chore row |
| `notes/agents.md` | Update GID 976 caveat + architecture diagram |
