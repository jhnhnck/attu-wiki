#!/usr/bin/env zsh
# Attu Project Wiki - rotate ATTU_DB_PASSWORD in .env
# This file is licensed under the MIT License; See LICENSE for full text.
#
# rotates ATTU_DB_PASSWORD in the canonical .env (the dev worktree's copy;
# prod's .env is a symlink to it). other secrets (SMTP, Discord webhooks)
# were rotated recently and aren't touched by this script.
#
# usage:
#   zsh scripts/misc/rotate_env_secrets.zsh
#
# leaves .env.bak next to .env for one-step rollback. delete .env.bak
# manually after the migration target is confirmed healthy.

set -eu

script_dir="${0:A:h}"
project_dir="${script_dir:h:h}"
env_file="$project_dir/.env"

# resolve symlinks so we always edit the real file. prod's .env is a symlink
# to the dev worktree's .env; both should resolve to /srv/services/attu-wiki-dev/.env.
real_env="$(realpath "$env_file")"
expected='/srv/services/attu-wiki-dev/.env'

if [[ "$real_env" != "$expected" ]]; then
    print -u2 -- "refusing to rotate: realpath \$.env = $real_env"
    print -u2 -- "expected: $expected"
    exit 1
fi

[[ -f "$real_env" ]] || { print -u2 -- "missing $real_env"; exit 1; }

if [[ -e "$real_env.bak" ]]; then
    print -n "$real_env.bak already exists; overwrite? [y/N] "
    read confirm
    [[ "$confirm" == [yY] ]] || { print "aborted."; exit 1; }
fi

cp --preserve "$real_env" "$real_env.bak"
chmod 600 "$real_env.bak"

new_pw=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
[[ -n "$new_pw" ]] || { print -u2 -- "secret generation failed"; exit 1; }

# in-place rewrite via temp file to preserve symlink target identity
tmp=$(mktemp --tmpdir="$(dirname "$real_env")" .env.new.XXXXXX)
trap 'rm -f "$tmp"' EXIT
sed "s|^ATTU_DB_PASSWORD=.*|ATTU_DB_PASSWORD=\"$new_pw\"|" "$real_env" > "$tmp"

# verify the line landed
if ! grep --quiet "^ATTU_DB_PASSWORD=\"$new_pw\"$" "$tmp"; then
    print -u2 -- "sed rewrite failed; check .env format"
    exit 1
fi

mv "$tmp" "$real_env"
chmod 600 "$real_env"
trap - EXIT

print "rotated ATTU_DB_PASSWORD in $real_env"
print "backup at $real_env.bak (delete manually after migration is confirmed)"
