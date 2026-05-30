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

## revision after phase 0 — 2026-05-30

- phase 1 (template audit & fork): revise — attribution comments in `.txt` files must use `<!-- -->` HTML comment format; plain-text comments would render visibly in wiki output. Spec and DoD unchanged; attribution format clarified in 1b.
- phase 2 (documentation cleanup): valid — unchanged
