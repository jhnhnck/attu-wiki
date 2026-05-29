# Phase 0 Research Findings — IgRS Timeline

_Written 2026-05-29. All probes run against dev wiki (attu-dev-mediawiki-1, MW 1.44)._

## 1. SVG Sanitizer Probe (DoD item 1) — PIVOT TRIGGERED

**Result: BLOCKED**

MediaWiki's `Sanitizer::removeHTMLtags()` does not include `svg` in its allowed-elements list
(`$htmlpairsStatic`, `$htmlsingle`). Every approach was tested:

| Approach | Result |
|---|---|
| `mw.html.create('svg')` + `tostring()` | `&lt;svg&gt;` escaped text |
| Raw string return `'<svg>...'` | `&lt;svg&gt;` escaped text |
| `frame:preprocess('<svg>...')` | `&lt;svg&gt;` escaped text |
| `<img src="data:image/svg+xml,...">` | `&lt;img&gt;` escaped (img not in whitelist either) |
| `<div style="...">` | **WORKS** — div, span, position:absolute/relative, background:, width, height all survive |

**Pivot:** SVG approach is blocked. CSS-div approach replaces it.

### CSS-div Layout Verified

The following CSS properties survive MediaWiki's sanitizer when used in `style=""` attributes on `<div>`:
- `position: relative` (container)
- `position: absolute` (child bars + labels)
- `top`, `left`, `width`, `height` (pixel values)
- `background: <color>` (hex and named)
- `font-family`, `font-size`, `color`, `line-height`
- `white-space: nowrap`, `overflow: hidden`
- `text-align`, `padding-right`, `box-sizing`

The multi-bar CSS probe rendered 7 segments across 3 speaker rows (Yol 2-term, Vidar 2-term,
Ara 3-term) correctly.

---

## 2. Data Model (DoD item 4)

### Color map (19 nations)

| ID | Color | Legend name |
|---|---|---|
| utlia | `#FF0000` (red) | Utlia |
| akaria | `#008080` (teal) | Akaria |
| okrit | `#00FF00` (brightgreen) | Okrit |
| tietero | `#0000FF` (blue) | Tietero |
| niueyjar | `#800080` (purple) | Niueyjar |
| deysachin | `#FFA500` (orange) | Deysachin |
| nongba | `#FFB6C1` (pink) | Nongba |
| eee | `#FFFF00` (yellow) | eee |
| casea | `#87CEEB` (skyblue) | Casea |
| faltir | tan1 ≈ `#D2B48C` | Faltir |
| kel | `gray(0.25)` ≈ `#404040` | Kelelemi |
| spyron | `gray(0.5)` = `#808080` | Spyron |
| joy | tan2 ≈ `#D2B48C` | Joy |
| larossa | `rgb(0,0,0.5)` = `#000080` | La_Rossa |
| kalam | `rgb(0,1,1)` = `#00FFFF` | Kalam |
| hapsaw | `rgb(1,0,1)` = `#FF00FF` | Hapshaw |
| steam | `rgb(0.5,0.5,0)` = `#808000` | Steamworks |
| tvaqi | `rgb(0.3,0.7,0.7)` ≈ `#4DB3B3` | T'vaqi |
| walst | `rgb(0.7,0.3,0.3)` ≈ `#B34D4D` | Wälstanland |

### Timeline parameters

- Period: `01/01/1901` – `01/01/1963` (62 years)
- Date format internally: `mm/dd/yyyy`
- `end` keyword = `01/01/1963` (period end, NOT current real-world date)
- 74 bar rows in defined order (see BarData in EasyTimeline block)
- barincrement: 20px
- PlotArea: left=150, bottom=110, top=5, right=0 (source reference)

### Multi-term speaker structure

Each PlotData entry has: `{bar, from, till, color_id, width}`. A single speaker (bar row)
can have multiple entries across multiple color blocks. Multi-term = multiple entries for
same `bar:` key.

**Key multi-term speakers:**

- **Psaha Yol** (`bar:Yol`): 2 terms, both nongba:
  - Term 1: `01/03/1902` – `11/16/1907`
  - Term 2: `12/15/1916` – `01/01/1926`
