#!/usr/bin/env python3
"""Convert IgRS Speakers EasyTimeline block to {{TimelineBar|...}} template calls.

Usage:
    uv run scripts/misc/convert_timeline.py

Output: one {{TimelineBar|...}} line per segment, in BarData display order.
Dates are converted from mm/dd/yyyy (year-1900=PC) to Haracalnde format (d-m y PC).
till:end is converted to 'present' (all end-dated speakers are still active;
the EasyTimeline had a fixed 1963 period cutoff).
Narrow segments (effective width < 11) get a trailing |narrow arg.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict

import requests

PAGE = "List_of_IgRS_Speakers_by_time_as_Speaker"
API  = "https://attuproject.org/api.php"
UA   = "tietero-tools/1.0 (jhn, attuproject)"


# ---------- fetch ----------

def fetch_wikitext(title: str) -> str:
    s = requests.Session()
    s.headers["User-Agent"] = UA
    r = s.get(API, params={
        "action": "query", "prop": "revisions", "rvprop": "content",
        "rvslots": "main", "titles": title, "redirects": 1,
        "format": "json", "formatversion": 2,
    }, timeout=20)
    r.raise_for_status()
    page = r.json()["query"]["pages"][0]
    if page.get("missing"):
        raise SystemExit(f"Page not found: {title!r}")
    return page["revisions"][0]["slots"]["main"]["content"]


def extract_timeline(wikitext: str) -> str:
    # Wiki uses {{#tag:timeline|...}} (parser function), not <timeline>...</timeline>
    m = re.search(r"\{\{#tag:timeline\|(.*?)\}\}", wikitext, re.DOTALL)
    if not m:
        raise SystemExit("No {{#tag:timeline|...}} block found")
    return m.group(1)


# ---------- parse BarData ----------

def parse_bar_data(block: str) -> list[tuple[str, str, str]]:
    """Return [(bar_id_lower, bar_id_orig, label), ...] in display order."""
    m = re.search(r"BarData\s*=(.*?)(?=\n\S|\Z)", block, re.DOTALL)
    if not m:
        raise SystemExit("No BarData section found")
    bars: list[tuple[str, str, str]] = []
    for line in m.group(1).splitlines():
        m2 = re.match(r"\s*bar:(\S+)\s+text:(.*)", line)
        if m2:
            bar_id = m2.group(1)
            label  = m2.group(2).strip()
            bars.append((bar_id.lower(), bar_id, label))
    return bars


# ---------- parse PlotData ----------

Segment = tuple[str, str, str, int]  # (color, from_date, till_date, effective_width)


def parse_plot_data(block: str) -> dict[str, list[Segment]]:
    """Return {bar_id_lower: [(color, from, till, effective_width), ...]}."""
    m = re.search(r"PlotData\s*=(.*)\Z", block, re.DOTALL)
    if not m:
        raise SystemExit("No PlotData section found")

    segments: dict[str, list[Segment]] = defaultdict(list)
    current_color: str | None = None
    current_width: int = 11

    for raw in m.group(1).splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        # Header line: "color:X [width:Y]" — must have color: but no bar:
        if "color:" in line and "bar:" not in line:
            color_m = re.search(r"color:(\S+)", line)
            width_m = re.search(r"width\s*:\s*(\d+)", line)
            if color_m:
                current_color = color_m.group(1)
            current_width = int(width_m.group(1)) if width_m else 11
            continue

        # Bar entry
        bar_m  = re.search(r"bar:(\S+)", line)
        from_m = re.search(r"from:(\S+)", line)
        till_m = re.search(r"till:(\S+)", line)
        if not (bar_m and from_m and till_m):
            continue

        width_m = re.search(r"width\s*:\s*(\d+)", line)
        bar_id  = bar_m.group(1).lower()
        color   = current_color or "unknown"
        from_d  = from_m.group(1)
        till_d  = till_m.group(1)
        width   = int(width_m.group(1)) if width_m else current_width

        segments[bar_id].append((color, from_d, till_d, width))

    return dict(segments)


# ---------- date conversion ----------

def convert_date(d: str) -> str:
    """mm/dd/yyyy → d-m y PC. 'end' → 'present'."""
    d = d.strip()
    if d.lower() == "end":
        return "present"
    m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})$", d)
    if not m:
        raise ValueError(f"Unrecognised date: {d!r}")
    month = int(m.group(1))
    day   = int(m.group(2))
    year  = int(m.group(3))
    return f"{day}-{month} {year - 1900} PC"


def date_sort_key(from_str: str) -> tuple[int, int, int]:
    m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", from_str)
    if m:
        return int(m.group(3)), int(m.group(1)), int(m.group(2))
    return 9999, 0, 0


# ---------- main ----------

def main() -> None:
    print(f"Fetching {PAGE}...", file=sys.stderr)
    wikitext = fetch_wikitext(PAGE)
    block    = extract_timeline(wikitext)
    bars     = parse_bar_data(block)
    segments = parse_plot_data(block)

    total_lines = 0
    warnings    = 0
    for bar_lower, bar_orig, label in bars:
        segs = sorted(
            segments.get(bar_lower, []),
            key=lambda s: date_sort_key(s[1]),
        )
        if not segs:
            print(f"WARNING: no segments for bar {bar_orig!r}", file=sys.stderr)
            warnings += 1
        for color, from_d, till_d, width in segs:
            try:
                start = convert_date(from_d)
                end   = convert_date(till_d)
            except ValueError as e:
                print(f"WARNING: {e}", file=sys.stderr)
                warnings += 1
                continue
            narrow = "|narrow" if width < 11 else ""
            print(f"{{{{TimelineBar|{bar_orig}|{label}|{color}|{start}|{end}{narrow}}}}}")
            total_lines += 1

    print(
        f"\n{len(bars)} bars, {total_lines} TimelineBar lines"
        + (f", {warnings} warnings" if warnings else ""),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
