#!/usr/bin/env zsh
# Attu Project Wiki - acme.sh SSL certificate renewal
# This file is licensed under the MIT License; See LICENSE for full text.
#
# acme.sh exits 2 when the cert is not yet due for renewal; treated as success
# so the script is safe to run on the twice-daily cron cadence without noise.

set -eu -o pipefail

typeset -r acme_home="${USER_HOME}/certificates/.acme.sh"
typeset -r cert_out="${USER_HOME}/certificates"

# one wildcard cert per domain; each gets its own subdirectory under cert_out
typeset -a domains=(
    attuproject.org
    jhnhnck.com
    xffxe4.lol
    xffxe4.com
    attu.link
)

typeset -i rc failures=0

print -P '%F{cyan}[acme-renew]%f checking certificates'

for domain in "${domains[@]}"; do
    print -P "%F{cyan}[acme-renew]%f ${domain}"

    rc=0
    # --home keeps all state (account, domain config) on the bind mount so it
    # survives container restarts; ACME_HOME env var is not reliably picked up
    acme.sh --home "${acme_home}" --issue --dns dns_cf --server letsencrypt \
        -d "${domain}" \
        -d "*.${domain}" \
        || rc=$?

    if (( rc != 0 && rc != 2 )); then
        print -P "%F{yellow}[acme-renew]%f ${domain}: issue failed (exit ${rc}), skipping"
        (( ++failures ))
        continue
    fi

    mkdir -p "${cert_out}/${domain}"

    acme.sh --home "${acme_home}" --install-cert -d "${domain}" \
        --cert-file      "${cert_out}/${domain}/cert.pem" \
        --key-file       "${cert_out}/${domain}/key.pem" \
        --fullchain-file "${cert_out}/${domain}/fullchain.pem" \
        --ca-file        "${cert_out}/${domain}/chain.pem"
done

# GID 976 = caddy group on the host; caddy is not installed in this container
# so we use the numeric GID. verify with `getent group caddy` if host changes.
find "${cert_out}" -type f -name '*.pem' \
    -exec sudo chown --changes :976 {} \+ \
    -exec sudo chmod --changes g+r {} \+

# non-zero exit triggers the ZERR trap in entry.zsh, firing the Discord alert
(( failures == 0 ))

print -P '%F{green}Done.%f'
