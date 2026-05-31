#!/usr/bin/env python3
"""Convert an EasyTimeline block to {{TimelineBar|...}} template calls.

Usage:
    uv run scripts/misc/convert_timeline.py "<Page title>"

Output: one {{TimelineBar|...}} line per segment, in BarData display order.
Dates are converted from mm/dd/yyyy (year-1900=PC) to Haracalnde format (d-m y PC).
till:end is converted to 'present'.
Narrow segments (effective width < 11) get a trailing |narrow arg.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict

import requests

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


def parse_date_format(block: str) -> str:
    m = re.search(r"DateFormat\s*=\s*(\S+)", block)
    return m.group(1) if m else "mm/dd/yyyy"


def parse_period(block: str) -> tuple[str, str]:
    """Return (from_raw, till_raw) strings from the Period declaration."""
    m = re.search(r"Period\s*=\s*from:(\S+)\s+till:(\S+)", block)
    if not m:
        return ("", "")
    return m.group(1), m.group(2)


# ---------- color extraction ----------

# Color IDs already handled by Module:Timeline's hardcoded palette — skip these
# so convert_timeline.py doesn't override the module's curated hues.
_HARDCODED_IDS = {
    "utlia", "akaria", "okrit", "tietero", "niueyjar", "deysachin",
    "nongba", "eee", "casea", "faltir", "kel", "spyron", "joy",
    "larossa", "kalam", "hapsaw", "steam", "tvaqi", "walst",
}

_NAMED_COLORS: dict[str, str] = {
    "red":         "#FF0000",
    "blue":        "#0000FF",
    "green":       "#008000",
    "teal":        "#008080",
    "purple":      "#800080",
    "orange":      "#FF6600",
    "pink":        "#FFC0CB",
    "yellow":      "#FFFF00",
    "brightgreen": "#00CC00",
    "skyblue":     "#87CEEB",
    "tan1":        "#D2B48C",
    "tan2":        "#8B6914",
    "black":       "#000000",
    "white":       "#FFFFFF",
}


def value_to_hex(value: str) -> str | None:
    """Convert an EasyTimeline color value string to #RRGGBB hex, or None if unknown."""
    value = value.strip()
    m = re.match(r"^rgb\(([0-9.]+),([0-9.]+),([0-9.]+)\)$", value)
    if m:
        r = min(255, round(float(m.group(1)) * 255))
        g = min(255, round(float(m.group(2)) * 255))
        b = min(255, round(float(m.group(3)) * 255))
        return f"#{r:02X}{g:02X}{b:02X}"
    m = re.match(r"^gray\(([0-9.]+)\)$", value)
    if m:
        v = min(255, round(float(m.group(1)) * 255))
        return f"#{v:02X}{v:02X}{v:02X}"
    return _NAMED_COLORS.get(value.lower())


def parse_colors(block: str) -> list[tuple[str, str, str]]:
    """Parse the Colors section. Returns [(id, hex, legend), ...] for non-hardcoded IDs."""
    m = re.search(r"Colors\s*=(.*?)(?=\n\S|\Z)", block, re.DOTALL)
    if not m:
        return []
    results = []
    for line in m.group(1).splitlines():
        m2 = re.match(r"\s*id:(\S+)\s+value:(\S+)(?:\s+legend:(.*))?", line)
        if not m2:
            continue
        color_id = m2.group(1).lower()
        if color_id in _HARDCODED_IDS or color_id == "bars":
            continue
        value  = m2.group(2)
        legend = (m2.group(3) or color_id).strip().replace("_", " ")
        hex_color = value_to_hex(value)
        if hex_color:
            results.append((color_id, hex_color, legend))
        else:
            print(f"WARNING: cannot convert color {color_id!r}: {value!r}", file=sys.stderr)
    return results


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
        from_m = re.search(r"from:\s*(\S+)", line)
        till_m = re.search(r"till:\s*(\S+)", line)
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

def make_converter(date_format: str, period_start: str = "", period_end: str = ""):
    """Return (convert_date, sort_key) functions for the given DateFormat."""
    if date_format == "mm/dd/yyyy":
        def convert(d: str) -> str:
            d = d.strip()
            if d.lower() in ("end", "till"):
                return "present"
            m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})$", d)
            if not m:
                raise ValueError(f"Unrecognised date: {d!r}")
            return f"{int(m.group(2))}-{int(m.group(1))} {int(m.group(3)) - 1900} PC"
        def sort_key(d: str) -> tuple[int, int, int]:
            m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", d)
            return (int(m.group(3)), int(m.group(1)), int(m.group(2))) if m else (9999, 0, 0)
    elif date_format == "yyyy":
        def _yr_to_haracalnde(d: str) -> str:
            y = int(d)
            if y > 0:
                return f"1-1 {y} PC"
            else:
                return f"1-1 {abs(y)} TT"
        def convert(d: str) -> str:
            d = d.strip()
            if d.lower() == "end":
                return "present"
            if d.lower() == "start":
                if not period_start:
                    raise ValueError("'start' keyword used but Period not found")
                return _yr_to_haracalnde(period_start)
            if re.match(r"^-?\d+$", d):
                return _yr_to_haracalnde(d)
            raise ValueError(f"Unrecognised date: {d!r}")
        def sort_key(d: str) -> tuple[int, int, int]:
            if d.lower() in ("start", "end"):
                y = int(period_start) if d.lower() == "start" else int(period_end or "9999")
                return (y, 0, 0)
            return (int(d), 0, 0) if re.match(r"^-?\d+$", d) else (9999, 0, 0)
    else:
        raise SystemExit(f"Unsupported DateFormat: {date_format!r}")
    return convert, sort_key


# ---------- main ----------

def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("Usage: convert_timeline.py <page title>")
    page = sys.argv[1]
    print(f"Fetching {page}...", file=sys.stderr)
    wikitext       = fetch_wikitext(page)
    block          = extract_timeline(wikitext)
    date_format    = parse_date_format(block)
    period_start, period_end = parse_period(block)
    convert_date, date_sort_key = make_converter(date_format, period_start, period_end)
    print(f"DateFormat: {date_format}  Period: {period_start} – {period_end}", file=sys.stderr)
    colors   = parse_colors(block)
    bars     = parse_bar_data(block)
    segments = parse_plot_data(block)

    for color_id, hex_color, legend in colors:
        print(f"{{{{TimelineColor|{color_id}|{hex_color}|{legend}}}}}")

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
    print(f"\nSubpage title: {page}/Timeline", file=sys.stderr)


if __name__ == "__main__":
    main()
