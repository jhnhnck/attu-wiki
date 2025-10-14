#!/usr/bin/env python
"""
Attu Project Wiki - Error rate monitoring script
This file is licensed under the MIT License; See LICENSE for full text.
"""

from os import getenv
import asyncio
import sys
from datetime import datetime, timedelta
from typing import List, cast, Dict, Optional, Union

from cysystemd.reader import JournalOpenMode, JournalReader, Rule
from pydantic import BaseModel, Field

# --- Init ---

webhook_url = getenv('ATTU_SCRIPTS_WEBHOOK')
threshold = 0.015
threshold_min = 10

if webhook_url is None:
    print('error_rate: error: ATTU_SCRIPTS_WEBHOOK not set', file=sys.stderr)
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
    headers: Dict[str, List[str]]
    tls: CaddyTLSInfo

class CaddyLogEntry(BaseModel):
    level: str
    ts: float
    logger: str
    msg: str
    request: CaddyRequestInfo
    bytes_read: int = Field(..., alias="bytes_read")
    user_id: Optional[str] = Field(None, alias="user_id")
    duration: float
    size: int
    status: int
    resp_headers: Dict[str, List[str]] = Field(..., alias="resp_headers")

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

total, errors = 0, 0
alerts: set[str] = set()

for entry in entries:
    if entry.request.host.lower() == 'attuproject.org' and 'Better Uptime Bot' not in entry.request.headers['User-Agent'][0]:
        total += 1

        if entry.status // 100 == 5:
            if entry.request.headers["Cf-Ipcountry"] is not None:
                cf_ip_country = ','.join(entry.request.headers["Cf-Ipcountry"])
            else:
                cf_ip_country = 'unknown'

            alerts.add(f'[{entry.status}] {entry.request.method} {entry.request.uri} (from {cf_ip_country})')
            errors += 1

now_text = datetime.now().strftime('%F,%T')
error_rate = errors / total

print(f'error_rate: {now_text},{error_rate:.4f},{errors},{total}')

# --- Send Alerts ---

# feels inefficient but more straight-forward I think -jhn
def break_at_newline(lines: set[str], maximum: int = 2000, begin: str = '', end: str = '') -> str:
    everything = lambda lines_left: f'{begin}{"\n".join(lines_left)}\n{end}'

    while True:
        if len(everything(lines)) <= maximum:
            return everything(lines)
        else:
            lines.pop()

    return everything(['...'])  # failsafe


def send_webhook_alert():
    import requests  # noqa: PLC0415

    webhook = lambda(text: str): requests.post(cast(str, webhook_url), json={'content': text, 'username': 'DoomBot', 'allowed_mentions': {'parse': []}})

    heading = f':warning: **Wiki Service Warning**\nIncreased error rate for attuproject.org: {error_rate * 100:.2f}% > {threshold * 100:.1f}% ({errors}/{total})'
    webhook(heading)

    body = break_at_newline(alerts, begin='```\n', end='```')
    webhook(body)


if error_rate > threshold and errors > threshold_min:
    # print all alerts
    for msg in alerts:
        print(msg)

    send_webhook_alert()
