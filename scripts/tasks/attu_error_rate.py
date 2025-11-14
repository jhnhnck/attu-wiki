#!/usr/bin/env python3
"""
Attu Project Wiki - Error rate monitoring script
This file is licensed under the MIT License; See LICENSE for full text.
"""

import sys
from datetime import datetime, timedelta
from os import getenv

from cysystemd.reader import JournalOpenMode, JournalReader, Rule
from pydantic import BaseModel, Field

# --- Init ---

webhook_url = getenv('ATTU_SCRIPTS_WEBHOOK')
webhook_icon = getenv('ATTU_WEBHOOK_ICON')

threshold = 0.015
threshold_min = 10

# this should be impossible btw
if webhook_url is None:
    print('error="ATTU_SCRIPTS_WEBHOOK not set"', file=sys.stderr)
    sys.exit(1)

elif webhook_icon is None:
    print('error="ATTU_WEBHOOK_ICON not set"', file=sys.stderr)
    sys.exit(1)

# --- Log Processing ---

# quick and dirt pydantic model for json structure
class CaddyTLSInfo(BaseModel):
    resumed: bool
    version: int
    cipher_suite: int
    proto: str
    server_name: str


class CaddyRequestInfo(BaseModel):
    remote_ip: str
    remote_port: str
    client_ip: str
    proto: str
    method: str
    host: str
    uri: str
    headers: dict[str, list[str]]
    tls: CaddyTLSInfo

class CaddyLogEntry(BaseModel):
    level: str
    ts: float
    logger: str
    msg: str
    request: CaddyRequestInfo
    bytes_read: int = Field(..., alias="bytes_read")
    user_id: str | None = Field(None, alias="user_id")
    duration: float
    size: int
    status: int
    resp_headers: dict[str, list[str]] = Field(..., alias="resp_headers")

# wraps up dealing with journald and parsing everything out
def get_journal_entries() -> list[CaddyLogEntry]:
    reader = JournalReader()
    reader.open(JournalOpenMode.SYSTEM)
    entries: list[CaddyLogEntry] = []

    since_time = datetime.now() - timedelta(minutes=15)
    reader.seek_realtime_usec(since_time.timestamp() * 1000000)

    rule = Rule('_SYSTEMD_UNIT', 'caddy.service')
    reader.add_filter(rule)

    for record in reader:
        try:
            message = record.data.get('MESSAGE', '')
            if message[0] == '{':
                obj = CaddyLogEntry.model_validate_json(message)
                entries.append(obj)
            # else:
                # print(f'error_rate: skipping: {message}', file=sys.stderr)

        except:  # noqa: E722, S110
            # print(f'error_rate: error parsing entry: {str(err).lower()}', file=sys.stderr)
            pass

    return entries

entries = get_journal_entries()

# --- Calc ---

total, errors = 1, 0  # avoid div by zero by being slightly less accurate
alerts: set[str] = set()

def check_and_store_alert(entry: CaddyLogEntry):
    global total, errors  # noqa: PLW0603

    if entry.request.host.lower() == 'attuproject.org' and 'Better Uptime Bot' not in entry.request.headers['User-Agent'][0]:
        total += 1

        if entry.status // 100 == 5:
            cf_ip_country = ','.join(entry.request.headers['Cf-Ipcountry']) if entry.request.headers['Cf-Ipcountry'] is not None else 'unknown'

            alerts.add(f'[{entry.status}] {entry.request.method} {entry.request.uri} (from {cf_ip_country})')
            errors += 1

for entry in entries:
    try:  # noqa: SIM105
        check_and_store_alert(entry)
    except:  # noqa: E722, S110
        pass

now_text = datetime.now().strftime('%F,%T')
error_rate = errors / total

print(f'error_rate={error_rate:.4f},error_count={errors},total_count={total},time="{now_text}"')

# --- Send Alerts ---

# feels inefficient but more straight-forward I think -jhn
def break_at_newline(lines: set[str], maximum: int = 2000, begin: str = '', end: str = '') -> str:
    def everything(lines_left):
        return f'{begin}{"\n".join(lines_left)}\n{end}'

    while True:
        if len(everything(lines)) <= maximum:
            return everything(lines)
        else:
            lines.pop()

    return everything(['...'])  # failsafe


def send_webhook_alert():
    import subprocess  # noqa: PLC0415

    body = break_at_newline(alerts, begin='```\n', end='```', maximum=4096)
    error_field = f'Error Rate;{error_rate * 100:.2f}% > {threshold * 100:.1f}% ({errors}/{total})'

    subprocess.run([  # noqa: S603
        '/usr/local/bin/discord.sh',
        f'--webhook-url={webhook_url}',
        '--username', 'Wiki Service Alert',
        '--avatar', webhook_icon,
        '--title', 'An increased error rate was detected.',
        '--description', body.replace('\n', '\\n'),  # have to send literal \n's
        '--field', error_field,
        '--color', '0xff4941',
        '--footer', __file__,
        '--timestamp',
    ], check=True)

if error_rate > threshold and errors > threshold_min:
    # print all alerts
    for msg in alerts:
        print(msg)

    send_webhook_alert()
