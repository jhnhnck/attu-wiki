#!/usr/bin/env zsh
# Attu Project Wiki - migration target-side runner
# This file is licensed under the MIT License; See LICENSE for full text.
#
# Invoked by scripts/migrate.zsh via `ssh "$host" zsh -s -- ARGS < this-file`.
# Runs on the *target* server. Recreates dependency dirs (uv/pnpm), rotates
# ATTU_DB_PASSWORD in the rsynced .env so the fresh DB initializes with a
# new credential, creates and loads named volumes, boots prod (DB → load SQL
# → rest), refreshes dev's init SQL with the fresh dump and boots dev, then
# runs a one-shot sitemap regeneration.

set -eu -o pipefail

if (( $# != 3 )); then
    print -u2 -- "usage: remote.zsh <prod-dir> <dev-dir> <dump-dir>"
    exit 2
fi

prod_dir="$1"
dev_dir="$2"
dump_dir="$3"

print -P "%F{cyan}[remote]%f prod=$prod_dir dev=$dev_dir dump=$dump_dir"

# --- Restore www-data ownership on the few paths that need it
# Source rsync dropped ownership (jhn lacks privilege to set www-data over
# SSH). Per the source-side audit, only paths under prod/files/ are
# www-data on source. The only one the running container actively writes
# is listed_ip_30_all.txt (spam-list chore overwrites it daily) — that one
# strictly *needs* the container's UID; the others are tidied for parity.
#
# Using numeric 33:33: target host doesn't have a www-data user defined,
# but the container's internal uid is 33 — the bind mount maps by uid.
print -P "%F{cyan}[remote]%f restoring uid 33 (www-data) ownership on prod/files paths"
www_data_paths=(
    "$prod_dir/files/assets"
    "$prod_dir/files/well-known"
    "$prod_dir/files/listed_ip_30_all.txt"
)
for p in "${www_data_paths[@]}"; do
    [[ -e "$p" ]] && sudo chown --recursive 33:33 "$p"
done

# --- Set up package deps for the two devel/ repos that need it.
# NovaDiscord (PHP, composer) and FamilyTreeEditor (JS, pnpm workspace) are
# the only devel/ repos with package managers that need running on a fresh
# checkout. Other devel/ repos (Citizen, Drafts, MediaWiki) are pure-PHP and
# don't need install steps. Other host paths (scripts/.venv, certbot/.venv,
# project-root .venv) are intentionally untouched here — they're either set
# up out-of-band on target or not actually used at runtime.
#
# composer is run via the composer:2 docker image so we don't need it
# installed on the host. The --user flag matches the SSH user so vendor/
# files don't end up root-owned.
print -P "%F{cyan}[remote]%f setting up devel/ package deps"

novadiscord="$dev_dir/devel/NovaDiscord"
if [[ -d "$novadiscord" && -f "$novadiscord/composer.json" ]]; then
    print -P "%F{cyan}[remote]%f composer install in $novadiscord"
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$novadiscord":/app -w /app \
        composer:2 install --no-interaction
fi

familytree="$dev_dir/devel/FamilyTreeEditor"
if [[ -d "$familytree" && -f "$familytree/pnpm-lock.yaml" ]]; then
    print -P "%F{cyan}[remote]%f pnpm install in $familytree"
    (cd "$familytree" && pnpm install --frozen-lockfile)
fi

# --- Rotate ATTU_DB_PASSWORD on target before any container boots — but
# only on the very first migration run. Once the attu-prod-database volume
# has been initialized, MariaDB's first-run user creation is a no-op on
# subsequent boots (volume isn't empty), so re-rotating .env would silently
# desync .env from what the running DB actually has. Detect the volume's
# init state and skip rotation when it's already populated.
db_init_marker_present=0
if docker volume inspect attu-prod-database >/dev/null 2>&1; then
    if docker run --rm -v attu-prod-database:/v alpine:3 \
            sh -c '[ -d /v/mysql ]' 2>/dev/null; then
        db_init_marker_present=1
    fi
fi

if (( db_init_marker_present )); then
    print -P "%F{yellow}[remote]%f db volume already initialized; preserving current .env (skipping rotation)"
else
    print -P "%F{cyan}[remote]%f rotating ATTU_DB_PASSWORD in $dev_dir/.env"
    rm --force "$dev_dir/.env.bak"
    zsh "$dev_dir/scripts/misc/rotate_env_secrets.zsh" </dev/null
fi

# prod/.env is a symlink to dev/.env on source; rsync excluded .env so the
# symlink was dropped. Recreate it so prod compose can find its env file.
if [[ ! -e "$prod_dir/.env" ]]; then
    print -P "%F{cyan}[remote]%f creating $prod_dir/.env symlink → $dev_dir/.env"
    ln -sf "$dev_dir/.env" "$prod_dir/.env"
fi

# --- Create + load named volumes
print -P "%F{cyan}[remote]%f creating named volumes"
docker volume create attu-prod-database >/dev/null
docker volume create attu-prod-images >/dev/null
docker volume create attu-prod-redis-data >/dev/null
docker volume create attu-dev-images >/dev/null

restore_into_volume() {
    local vol="$1" archive="$2"
    if [[ ! -f "$archive" ]]; then
        print -u2 -- "missing archive: $archive"
        return 1
    fi
    print -P "%F{cyan}[remote]%f restoring $archive → $vol"
    docker run --rm \
        -v "$vol":/dest \
        -v "$dump_dir":/backup:ro \
        alpine:3 \
        sh -c "tar xzf /backup/$(basename "$archive") -C /dest"
}

restore_into_volume attu-prod-redis-data "$dump_dir/redis-data.tar.gz"
restore_into_volume attu-prod-images     "$dump_dir/attu-prod-images.tar.gz"
if [[ -f "$dump_dir/attu-dev-images.tar.gz" ]]; then
    restore_into_volume attu-dev-images "$dump_dir/attu-dev-images.tar.gz"
fi

# --- Boot prod database alone, wait healthy
# Both -f flags are required: docker compose only auto-merges
# docker-compose.override.yml when no -f is given. Without the override the
# bind mount `./database` shadows the named volume and the !override never
# applies. MARIADB_PASSWORD is substituted from .env at compose time, so
# first-init creates `attu`@'%' with the freshly-rotated password.
prod_compose_args=(-f docker-compose.prod.yml -f docker-compose.override.yml)
dev_compose_args=(-f docker-compose.dev.yml -f docker-compose.override.yml)

print -P "%F{cyan}[remote]%f booting prod database (waiting for healthy)"
cd "$prod_dir"
docker compose "${prod_compose_args[@]}" up -d --wait --wait-timeout 180 database

# --- Load SQL dump
# attu has only `attu`@'%' (no localhost grant) so we force TCP via
# --host=127.0.0.1; '%' matches loopback TCP but not unix-socket connections.
# MARIADB_RANDOM_ROOT_PASSWORD=true makes root unreachable from us, so we
# can't ALTER USER as root — we rely on first-init having set the password.
print -P "%F{cyan}[remote]%f loading SQL dump into prod database"
set -a
source "$prod_dir/.env"
set +a
gunzip -c "$dump_dir/attu-wiki-prod.sql.gz" \
    | docker compose "${prod_compose_args[@]}" exec -T \
        -e MYSQL_PWD="$ATTU_DB_PASSWORD" database \
        mariadb --user=attu --host=127.0.0.1 attu_wiki

# --- Boot rest of prod
print -P "%F{cyan}[remote]%f booting rest of prod stack (waiting for healthy)"
docker compose "${prod_compose_args[@]}" up -d --wait --wait-timeout 300

# --- Refresh dev init SQL with fresh prod dump, then boot dev
if [[ -f "$dev_dir/docker-compose.dev.yml" ]]; then
    print -P "%F{cyan}[remote]%f seeding dev init SQL with fresh prod dump"
    gunzip -c "$dump_dir/attu-wiki-prod.sql.gz" > "$dev_dir/attu-wiki-backup.sql"
    print -P "%F{cyan}[remote]%f booting dev stack (waiting for healthy)"
    cd "$dev_dir"
    docker compose "${dev_compose_args[@]}" up -d --wait --wait-timeout 300
fi

# --- One-shot sitemap regeneration
print -P "%F{cyan}[remote]%f running chore:regenerate-sitemap"
cd "$prod_dir"
docker compose "${prod_compose_args[@]}" run --rm \
    --entrypoint zsh scheduler \
    /app/scripts/entry.zsh chore:regenerate-sitemap

print -P "%F{green}[remote]%f migration target steps complete"
