# log — IgRS Timeline — Scribunto Lua CSS-div

## starting phase 0 — 2026-05-29

**worktree:** `.claude/worktrees/igrs-timeline-lua/`
**branch:** `phase/igrs-timeline-lua/0`

**pivot note:** mid-phase revision triggered by Phase 0 pivot criterion (SVG probe failed). No formal retro/triage — revision driven directly by probe results.

**confirmed DoD:**
1. `Module:TimelineTest` on dev wiki renders a hardcoded single-bar `<svg>` — DOM-verified in DevTools (not escaped text); `viewBox` and `xmlns` attributes survive sanitization unchanged.
2. Pivot criterion: if step 1 fails, call `plan-revise` before Phase 1.
3. Layout algorithm sketched for the 3 most complex rows (Vidar Astridson 2-term, Psaha Yol 2-term, Ara Deram 3-term) and confirmed tractable.
4. Data architecture chosen (Lua table, `Module:TimelineData/IgRS`, or wikitext parse); feasibility spike if wikitext parse.
5. `os.time()` sandbox behavior confirmed, or hardcoded end-year parameter documented.
6. Source control workflow decided.
7. Visual spec captured from `devel/ploticus242`, `devel/EasyTimeline`, and current rendered PNG.

## revision after phase 0 — 2026-05-29

Mid-phase pivot revision (pivot criterion triggered at DoD item 1; all other items resolved before plan-revise).

- phase 0 (research + walking skeleton): **done** — all 7 DoD items resolved. SVG probe failed (blocked by MediaWiki sanitizer; `svg` not in `$htmlpairsStatic`). CSS-div approach confirmed viable: position:absolute/relative, background:, pixel dimensions all survive. Pivot criterion executed.
- phase 1 (module development): **revise** — scope changes from SVG coordinate geometry to CSS-div layout. Data model and architecture confirmed. DoD and scope rewritten in plan.md.
- phase 2 (wiki integration): **valid** — no premise changes; wording updated (SVG → CSS-div).

Plan title and goals updated to reflect CSS-div approach throughout.

## phase 0 retro — 2026-05-29

### spec delta
- delivered: all 7 DoD items resolved; CSS-div probe replaces SVG per pivot criterion
- missed / deferred: none
- extra: `os.time()` confirmed available (enables `present` sentinel in Phase 1); Haracalnde calendar design + `Module:AttuCalendar` scoped in mid-phase; conversion script (`convert_timeline.py`) added to Phase 1 scope; template-call subpage architecture chosen (user decision)

### surprises
- SVG blocked across all 5 output paths → CSS-div adopted; pivot criterion executed cleanly, no delay
- `img` data-URI also blocked (`img` not in whitelist); irrelevant to final design
- EasyTimeline fake dates map trivially to Haracalnde (year − 1900 = PC year, month/day digits unchanged) → conversion script is straightforward
- `present` sentinel in data subpage requires live epoch data → `Module:AttuCalendar` added as a new deliverable, mirroring `scripts/misc/current_year.py`

### residual debt
- `Module:TimelineTest` + `Project:TimelineTest` + `Project:OsTest` on dev wiki are probe artifacts; can stay as scratch pad or be deleted during Phase 1 cleanup · routed to bugs.md as CLEANUP-001

## revision after phase 0 (design update) — 2026-05-29

Design decision post-pivot: data architecture changed from Lua data module (`Module:Timeline/IgRS`) to template-call subpage (`{{TimelineBar|...}}` lines on `<Article>/Timeline`). Haracalnde calendar (`d-m y PC/TT`) adopted throughout; `present` sentinel resolves via `Module:AttuCalendar`. Epoch data in `Module:AttuCalendar` mirrors `scripts/misc/current_year.py`.

- phase 1 (module development): **revise** — architecture now: `Module:AttuCalendar` + `Module:Timeline` + `Template:TimelineBar` (no-op) + data subpage. Conversion script (`scripts/misc/convert_timeline.py`) added to scope to auto-generate initial subpage from EasyTimeline block.
- phase 2 (wiki integration): **valid** — no structural change; subpage creation is part of Phase 2 deploy.
