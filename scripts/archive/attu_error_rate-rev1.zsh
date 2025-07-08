#!/usr/bin/zsh

webhook="https://discord.com/api/webhooks/REDACTED/REDACTED"

threshold='0.015'
[[ -z $webhook ]] && {
echo "DISCORD_WEBHOOK_URL not set" >&2
exit 1
}

now=$(date '+%F,%T')
log=$(journalctl -u nginx --since '15 minutes ago' --no-pager -o cat |\
grep 'capcom nginx: ' | grep -v 'Better Uptime Bot' |\
sed 's/^capcom nginx: //')

total=$(echo "$log" | wc -l | tr -d ' ')
errors=$(echo "$log" | grep -Eo ' "status":[5][0-9]{2},' | wc -l | tr -d ' ')
err_rate=$(awk -v e=$errors -v t=$total 'BEGIN{printf "%.4f", t?e/t:0}')

# CSV output: error_rate: timestamp,error_rate,errors,total
printf 'error_rate: %s,%s,%d,%d\n' "$now" "$err_rate" "$errors" "$total"

# set -eux

# alert if over threshold
awk "BEGIN{exit (${err_rate} > ${threshold}) ? 0 : 1}" && {
payload() {
printf '{"content":":warning: **Wiki Service Warning**\\nIncreased Error Rate for attuproject.org: %.2f%%> %.1f%% (%d/%d)"}' \
$(awk 'BEGIN{print '"$err_rate"'*100}') $(awk 'BEGIN{print '"$threshold"'*100}') $errors $total
}

curl -sS -H 'Content-Type: application/json' -d "$(payload)" "$webhook" >/dev/null
}

exit 0
