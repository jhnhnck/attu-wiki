#!/usr/bin/env python3
"""Print the current in-universe Attu year, computed from an embedded epoch snapshot."""

import tomllib
from datetime import date, datetime
from zoneinfo import ZoneInfo

# epoch snapshot — paste the output of /fix epoch here when the epoch changes
_epoch_toml = """\
[epoch]
time = 1772229600
year = 76
length = 21
paused = false
rollover_minutes = 1020  # 17:00
"""


def compute_attu_year() -> int:
    """Compute the current Attu year from the epoch snapshot in _epoch_toml."""
    epoch = tomllib.loads(_epoch_toml)['epoch']
    tz = ZoneInfo('UTC')
    rollover_minutes: int = epoch['rollover_minutes']
    rollover_time = datetime.min.time().replace(
        hour=rollover_minutes // 60,
        minute=rollover_minutes % 60,
        tzinfo=tz,
    )
    epoch_dt = datetime.combine(
        datetime.fromtimestamp(epoch['time']).astimezone(), rollover_time
    )
    today_dt = datetime.combine(date.today(), rollover_time)
    elapsed_days = int((today_dt - epoch_dt).total_seconds() / 86400)
    year: int = epoch['year'] + (elapsed_days // epoch['length'])
    if (elapsed_days % epoch['length']) == 0 and datetime.now().astimezone() < today_dt:
        year -= 1
    return year


if __name__ == "__main__":
    print(compute_attu_year())
