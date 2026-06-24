#!/usr/bin/env zsh
# Attu Project Wiki - acme.sh SSL certificate renewal
# This file is licensed under the MIT License; See LICENSE for full text.
#
# acme.sh exits 2 when the cert is not yet due for renewal; treated as success
# so the script is safe to run on the twice-daily cron cadence without noise.

set -eu -o pipefail

typeset -r acme_home="${USER_HOME}/certificates/.acme.sh"
typeset -r cert_out="${USER_HOME}/certificates"

print -P '%F{cyan}[acme-renew]%f checking certificate'

# --home keeps all state (account, domain config) on the bind mount so it
# survives container restarts; ACME_HOME env var is not reliably picked up
acme.sh --home "${acme_home}" --issue --dns dns_cf --server letsencrypt \
    -d attuproject.org \
    -d dev.attuproject.org \
    -d links.attuproject.org \
    || (( $? == 2 ))

mkdir -p "${cert_out}/attuproject.org"

acme.sh --home "${acme_home}" --install-cert -d attuproject.org \
    --cert-file      "${cert_out}/attuproject.org/cert.pem" \
    --key-file       "${cert_out}/attuproject.org/key.pem" \
    --fullchain-file "${cert_out}/attuproject.org/fullchain.pem" \
    --ca-file        "${cert_out}/attuproject.org/chain.pem"

# GID 976 = caddy group on the host; caddy is not installed in this container
# so we use the numeric GID. verify with `getent group caddy` if host changes.
find "${cert_out}" -type f -name '*.pem' \
    -exec sudo chown --changes :976 {} \+ \
    -exec sudo chmod --changes g+r {} \+

print -P '%F{green}Done.%f'