- **Vidar Astridson** (`bar:Vidar`): 2 niueyjar terms + faltir narrow overlay:
  - Term 1 (niueyjar full): `02/18/1901` – `03/07/1904`
  - Term 2 (niueyjar full): `05/07/1918` – `01/01/1941`
  - Overlap overlay (faltir, width:3): `05/07/1918` – `01/01/1920`
- **Ara Deram** (`bar:Ara`): 3 akaria terms:
  - Term 1: `06/26/1924` – `07/17/1926`
  - Term 2: `01/13/1939` – `01/01/1944`
  - Term 3: `01/01/1945` – `end` (= 01/01/1963)
  - Narrow overlay (akaria, width:3): `01/13/1939` – `end`

**Width semantics in EasyTimeline:** `width:11` = full bar height; `width:3` = narrow overlay.
In CSS-div equivalent: full bar = `height: ROW_H - 4px`; narrow = `height: 6px; top: ROW_H/2`.

---

## 3. Layout Algorithm (DoD item 3)

For the CSS-div approach:

```
TOTAL_YEARS = 62  (1901-1963)
CANVAS_W    = label_width + bar_area_width  (e.g. 150 + 1150 = 1300px)
ROW_H       = 20px (barincrement)

date_frac(d)  = (year(d)-1901 + (month-1)/12 + (day-1)/365) / TOTAL_YEARS
                # returns value in [0.0, 1.0]; "end" = 1.0

bar_x(frac)   = LABEL_W + floor(frac * BAR_AREA)
bar_w(f1, f2) = max(2, floor((f2 - f1) * BAR_AREA))
bar_top(row)  = (row - 1) * ROW_H + 2    # +2 for 1px breathing room

Full-width bar:    height = ROW_H - 4 = 16px
Narrow overlay:    height = 6px, top offset = (ROW_H - 6) / 2 = 7px relative to row top
```

Vidar's faltir overlay stacks on top of the niueyjar bar using `z-index: 1` or simply
rendering it after the base bar (later DOM = visually on top for same top/left).

Algorithm confirmed tractable: CSS-div probe rendered all 7 segments (2+2+3 terms) correctly.

---

## 4. Data Architecture Decision (DoD item 4)

**Decision: Lua table hardcoded in module + separate data submodule.**

Structure:
- `Module:Timeline` — rendering logic (layout, CSS output)
- `Module:Timeline/IgRS` — data table: bars order, labels, segments list, colors

Wikitext parse was rejected: EasyTimeline's multi-section PlotData syntax is too complex
for Lua string ops. No mwparserfromhell available.

---

## 5. os.time() Sandbox Behavior (DoD item 5)

**Result: Available.** `os.time()` returns Unix timestamp in this Scribunto/luastandalone
installation. `os.clock()` also works.

However, `os.time()` is NOT needed: all `till:end` entries map to the period end
`01/01/1963` (hardcoded constant, not the real-world current date). The in-universe
timeline is historical, not live.

---

## 6. Source Control Workflow (DoD item 6)

**Decision: Track module source in repo, copy-paste to wiki manually.**

- Repo path: `wiki-modules/Module-Timeline.lua` and `wiki-modules/Module-Timeline-IgRS.lua`
- Workflow: edit in repo → test locally (parse API) → paste into wiki Module: namespace
- Benefit: git history, diffs, PR review before wiki updates
- The `Module:TimelineTest` used for probing can be deleted or kept as a dev scratch pad

---

## 7. Visual Spec Capture (DoD item 7)

From EasyTimeline.pl + Ploticus:

| Attribute | Value |
|---|---|
| Bar height (barincrement) | 20px |
| Bar fill height | 16px (20 - 2×2 margin) |
| Narrow overlay height | ~6px (width:3 in EasyTimeline) |
| Label column width | 150px (left:150 from PlotArea) |
| Total canvas width | 1300px |
| Year axis major ticks | every 5 years (ScaleMajor increment:5) |
| Year axis minor ticks | every 1 year (ScaleMinor increment:1) |
| Period | 01/01/1901 – 01/01/1963 |
| Year label format | yyyy |
| Legend | position:bottom, orientation:vertical, columns:4 |
| Background color | gray(0.95) ≈ `#F2F2F2` |
| Default bar colors | per nation (see color map above) |
