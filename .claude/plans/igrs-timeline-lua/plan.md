# IgRS Timeline — Scribunto Lua CSS-div

## goals
- A CSS-div timeline on `List_of_IgRS_Speakers_by_time_as_Speaker` replacing the EasyTimeline block
- Speaker data stored as `{{TimelineBar|...}}` template calls on a wiki subpage — editable by anyone without touching Lua
- Dates in the Haracalnde calendar (`d-m y PC` / `d-m y TT`); `present` resolves to the current in-universe year automatically
- A shared `Module:AttuCalendar` on the wiki that any future module can use for date arithmetic

## non-goals
- New PHP extensions or Docker rebuilds (Scribunto is already installed)
- Full accessibility audit (aria labels are a nice-to-have, not a gate)
- Migrating every existing EasyTimeline page in one go — IgRS Speakers is the pilot

## constraints
- MediaWiki's HTML sanitizer blocks `<svg>` from all Scribunto output paths — CSS-div is the only inline approach
- Scribunto runs `luastandalone` — no filesystem, no network, only `mw.*` APIs + stdlib; `os.time()` is available
- `Module:AttuCalendar` must be kept in sync with `scripts/misc/current_year.py`; both are updated when `/fix epoch` runs
- Wiki edits require manual credentials; repo files under `wiki-modules/` are the source of truth, manually pasted to wiki

## accepted risks
Phase 0 confirmed SVG is blocked; CSS-div approach verified working. Data is now template-call-based on a subpage, parsed by the module from raw wikitext — the parse is a controlled flat format (`{{TimelineBar|5 positional args}}`), far simpler than the rejected EasyTimeline syntax. Remaining risks: (low) `mw.title:getContent()` on the data subpage adds one extra API call per render — monitor via NewPP profiling; (low) Haracalnde date parsing edge cases (TT dates near year boundary, month/day > valid range) — validate in Phase 1 with a test suite in the module.

## phase 0 — research + walking skeleton
**status:** closed (pending merge)
**definition of done:**
1. ✅ CSS-div probe confirmed: `position:absolute/relative`, `background:`, pixel dimensions all survive MediaWiki's sanitizer. `<svg>` confirmed blocked across all Scribunto output paths.
2. ✅ Pivot: SVG blocked → CSS-div adopted; `plan-revise` called.
3. ✅ Layout algorithm for multi-term speakers confirmed tractable with CSS-div segments.
4. ✅ `os.time()` available; not needed for period-end (hardcoded 01/01/1963 in EasyTimeline = 63 PC).
5. ✅ Source control: `wiki-modules/` in repo, manual paste to wiki.
6. ✅ Visual spec: 20px bar rows, 19-nation color map, 62-year period, major ticks every 5 years.

**artifacts:** `wiki-modules/phase0-research.md`; `Module:TimelineTest` + `Project:TimelineTest` on dev wiki.

## phase 1 — module development
<!-- phase 1: CSS-div approach; template-call data on subpage; Haracalnde calendar via Module:AttuCalendar -->
**status:** open

**architecture:**
```
Module:AttuCalendar       epoch data + parse_date() + current_year()
Module:Timeline           renderer — reads data subpage, outputs CSS-div
Template:TimelineBar      no-op (renders nothing; module reads raw wikitext)
<Article>/Timeline        data subpage — one {{TimelineBar|...}} line per term
```

**data subpage format** (`List_of_IgRS_Speakers_by_time_as_Speaker/Timeline`):
```
{{TimelineBar|Yyme|Yyme Braia|utlia|18-2 1 PC|3-12 16 PC}}
{{TimelineBar|Yol|Psaha Yol|nongba|3-1 2 PC|16-11 7 PC}}
{{TimelineBar|Yol|Psaha Yol|nongba|15-12 16 PC|1-1 26 PC}}
{{TimelineBar|Alekso|Alekso IV|tietero|8-9 18 PC|present}}
```
Row order = display order. One line per term. `present` = live current year.

**invoke on the article page:**
```
{{#invoke:Timeline|main|data=List_of_IgRS_Speakers_by_time_as_Speaker/Timeline|period_start=1-1 1 PC|period_end=present}}
```

**definition of done:**
- `Module:AttuCalendar` on dev wiki: `parse_date("d-m y ERA")` handles PC and TT; `present` returns `current_year()`; TT year arithmetic correct (1 TT = −1, no year 0); round-trips verified for boundary dates.
- `Module:Timeline` on dev wiki: reads data subpage via `mw.title.new(args.data):getContent()`; parses all `{{TimelineBar|...}}` lines; renders complete CSS-div timeline for all 74 IgRS speakers.
- Full-bar segments and narrow overlays (EasyTimeline `width:3` equivalent) both render correctly.
- Year axis: major labels every 5 years, minor ticks every 1 year, correct PC year numbers.
- Legend: 4-column grid, correct nation names and colors.
- Label column: speaker name in 150px column, truncated with `overflow:hidden`.
- `period_end=present` renders to current year (80 PC) and updates automatically.
- NewPP profiling confirms within default Scribunto CPU/memory limits.
- Visual parity check: information density matches EasyTimeline rendered PNG.

**scope:**
- Write `Module:AttuCalendar`: epoch constants (mirroring `scripts/misc/current_year.py`), `current_year()`, `parse_date()`, `to_frac(date, period_start, period_end)`.
- Write `scripts/misc/convert_timeline.py`: fetch IgRS Speakers wikitext, parse EasyTimeline BarData + PlotData, convert fake dates (`mm/dd/yyyy`, year − 1900 = PC year) to Haracalnde, emit `{{TimelineBar|...}}` lines in BarData row order. Output becomes the initial data subpage content.
- Write `Module:Timeline`: `main(frame)` reads `args.data` page content, parses TimelineBar calls, builds CSS-div layout using `Module:AttuCalendar` for date fractions.
- Create `Template:TimelineBar` (empty body, `<noinclude>` docs only).
- Test incrementally: push modules via `maintenance/run.php edit`; verify with `action=parse` API.
- Create data subpage on dev wiki using conversion script output; verify all 74 rows render.

## phase 2 — wiki integration
**status:** open
**definition of done:** Prod wiki `List_of_IgRS_Speakers_by_time_as_Speaker` uses `Module:Timeline`; EasyTimeline block replaced by invoke + data subpage; CSS-div timeline renders correctly in browser; zero JS console errors.
**scope:** *(to be detailed at end of Phase 1)*
