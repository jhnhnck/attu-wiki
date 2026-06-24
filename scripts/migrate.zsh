#!/usr/bin/env zsh
# Attu Project Wiki - host migration orchestrator
# This file is licensed under the MIT License; See LICENSE for full text.
#
# Stages a migration of the attu-wiki stack (prod + dev) from this host to a
# target server. Source enters MediaWiki read-only mode, dumps + rsyncs to
# target, target rotates ATTU_DB_PASSWORD and boots fresh from the dump,
# then `at` schedules the source containers to stop 1 hour after DNS cutover
# (grace window for clients on stale DNS).
#
# usage: ./scripts/migrate.zsh [--dry-run] [--target-host=moon]
#                              [--remote-base=/srv/services] [--ssh-user=USER]
#                              [--dump-dir=/tmp/attu-migration] [--yes]
#                              [--trace] [--overwrite]
#
# By default, dump artifacts (sql.gz, tar.gz) and the LocalSettings.php
# read-only patch are skipped if already present from a prior run. Pass
# --overwrite to force every step to redo its work.
#
# Run from /srv/services/attu-wiki-prod. See notes/runbooks for context.

set -eu -o pipefail

# --- Args ---------------------------------------------------------------
# attu-wiki-prod and attu-wiki-dev are two checkouts of the same git repo
# (prod's .env is even a symlink into the dev tree). Migration always moves
# both — there is no skip-dev mode.
typeset -a DRY_RUN_FLAG YES_FLAG TRACE_FLAG OVERWRITE_FLAG
typeset -a TARGET_HOST_OPT REMOTE_BASE_OPT SSH_USER_OPT DUMP_DIR_OPT
zparseopts -D -E -F -- \
    -dry-run=DRY_RUN_FLAG \
    -target-host:=TARGET_HOST_OPT \
    -remote-base:=REMOTE_BASE_OPT \
    -ssh-user:=SSH_USER_OPT \
    -dump-dir:=DUMP_DIR_OPT \
    -yes=YES_FLAG \
    -trace=TRACE_FLAG \
    -overwrite=OVERWRITE_FLAG

target_host="${TARGET_HOST_OPT[2]:-moon}"
remote_base="${REMOTE_BASE_OPT[2]:-/srv/services}"
ssh_user="${SSH_USER_OPT[2]:-}"
dump_dir="${DUMP_DIR_OPT[2]:-/tmp/attu-migration}"

ssh_target="$target_host"
[[ -n "$ssh_user" ]] && ssh_target="${ssh_user}@${target_host}"

