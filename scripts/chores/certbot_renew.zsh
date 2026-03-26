#!/usr/bin/env zsh
# Attu Project Wiki - Certbot SSL certificate renewal
# This file is licensed under the MIT License; See LICENSE for full text.

certbot_config='/srv/services/certbot/config'
certbot_creds='/srv/services/certbot/cloudflare.ini'

certbot renew \
  --dns-cloudflare \
  --dns-cloudflare-credentials "${certbot_creds}" \
  --config-dir "${certbot_config}" \
  --work-dir /tmp/certbot-work \
  --logs-dir /tmp/certbot-logs

find "${certbot_config}" -type f -name '*.pem' \
  -exec sudo chown :976 -c {} \+ \
  -exec sudo chmod -c g+r {} \+
