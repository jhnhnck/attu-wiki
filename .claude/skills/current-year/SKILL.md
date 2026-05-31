---
name: current-year
description: >
  Fetch the current in-universe Attu year, computed from the project's epoch
  snapshot. Use when you need to know what year it is in the Attu world — for
  dating "as of" claims, calculating ages, deciding whether a fact is current,
  or stamping a new in-universe event.
allowed-tools:
  - Bash
---

# current-year

## Current Attu year

!`uv run scripts/misc/current_year.py`

The number above is the current in-universe Attu year (PC), computed at skill-load time from the epoch snapshot embedded in `scripts/misc/current_year.py`. Use it directly; do not re-derive it from real-world dates.

## When the epoch changes

If the project announces a new epoch (the `/fix epoch` command produces a fresh TOML block), paste the updated block into the `_epoch_toml` string in [scripts/misc/current_year.py](../../../scripts/misc/current_year.py). No other changes are needed; the next skill invocation will reflect the new epoch.

## Rules

- The output is a single integer, the year in PC.
- Real-world today's date is unrelated to this number; the Attu calendar runs at a different rate (currently 21 real days per in-universe year).
- Do not interpret the number as anything else (not a count of facts, not a file index).
