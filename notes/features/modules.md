# Wiki modules

Lua modules and templates tracked in this repo under `wiki/`. The files here are the canonical version; they are automatically synced to the wiki on every `job-update` run (via `scripts/chores/load_modules.zsh`). Use `wiki.py edit` for one-off manual pushes during development.

## Directory layout

```
wiki/
  <Namespace>/
    <PageTitle>.<ext>   — Lua modules use .lua; wikitext pages use .txt
```

Main-namespace pages (no prefix) live under `wiki/Main/`. Subpages use actual subdirectories.

## Pushing updates

Normal flow: edit the file in `wiki/`, rebuild the image, run `docker compose run job-update`. The `load_modules.zsh` chore detects the changed checksum and pushes automatically.

For immediate one-off pushes to dev during development:

```bash
uv run scripts/misc/wiki.py --wiki dev edit "Module:AttuCalendar" \
  --file wiki/Module/AttuCalendar.lua -s "<summary>" --bot
```

Always push to dev and verify with `action=parse` before touching prod.

---

## Module:AttuCalendar

**Source:** [wiki/Module/AttuCalendar.lua](../../wiki/Module/AttuCalendar.lua)

Haracalnde calendar arithmetic. Epoch constants mirror `scripts/misc/current_year.py`; update both files when `/fix epoch` runs.

### Wikitext-callable functions

#### `current_year`

Returns the current in-universe year (PC, integer).

```
{{#invoke:AttuCalendar|current_year}}
```

Example output: `80`

#### `years_between`

Returns the absolute number of years between two Haracalnde dates.

```
{{#invoke:AttuCalendar|years_between|<date1>|<date2>}}
{{#invoke:AttuCalendar|years_between|<date1>|<date2>|<decimal places>}}
```

- Either date may be `present` (resolves to current year).
- Decimal places defaults to `0`.

Examples:

```
{{#invoke:AttuCalendar|years_between|18-2 1 PC|present}}        → 79
{{#invoke:AttuCalendar|years_between|18-2 1 PC|present|1}}      → 78.9
{{#invoke:AttuCalendar|years_between|3-1 2 PC|16-11 7 PC|2}}    → 5.87
```

### Internal API (for use by other modules)

| Function | Returns |
|---|---|
| `M.current_year()` | current PC year as integer |
| `M.parse_date(s)` | fractional year number from `"d-m y PC"` / `"d-m y TT"` / `"present"` |
| `M.to_frac(date, ps, pe)` | `[0,1]` fraction of date within period `[ps, pe]` |

---

## Module:Timeline

**Source:** [wiki/Module/Timeline.lua](../../wiki/Module/Timeline.lua)

CSS-div timeline renderer. Reads a data subpage of `{{TimelineBar|...}}` calls and outputs a scrollable bar chart with year axis and legend.

### Usage

```
{{#invoke:Timeline|main
|data=<data subpage title>
|period_start=<Haracalnde date>
|period_end=<Haracalnde date or present>
}}
```

Example (IgRS Speakers):

```
{{#invoke:Timeline|main
|data=List_of_IgRS_Speakers_by_time_as_Speaker/Timeline
|period_start=1-1 1 PC
|period_end=present
}}
```

### Data subpage format

**Source:** [wiki/Main/List_of_IgRS_Speakers_by_time_as_Speaker/Timeline.txt](../../wiki/Main/List_of_IgRS_Speakers_by_time_as_Speaker/Timeline.txt)

One `{{TimelineBar|...}}` line per speaker term, in display order (top-to-bottom in the rendered chart):

```
{{TimelineBar|<bar_id>|<label>|<nation_id>|<start>|<end>}}
{{TimelineBar|<bar_id>|<label>|<nation_id>|<start>|<end>|narrow}}
```

- `bar_id` — short identifier; multiple lines with the same id share a row
- `label` — display name shown in the 150 px label column (first occurrence wins)
- `nation_id` — colour key from the 19-nation colour map in `Module:Timeline`
- `start` / `end` — Haracalnde dates; `end` may be `present`
- `narrow` — optional sixth arg; renders a 6 px overlay instead of a 16 px full bar

To regenerate the data subpage from the EasyTimeline block on prod:

```bash
uv run scripts/misc/convert_timeline.py > wiki/Main/List_of_IgRS_Speakers_by_time_as_Speaker/Timeline.txt
```

---

## Template:TimelineBar

**Source:** [wiki/Template/TimelineBar.txt](../../wiki/Template/TimelineBar.txt)

No-op template. Renders nothing when transcluded directly — exists so the data subpage displays cleanly when viewed on its own, while `Module:Timeline` reads the raw wikitext.

---

## Pages changed

| Page | Change |
|---|---|
| `Attu Project:Home` | `Current Year:` replaced with `{{#invoke:AttuCalendar\|current_year}} PC` |
| `List_of_IgRS_Speakers_by_time_as_Speaker` | `{{#tag:timeline\|...}}` block replaced with `{{#invoke:Timeline\|main\|...}}` |
