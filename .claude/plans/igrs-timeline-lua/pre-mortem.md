# pre-mortem — IgRS Timeline — Scribunto Lua SVG

**Bottom line:** proceed with revisions (folded into plan.md)

### Risks
- [high] integration — MediaWiki's HTML sanitizer may strip `<svg>` elements from Lua module output; if true, the entire approach collapses · probe: create `Module:TimelineTest` on dev wiki returning a minimal `<svg>` element, load the page, inspect DOM to confirm `<svg>` is present and not escaped text
- [high] expertise — SVG bar-chart layout for 70+ rows must handle multi-term speakers (up to 3 terms), "present" open-ended dates, non-overlapping labels, and a legend — non-trivial coordinate geometry in sandboxed Lua with no layout helpers · probe: in Phase 0, sketch the row-assignment and label-placement algorithm for Vidar Astridson (2-term), Psaha Yol (2-term), and Ara Deram (3-term) before writing any code
- [medium] dependency — `mw.html` is designed for HTML, not SVG; namespace attributes like `viewBox` (camelCase) and `xmlns` may be mangled or stripped by mw.html's attribute sanitizer · probe: in the walking-skeleton test, explicitly verify `viewBox` and `xmlns` survive the round-trip in DevTools
- [medium] scope — "parse from wikitext table" is a listed data architecture option but Scribunto has no mwparserfromhell — only string ops and `mw.title:getContent()`; that path could balloon Phase 1 scope significantly · probe: Phase 0 must prototype both approaches at the data-loading layer only and choose before Phase 1 starts
- [medium] operational — the Lua module lives only on the wiki with no git history; update workflow (edit → test → deploy) is undefined · probe/decision: Phase 0 decides whether module source is tracked in the repo as a text file manually pasted into the wiki
- [low] performance — no measurement of Scribunto CPU/memory cost for building a 70-bar SVG string · probe: enable Scribunto profiling in Phase 1 and confirm execution within default limits
- [low] premise — `os.time()` is sandboxed in Scribunto's luastandalone; "present" end date for active speakers cannot be resolved at runtime without it · probe: in Phase 0, confirm whether `os.time()` works in luastandalone; if not, define the hardcoded end-year parameter API

### Walking-skeleton check
Phase 0 is correctly shaped as a walking skeleton — a hardcoded single-bar SVG is the thinnest end-to-end slice that proves the full rendering pipeline (Lua → wikitext → MediaWiki parser → browser DOM). Every subsequent phase replaces stubs. The pivot criterion (plan-revise if sanitizer strips SVG) and the attribute-survives-sanitization check have been added explicitly to the Phase 0 DoD.

### Phase-order revisions
| original | proposed | reason |
|---|---|---|
| (no changes) | — | Phase 0 already retires the highest-severity risks; order is correct |

### Definition-of-done additions
- phase 0 — add: DOM-verified `<svg>` in DevTools (not escaped text); `viewBox` and `xmlns` attributes confirmed intact
- phase 0 — add: explicit pivot criterion — if sanitizer strips SVG, call `plan-revise` before Phase 1
- phase 0 — add: `os.time()` sandbox behavior confirmed or hardcoded end-year parameter documented
- phase 0 — add: source control workflow decided and documented
- phase 1 — add: layout verified against `devel/ploticus242` reference output for all multi-term speakers
- phase 1 — add: Scribunto profiling confirms execution within default CPU/memory limits
