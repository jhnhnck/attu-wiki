# Wiki modules

Lua modules and templates tracked in this repo under `wiki/`. The files here are the canonical version; they are automatically synced to the wiki on every `job-update` run (via `scripts/chores/load_modules.zsh`). Use `wiki.py edit` for one-off manual pushes during development.

## Directory layout

```
wiki/
  <Namespace>/
    <PageTitle>.<ext>   — system namespaces only: Module, Template, MediaWiki
```

Only `Module:`, `Template:`, and `MediaWiki:` pages live here — these are auto-synced.
Article pages and data subpages are **not** tracked in `wiki/`; see `notes/wiki-pages/` instead.

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

**Reference copy:** [notes/wiki-pages/List_of_IgRS_Speakers_by_time_as_Speaker.Timeline.txt](../wiki-pages/List_of_IgRS_Speakers_by_time_as_Speaker.Timeline.txt) — push manually via `wiki.py edit`.

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

To regenerate from the EasyTimeline block on prod:

```bash
uv run scripts/misc/convert_timeline.py > notes/wiki-pages/List_of_IgRS_Speakers_by_time_as_Speaker.Timeline.txt
```

---

## Template:TimelineBar

**Source:** [wiki/Template/TimelineBar.txt](../../wiki/Template/TimelineBar.txt)

No-op template. Renders nothing when transcluded directly — exists so the data subpage displays cleanly when viewed on its own, while `Module:Timeline` reads the raw wikitext.

---

## Manual page edits

These changes need to be made directly on the wiki. Fetch the current wikitext first and apply the diffs below — don't use a stored snapshot, the page may have changed.

### `Attu Project:Home`

In the `== Current Events ==` section, replace the hardcoded year:

```
Current Year: 80 PC
```
→
```
Current Year: {{#invoke:AttuCalendar|current_year}} PC
```

### `List_of_IgRS_Speakers_by_time_as_Speaker`

**1. Replace the EasyTimeline block.** Find `{{#tag:timeline|` and delete everything through the closing `}}`, replacing with:

```
{{#invoke:Timeline|main
|data=List_of_IgRS_Speakers_by_time_as_Speaker/Timeline
|period_start=1-1 1 PC
|period_end=present
}}
```

**2. Update speech lengths for active speakers.** For each row where the date range ends in `present`, replace the static `~N years` cell with a `years_between` call using the start date from that row:

```
|{{#invoke:AttuCalendar|years_between|<start date>|present}} years
```

Active speakers and their start dates as of the last conversion:

| Speaker | Start date |
|---|---|
| Alekso IV | `8-9 18 PC` |
| Deyg Arthur | `4-9 22 PC` |
| Cya Iri-Semwache | `20-7 52 PC` |
| Dimasi V'sha | `3-9 53 PC` |
| Giulio Moretti | `7-2 57 PC` |
| Reto Heyel | `1-1 57 PC` |
| Řiselan | `1-1 58 PC` |
| Kenpu Nan | `1-1 59 PC` |
| Klemens Joachim | `1-1 60 PC` |

### `List_of_IgRS_Speakers_by_time_as_Speaker/Timeline`

Create this subpage. Generate the content with:

```bash
uv run scripts/misc/convert_timeline.py
```

Paste the output as the full page content.
