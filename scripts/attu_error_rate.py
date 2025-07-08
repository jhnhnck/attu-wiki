#!/usr/bin/env python

import asyncio
import sys
from datetime import datetime, timedelta
from typing import cast

from cysystemd.reader import JournalOpenMode, JournalReader, Rule
from dotenv import dotenv_values
from pydantic import BaseModel

# --- Init ---

config = dotenv_values('./.env')

webhook_url = config.get('ATTU_ERROR_RATE_WEBHOOK')
threshold = 0.015
threshold_min = 10

if webhook_url is None:
    print('error_rate: error: ATTU_ERROR_RATE_WEBHOOK not set', file=sys.stderr)
    sys.exit(1)

# --- Log Processing ---

# quick and dirt pydantic model for json structure
class LogEntry(BaseModel):
    cf_connecting_ip: str
    remote_addr: str
    remote_user: str
    time_local: str
    request_method: str
    request_uri: str
    status: int
    body_bytes_sent: int
    http_referer: str
    http_host: str
    http_user_agent: str
    http_x_forwarded_for: str
    http_cf_ipcountry: str

# wraps up dealing with journald and parsing everything out
def get_journal_entries() -> list[LogEntry]:
    reader = JournalReader()
    reader.open(JournalOpenMode.SYSTEM)
    entries: list[LogEntry] = []

    since_time = datetime.now() - timedelta(minutes=15)
    reader.seek_realtime_usec(since_time.timestamp() * 1000000)

    rule = Rule('_SYSTEMD_UNIT', 'nginx.service')
    reader.add_filter(rule)

    for record in reader:
        try:
            message = record.data.get('MESSAGE', '')
            if message[14] == '{':
                obj = LogEntry.model_validate_json(message[14:])
                entries.append(obj)
            else:
                print(f'error_rate: skipping: {message}', file=sys.stderr)

        except Exception as err:
            print(f'error_rate: error: parsing entry; {str(err).lower()}', file=sys.stderr)

    return entries

entries = get_journal_entries()

# --- Calc ---

total, errors = 0, 0
alerts: list[str] = []

for entry in entries:
    if 'attuproject.org' in entry.http_host.lower() and 'Better Uptime Bot' not in entry.http_user_agent:
        total += 1

        if entry.status // 100 == 5:
            alerts.append(f'[{entry.status}] {entry.request_method} {entry.request_uri} (from {entry.http_cf_ipcountry})')
            errors += 1

now_text = datetime.now().strftime('%F,%T')
error_rate = errors / total

print(f'error_rate: {now_text},{error_rate:.4f},{errors},{total}')

for alert in alerts:
    print(alert)

# --- Send Alerts ---

# for trimming to discord character length (adapted from attubot.util)
def break_at_newline(lines: list[str], maximum: int = 2000, end: str = '...\n') -> str:
    result = ''

    for line in lines:
        holding = f'f{result}{line}\n'

        if len(holding) + len(end) > maximum:
            return result + end

        result += line + '\n'

    return '\n'.join(lines) + end

async def send_alert():
    import aiohttp  # noqa: PLC0415
    from discord import Webhook  # noqa: PLC0415

    async with aiohttp.ClientSession() as session:
        webhook = Webhook.from_url( cast(str, webhook_url), session=session)

        heading = f':warning: **Wiki Service Warning**\nIncreased error rate for attuproject.org: {error_rate:.4f}% > {threshold * 100:.1f}% ({errors}/{total})'

        await webhook.send(heading, username='DoomBot')
        await webhook.send(f'```{break_at_newline(alerts, maximum=2000 - 6)}```', username='DoomBot')


if error_rate > threshold and errors > threshold_min:
    asyncio.run(send_alert())
