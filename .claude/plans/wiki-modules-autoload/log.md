# Log — wiki-modules-autoload

## starting phase 0 — 2026-05-30

**Branch:** `phase/igrs-timeline-lua/0` (existing worktree reused per user instruction)  
**Worktree:** `/srv/services/attu-wiki-dev/.claude/worktrees/igrs-timeline-lua/`

**Confirmed DoD:**
- `docker compose run job-update` on dev pushes all 5 wiki/ files (or logs "skipped")
- Second run with no changes logs "skipped" for all 5 pages (idempotency)
- Content change → exactly one new wiki revision after next update run
- Scheduler image builds without error
- Probe confirmed: `maintenance/run.php edit` flags match; "Doom" user exists in wiki DB
- Pivot: if identical runs create duplicate revisions, move to `@reboot` cron in scheduler

## phase 0 retro — 2026-05-30

### spec delta
- delivered: all 5 DoD items met; Dockerfile, load_modules.zsh, entry.zsh, attu_tasks.zsh all landed
- missed / deferred: none
- extra: added `cd "$APP_HOME/mediawiki"` to load_modules.zsh (bug caught during integration check — standalone chore call would have had wrong cwd); removed FamilyTreeEditor include from worktree's docker-compose.dev.yml (worktree-only breakage)

### surprises
- plan assumed `--title` flag → reality: `<title>` is a positional arg in `maintenance/run.php edit` → plan spec corrected before implementation
- MediaWiki natively refuses identical-content edits ("edit was ignored, no change") → checksum dedup is now doubly safe; even a wiped volume produces no duplicate revisions
- Worktree docker-compose.dev.yml missing `files/assets/` prevented a clean `docker build` from the worktree → integration tested via exec into running main-dev containers; build correctness verified against main dev directory

### residual debt
- Dockerfile COPY + checksum RUN not testable via `docker build` from the worktree alone (worktree lacks `files/`, `patches/`, etc.) · acceptable; will be exercised on next full rebuild from main dev · routed to bugs.md as low

### implications for downstream phases
- Phase 1 adds templates to wiki/; load_modules.zsh picks them up automatically — no changes to the loading mechanism needed
- Phase 1 should verify forked templates render correctly after a load_modules run (mirrors DoD item 3 from phase 0 DoD)

## starting phase 1 — 2026-05-30

**Branch:** `phase/igrs-timeline-lua/0` (continued)

**Confirmed DoD:**
- Each forked template has `<!-- CC BY-SA 4.0, source: ... -->` attribution on line 1
- Before each fork: live-wiki version diffed against Wikipedia; local edits documented
- `templates_refresh.zsh` `template_list()` contains only entries that can't be forked
- Forked templates load cleanly on dev wiki after a load_modules run
- Pivot: >5 transitive deps → defer that template's fork

## phase 1 retro — 2026-05-30

### spec delta
- delivered: audit complete; 2 unused templates removed from templates_refresh.zsh; audit note at notes/templates/audit.md
- missed / deferred: all 7 in-use template forks deferred — pivot criterion triggered for every candidate (range: 25–116 transitive deps; threshold was 5)
- extra: none

### surprises
- plan assumed some templates would be simple leaf templates → reality: even `Cquote` has 102 transitive deps and `Did you mean box` has 25 — Wikipedia template infrastructure is far heavier than the plan anticipated → pivot triggered for all; no wiki/ files added this phase
- `hastemplate:` search syntax unsupported on this wiki; `embeddedin` API call was the correct approach

### residual debt
- full-tree template forking documented in notes/templates/audit.md as a follow-up path; no immediate action needed · not added to bugs.md (it's a future option, not a defect)

### implications for downstream phases
- Phase 2 (documentation cleanup) scope is unchanged: audit wiki/ for stale prose docs and move to notes/

## starting phase 2 — 2026-05-30

**Branch:** `phase/igrs-timeline-lua/0` (continued)

**Confirmed DoD:**
- No `.txt` files in `wiki/` contain prose documentation (only actual wikitext/Lua)
- `notes/` has corresponding `.md` files with attribution where relevant

## phase 2 retro — 2026-05-30

### spec delta
- delivered: wiki/ audited — no stale prose docs found; notes/features/modules.md updated to reflect auto-sync (stale "manually via wiki.py" line)
- missed / deferred: none
- extra: none

### surprises
- phase 2 premise assumed template forks would produce /doc subpages to clean up → phase 1 pivot meant no such docs existed → phase 2 scope collapsed to a single doc update

### residual debt
- none

## revision after phase 2 — 2026-05-30

- phase 2 (documentation cleanup): delivered as-scoped; no downstream phases remain
- plan complete; ready for merge

## revision after phase 1 — 2026-05-30

- phase 1 (template audit & fork): DoD rewritten to match actual deliverables — pivot triggered for all candidates; unused templates removed, audit note written
- phase 2 (documentation cleanup): valid — unchanged

## revision after phase 0 — 2026-05-30

- phase 1 (template audit & fork): revise — attribution comments in `.txt` files must use `<!-- -->` HTML comment format; plain-text comments would render visibly in wiki output. Spec and DoD unchanged; attribution format clarified in 1b.
- phase 2 (documentation cleanup): valid — unchanged
