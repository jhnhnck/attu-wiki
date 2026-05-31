# Template audit — 2026-05-30

Audit of `scripts/chores/templates_refresh.zsh` template list. Goal: identify candidates for repo-forking under `wiki/Template/` to bring template content under version control.

## Results

| Template | In use | Wikipedia dep count | Decision |
|---|---|---|---|
| Composition bar | ✓ 4+ pages | 57 | deferred — exceeds 5-dep threshold |
| Taxobox | ✗ unused | — | removed from refresh list |
| Did you mean box | ✓ 2+ pages | 25 | deferred — exceeds 5-dep threshold |
| Infobox military unit | ✓ 2+ pages | 116 | deferred — exceeds 5-dep threshold |
| Infobox | ✓ 5+ pages | 81 | deferred — exceeds 5-dep threshold |
| MessageBox | ✗ unused | — | removed from refresh list |
| Color box | ✓ 5+ pages | 85 | deferred — exceeds 5-dep threshold |
| Main | ✓ 5+ pages | 85 | deferred — exceeds 5-dep threshold |
| Cquote | ✓ 2+ pages | 102 | deferred — exceeds 5-dep threshold |

Dep count = number of pages returned by `Special:Export?pages=Template:X&curonly=1&templates=1` (includes all transitive dependencies).

## Licensing

All Wikipedia templates are CC BY-SA 4.0. Forking is permitted with attribution. Attribution format for `.txt` files: `<!-- CC BY-SA 4.0, source: https://en.wikipedia.org/wiki/Template:Name -->`.

## Why dep counts are so high

Wikipedia templates use module infrastructure heavily: `TemplateStyles`, `Module:*` Lua modules, CSS subpages, `/doc`, `/sandbox`, `/testcases`, helper templates like `Delink`, `Nowrap`, `If empty`, etc. Even "simple" templates like `Did you mean box` (25 deps) carry this infrastructure.

## Follow-up path

If full-tree forking becomes desirable (removes runtime Wikipedia dependency):
1. Use `Special:Export?pages=Template:X&curonly=1&action=submit&templates=1` to export the full dep tree as XML
2. Import via `maintenance/run.php importDump` to a local checkout
3. Bulk-export each page as individual `.txt` files into `wiki/Template/`
4. Update `templates_refresh.zsh` to remove forked entries

This is higher-effort but achievable as a standalone plan. Current `templates_refresh` chore is reliable and low-maintenance enough that the trade-off isn't warranted yet.
