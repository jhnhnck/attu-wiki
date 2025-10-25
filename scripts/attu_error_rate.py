#!/usr/bin/env python
"""
Attu Project Wiki - Error rate monitoring script
This file is licensed under the MIT License; See LICENSE for full text.
"""

import asyncio
import sys
from datetime import datetime, timedelta
from typing import List, cast, Dict, Optional, Union

from cysystemd.reader import JournalOpenMode, JournalReader, Rule
from dotenv import dotenv_values
from pydantic import BaseModel, Field

# --- Init ---

config = dotenv_values('./.env')

webhook_url = config.get('ATTU_SCRIPTS_WEBHOOK')
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
alerts: list[str] = []

for entry in entries:
    if entry.request.host.lower() == 'attuproject.org' and 'Better Uptime Bot' not in entry.request.headers['User-Agent'][0]:
        total += 1

        if entry.status // 100 == 5:
            alerts.append(f'[{entry.status}] {entry.request.method} {entry.request.uri} (from {entry.request.headers["Cf-Ipcountry"][0]})')
            errors += 1

now_text = datetime.now().strftime('%F,%T')
error_rate = errors / total

print(f'error_rate: {now_text},{error_rate:.4f},{errors},{total}')

for alert in alerts:
    print(alert)

# --- Send Alerts ---

# for trimming to discord character length (adapted from attubot.util)
def break_at_newline(lines: list[str], maximum: int = 2000, end: str = '\n...\n') -> str:
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

        heading = f':warning: **Wiki Service Warning**\nIncreased error rate for attuproject.org: {error_rate * 100:.2f}% > {threshold * 100:.1f}% ({errors}/{total})'

        await webhook.send(heading, username='DoomBot')
        await webhook.send(f'```{break_at_newline(alerts, maximum=2000 - 6)}```', username='DoomBot')


if error_rate > threshold and errors > threshold_min:
    asyncio.run(send_alert())