# --- run helper ---------------------------------------------------------
# --trace is opt-in. --dry-run alone does NOT enable shell trace because that
# leaks every variable in .env (tokens, webhooks, DB password) to stdout.
(( ${#TRACE_FLAG} )) && set -x

# Redact known secret values in the dry-run echo. Best-effort; .env hasn't
# been sourced yet at the time `run` is defined, so this re-reads the
# variable each call.
_redact() {
    local s="$*"
    [[ -n "${ATTU_DB_PASSWORD:-}" ]] && s="${s//$ATTU_DB_PASSWORD/<redacted>}"
    print -rP -- "%F{yellow}DRY:%f $s"
}

if (( ${#DRY_RUN_FLAG} )); then
    run() { _redact "$@"; }
else
    run() { "$@"; }
fi

# skip-existing helper. Default behaviour is to skip a destructive op if its
# output artifact already exists from a prior run; --overwrite forces redo.
should_skip() {
    local out="$1"
    (( ${#OVERWRITE_FLAG} )) && return 1
    if [[ -f "$out" ]]; then
        print -P "%F{yellow}skip:%f $out exists (use --overwrite to redo)"
        return 0
    fi
    return 1
}

# --- Sanity checks (read-only; bypass `run`) ----------------------------
script_dir="${0:A:h}"
project_dir="${script_dir:h}"

if [[ "$(realpath "$PWD")" != "$(realpath "$project_dir")" ]]; then
    print -u2 -- "must run from $project_dir (not $PWD)"
    exit 1
fi

if [[ "$(realpath "$project_dir")" != "/srv/services/attu-wiki-prod" ]]; then
    print -u2 -- "expected /srv/services/attu-wiki-prod, got $project_dir"
    exit 1
fi

prod_compose="$project_dir/docker-compose.prod.yml"
dev_dir="/srv/services/attu-wiki-dev"
dev_compose="$dev_dir/docker-compose.dev.yml"

[[ -f "$prod_compose" ]] || { print -u2 -- "missing $prod_compose"; exit 1; }
[[ -f "$dev_compose" ]] || { print -u2 -- "missing $dev_compose"; exit 1; }

for cmd in rsync ssh docker python3 at tar gzip; do
    command -v "$cmd" >/dev/null || { print -u2 -- "missing local: $cmd"; exit 1; }
done

print -P "%F{cyan}[local]%f checking remote tooling on ${ssh_target}"
ssh "$ssh_target" 'for c in rsync docker pnpm python3 tar gzip; do
    command -v "$c" >/dev/null || { echo "missing on target: $c" >&2; exit 1; }
done'

mediawiki_id=$(docker compose -f "$prod_compose" ps -q mediawiki 2>/dev/null || true)
if [[ -z "$mediawiki_id" ]]; then
    print -u2 -- "prod mediawiki container not running; cannot patch LocalSettings or dump DB"
    exit 1
fi

# Disk-space check
print -P "%F{cyan}[local]%f checking remote disk space"
# `du` exits non-zero when it hits unreadable files (e.g. database/ owned by
# the mariadb container's uid). swallow that so pipefail+errexit don't kill
# us — the byte total is still correct.
src_bytes=$({ du --summarize --bytes /srv/services/attu-wiki-prod /srv/services/attu-wiki-dev 2>/dev/null || true; } \
    | awk '{s+=$1} END{print s}')
have_bytes=$(ssh "$ssh_target" "df --block-size=1 --output=avail $remote_base | tail --lines=1 | tr -d ' '")
python3 - "$src_bytes" "$have_bytes" <<'PY'
import sys
src = int(sys.argv[1])
have = int(sys.argv[2])
need = int(src * 1.5) + 4 * 1024**3
if have < need:
    sys.exit(f"insufficient remote space: need ~{need/1e9:.1f} GB, have {have/1e9:.1f} GB")
print(f"disk ok: need ~{need/1e9:.1f} GB, have {have/1e9:.1f} GB")
PY

# --- Confirmation -------------------------------------------------------
if (( ! ${#DRY_RUN_FLAG} && ! ${#YES_FLAG} )); then
    print -P "%F{red}DESTRUCTIVE:%f migrate $(hostname) → ${target_host}:${remote_base}"
    print "  - mediawiki goes read-only on source"
    print "  - source containers will be scheduled to stop in 1h via 'at'"
    print -n "Type 'migrate' to proceed: "
    read confirm
    [[ "$confirm" == "migrate" ]] || { print "Aborted."; exit 1; }
fi

# --- 1. Patch LocalSettings.php on source mediawiki container -----------
# Idempotent: skip if a $wgReadOnly line is already present, unless
# --overwrite is set (which appends a fresh line — duplicates are harmless,
# last assignment wins in PHP).
read_only_msg='server migration in progress; try again in a few minutes'
already_patched=0
if (( ! ${#DRY_RUN_FLAG} )); then
    # grep -c exits 1 on zero matches; swallow it so set -e + pipefail don't
    # kill the script when LocalSettings.php hasn't been patched yet.
    already_patched=$(docker compose -f "$prod_compose" exec -T mediawiki \
        grep --count '^\$wgReadOnly' /app/mediawiki/LocalSettings.php 2>/dev/null \
        | tr -dc '0-9' || true)  # tr -dc = delete complement of '0-9' (keep only digits)
    : "${already_patched:=0}"
fi

if (( already_patched > 0 )) && (( ! ${#OVERWRITE_FLAG} )); then
    print -P "%F{yellow}skip:%f LocalSettings.php already has \$wgReadOnly (use --overwrite to re-append)"
else
    print -P "%F{cyan}[local]%f patching source LocalSettings.php → read-only"
    run docker compose -f "$prod_compose" exec -T mediawiki \
        sh -c "printf '%s\n' \"\\\$wgReadOnly = '$read_only_msg';\" >> /app/mediawiki/LocalSettings.php"  # sh, not zsh
fi

# --- 2. mariadb-dump (live, while read-only) ----------------------------
# Dumps both attu_wiki (the wiki) and attu_links (yourls); both are accessed
# by the same `attu` user with the same password. The --databases flag emits
# `CREATE DATABASE IF NOT EXISTS` + `USE` blocks for each. On target, the
# init script at scripts/migration/db-init.sql pre-creates attu_links and
# grants attu access (mariadb-dump doesn't dump grants), so the load
# proceeds as the attu user without privilege errors.
set -a
source "$project_dir/.env"
set +a
mkdir -p "$dump_dir"

if ! should_skip "$dump_dir/attu-wiki-prod.sql.gz"; then
    print -P "%F{cyan}[local]%f dumping attu_wiki + attu_links"
    # --no-create-db: suppress CREATE DATABASE statements. Both databases
    # already exist on target (attu_wiki via MARIADB_DATABASE, attu_links
    # via the db-init.sql initdb hook), and the `attu` user lacks CREATE
    # privilege globally — without --no-create-db the load would fail at
    # the CREATE DATABASE for attu_links with "Access denied".
    run sh -c "docker compose -f '$prod_compose' exec -T \
        -e MYSQL_PWD='$ATTU_DB_PASSWORD' database \
        mariadb-dump --user=attu --databases attu_wiki attu_links \
            --single-transaction --quick --no-create-db \
      | gzip -9 > '$dump_dir/attu-wiki-prod.sql.gz'"

    if (( ! ${#DRY_RUN_FLAG} )); then
        sql_size=$(stat --format=%s "$dump_dir/attu-wiki-prod.sql.gz" 2>/dev/null || print 0)
        if (( sql_size < 10000 )); then
            print -u2 -- "SQL dump suspiciously small ($sql_size bytes); aborting"
            exit 1
        fi
        print -P "%F{cyan}[local]%f SQL dump: $sql_size bytes"
    fi
fi

# --- 3. Live volume captures --------------------------------------------
if ! should_skip "$dump_dir/redis-data.tar.gz"; then
    # Try a synchronous SAVE. If a BGSAVE is already running (compose has
    # `--save 60 1`, so background snapshots happen automatically), SAVE
    # errors with "Background save already in progress" — wait for it to
    # finish instead. Either way we end up with a consistent dump.rdb on
    # disk before tarring.
    print -P "%F{cyan}[local]%f saving redis state"
    if (( ! ${#DRY_RUN_FLAG} )); then
        if ! docker compose -f "$prod_compose" exec -T redis redis-cli SAVE 2>&1 \
                | grep --quiet '^OK$'; then
            print -P "%F{yellow}[local]%f BGSAVE already running, waiting for it to finish"
            while docker compose -f "$prod_compose" exec -T redis redis-cli INFO persistence \
                    2>/dev/null | grep --quiet '^rdb_bgsave_in_progress:1'; do
                sleep 1
            done
        fi
    else
        run docker compose -f "$prod_compose" exec -T redis redis-cli SAVE
    fi

    # Exclude temp-*.rdb — those are in-flight snapshot files that get
    # atomically renamed to dump.rdb on completion. Including them risks
    # the file vanishing mid-tar (which is what failed on the prior run).
    print -P "%F{cyan}[local]%f tarring redis volume"
    run docker run --rm \
        -v attu-prod_redis-data-prod:/source:ro \
        -v "$dump_dir":/backup \
        alpine:3 \
        tar czf /backup/redis-data.tar.gz --exclude='temp-*.rdb' -C /source .
fi

if ! should_skip "$dump_dir/attu-prod-images.tar.gz"; then
    print -P "%F{cyan}[local]%f tarring prod images"
    run tar czf "$dump_dir/attu-prod-images.tar.gz" -C "$project_dir/images" .
fi

if [[ -d "$dev_dir/images" ]] && ! should_skip "$dump_dir/attu-dev-images.tar.gz"; then
    print -P "%F{cyan}[local]%f tarring dev images"
    run tar czf "$dump_dir/attu-dev-images.tar.gz" -C "$dev_dir/images" .
fi

# --- 4. Rsync project dirs ----------------------------------------------
exclude_file=$(mktemp -t attu-migrate-excludes.XXXXXX)
trap "rm -f '$exclude_file'" EXIT
cat > "$exclude_file" <<'EOF'
.venv/
node_modules/
__pycache__/
*.pyc
.uv-cache/
database/
images/
sitemap/
.git/
.env.bak
.env
.migration-dumps/
EOF

# -aH then --no-owner --no-group: preserve modes/symlinks/hardlinks but let
# the target's ssh user own everything. Neither side runs rsync as root, so
# trying to preserve www-data ownership over SSH-as-jhn would error out for
# every www-data-owned path. Files that the container actually writes (only
# listed_ip_30_all.txt is bind-mounted-writable) get chown'd to www-data on
# target by remote.zsh before containers boot. Skip -A/-X for the same
# reason — preserving ACLs/xattrs needs root privilege both ends.
rsync_flags=(-aH --no-owner --no-group \
    --delete --info=progress2 --exclude-from="$exclude_file")

print -P "%F{cyan}[local]%f rsync prod → ${ssh_target}:${remote_base}/attu-wiki-prod/"
run rsync $rsync_flags "$project_dir/" "${ssh_target}:${remote_base}/attu-wiki-prod/"

print -P "%F{cyan}[local]%f rsync dev → ${ssh_target}:${remote_base}/attu-wiki-dev/"
run rsync $rsync_flags "$dev_dir/" "${ssh_target}:${remote_base}/attu-wiki-dev/"

# .env is excluded from the bulk rsync because remote.zsh rotates it on the
# target — we don't want subsequent re-runs to clobber the rotated value
# with the source's pre-rotation copy. Copy it explicitly only on first run
# (when target has none) or under --overwrite.
target_env_path="${remote_base}/attu-wiki-dev/.env"
if (( ${#OVERWRITE_FLAG} )) \
   || ! ssh "$ssh_target" "test -f '$target_env_path'" 2>/dev/null
then
    print -P "%F{cyan}[local]%f copying .env to target (first run or --overwrite)"
    run rsync -a "$dev_dir/.env" "${ssh_target}:$target_env_path"
else
    print -P "%F{yellow}[local]%f preserving target's .env (already exists)"
fi

# rsync acme.sh cert state (issued certs, account config in .acme.sh/).
print -P "%F{cyan}[local]%f rsync /srv/services/caddy/certificates → ${ssh_target}:/srv/services/caddy/certificates/"
run rsync $rsync_flags \
    /srv/services/caddy/certificates/ "${ssh_target}:/srv/services/caddy/certificates/"

# --- 5. Rsync override templates → final names + dump artifacts ---------
print -P "%F{cyan}[local]%f installing docker-compose.override.yml on target"
run rsync -a "$script_dir/migration/override.prod.yml" \
    "${ssh_target}:${remote_base}/attu-wiki-prod/docker-compose.override.yml"
run rsync -a "$script_dir/migration/override.dev.yml" \
    "${ssh_target}:${remote_base}/attu-wiki-dev/docker-compose.override.yml"

remote_dump_dir="${remote_base}/attu-wiki-prod/.migration-dumps"
print -P "%F{cyan}[local]%f rsync dump artifacts → ${ssh_target}:${remote_dump_dir}/"
run ssh "$ssh_target" "mkdir -p '$remote_dump_dir'"
run rsync -a --info=progress2 "$dump_dir/" "${ssh_target}:${remote_dump_dir}/"

# --- 6. Run remote runner -----------------------------------------------
print -P "%F{cyan}[local]%f executing remote runner on ${ssh_target}"
run ssh "$ssh_target" zsh -s -- \
    "${remote_base}/attu-wiki-prod" \
    "${remote_base}/attu-wiki-dev" \
    "$remote_dump_dir" \
    < "$script_dir/migration/remote.zsh"

# --- 7. DNS pause -------------------------------------------------------
if (( ! ${#DRY_RUN_FLAG} )); then
    print
    print -P "%F{cyan}====== DNS UPDATE ======%f"
    print "Target stack is up at ${target_host}. Update DNS records now."
    print "Source remains read-only and will auto-stop in 1 hour."
    print -n "Press Enter once DNS has been switched: "
    read _
fi

# --- 8. Schedule deferred source stop via `at` --------------------------
print -P "%F{cyan}[local]%f scheduling source container stop in 1 hour"
run sh -c "echo 'docker compose -f $prod_compose stop' | at now + 1 hour"
run sh -c "echo 'docker compose -f $dev_compose stop' | at now + 1 hour"

print
print -P "%F{green}Migration complete.%f Source stops at $(date -d '+1 hour' '+%H:%M %Z')."
print "Cancel scheduled stop with: atq && atrm <jobid>"
