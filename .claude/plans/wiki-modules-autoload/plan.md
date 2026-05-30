# Plan: wiki-modules-autoload

**Worktree:** `igrs-timeline-lua`  
**Slug:** `wiki-modules-autoload`

## Context

The `wiki/` directory tracks Lua modules, templates, and a data subpage that collectively power the IGRS timeline and Attu calendar features. Currently the directory is NOT included in the scheduler image and must be pushed to the wiki manually with `wiki.py`. The goal is to make the image self-contained and auto-sync `wiki/` on every `update` run, so a rebuild + redeploy is sufficient to roll out any module change.

A secondary goal is to pull the in-use Wikipedia templates out of the runtime `templates_refresh` chore and into the repo itself (forked with attribution), so template content is also version-controlled.

---

## Phase 0 — Plumbing: Dockerfile · load_modules.zsh · entry.zsh (Walking Skeleton)

**Status:** pending merge  
**Retires:** "does the auto-sync mechanism work end-to-end?"

### 0a. Dockerfile — add `wiki/` to scheduler image

In `mediawiki.Dockerfile`, scheduler stage, after the existing `COPY ./scripts` line:

```dockerfile
COPY --chown=doom:doom ./wiki $USER_HOME/wiki
RUN sha256sum $(find $USER_HOME/wiki -type f | sort) \
    > $USER_HOME/wiki/.checksums
```

### 0b. `scripts/chores/load_modules.zsh` — new script

Pattern follows existing chores (`templates_refresh.zsh`, `spam_list_refresh.zsh`). Header/license block matches.

**All paths must be absolute.** `load_modules.zsh` is called from `entry.zsh` after `cd "$APP_HOME/mediawiki"`, so relative paths resolve against `/app/mediawiki`. Use `$USER_HOME` throughout. The venv and wiki.py live at:
- `$USER_HOME/.venv/bin/python`
- `$USER_HOME/misc/wiki.py` ← the Dockerfile does `COPY ./scripts $USER_HOME/`, copying *contents* of `scripts/` directly; `scripts/misc/wiki.py` → `$USER_HOME/misc/wiki.py`
- `$USER_HOME/wiki/` ← new COPY from 0a

**Title mapping** from `$USER_HOME/wiki/<NS>/<Page>.<ext>`:
- `wiki/Main/<path>.txt` → page title = `<path>` (no namespace prefix)
- `wiki/<NS>/<path>.<ext>` → page title = `<NS>:<path>` (underscores in NS kept as-is; MediaWiki normalises)
- Subpages: inner `/` in `<path>` stays as `/`

**Diff/skip mechanism — build-time checksums + volume-persisted applied record:**
`load_modules.zsh` runs inside `job-update`, which starts *before* the `mediawiki` web service (docker-compose `depends_on` ordering). The wiki HTTP API is unreachable at that point, so `wiki.py wikitext` cannot be used for diff checking.

The Dockerfile generates `$USER_HOME/wiki/.checksums` (baked into image — authoritative for this build). At runtime:

1. Read `$USER_HOME/wiki/.checksums` (baked into image).
2. Read `$APP_HOME/mediawiki/images/load_modules.sha256` (volume-persisted record of last-applied checksums; may not exist on first run).
3. For each page, if the image checksum matches the applied record → `skipped <title>`.
4. If different or not yet applied → push, then write the new checksum into the applied record.

The `images/` directory is on the `attu-prod-images` named volume, shared by both `job-update` and `scheduler`. Survives container restarts. If the volume is wiped, all pages re-push once (acceptable).

**Push:** use the maintenance-script pattern matching existing chores:
```zsh
sudo --preserve-env -u www-data -- \
    php maintenance/run.php edit \
        -u Doom \
        -s "load_modules: sync" \
        "$title" \
        < "$local_file"
```
Note: `<title>` is a **positional argument**, not a flag. Run from `$APP_HOME/mediawiki` (cwd is already correct when called from entry.zsh).

> **Probes confirmed (2026-05-30):**
> - Title is positional: `php maintenance/run.php edit -u USER -s SUMMARY "Page Title" < file`
> - User "Doom" exists and is valid
> - Identical push outputs "edit was ignored, no change" — no duplicate revision created (MediaWiki deduplicates natively)

**Output:** one line per page: `skipped <title>` or `updated <title>`.

### 0c. `scripts/entry.zsh` — call load_modules after update

```zsh
"update")
cd "$APP_HOME/mediawiki"
php maintenance/run.php update --quick
zsh "$USER_HOME/chores/load_modules.zsh"
;;
```

### 0d. `scripts/attu_tasks.zsh` — add chore dispatch entry

```zsh
'chore:load-modules')
printf '%s\n' "Running chore: sync wiki modules from repo"
zsh -eu "$USER_HOME/chores/load_modules.zsh" && send_success
;;
```

### DoD — Phase 0

- `docker compose run job-update` on dev pushes all 5 wiki/ files (or logs "skipped" for unchanged ones)
- Running job-update a second time with no wiki/ changes logs "skipped" for all 5 pages (idempotency)
- A content change to any wiki/ file results in exactly one new wiki revision after the next update run
- Scheduler image builds without error with the new COPY line
- **Probe confirmed:** `maintenance/run.php edit` flags match plan; "Doom" user exists in wiki DB
- **Pivot:** if two consecutive identical runs both create new revisions and the checksum file can't be reached from the update container, move load_modules invocation to a `@reboot` cron entry in the scheduler (where the API is available) instead of entry.zsh

---

## Phase 1 — Template Audit & Fork

**Status:** pending merge  
**Retires:** "which templates can move into the repo, and what's the licensing overhead?"

### 1a. Identify in-use templates

For each template in `templates_refresh.zsh`'s `template_list()`, check the live wiki for transclusion:
- Use `wiki.py search "insource:/Template:Foo/" --namespace 0` or `wiki.py members` on hidden tracking categories.
- The 9 candidates: `Composition bar`, `Taxobox`, `Did you mean box`, `Infobox military unit`, `Infobox`, `MessageBox`, `Color box`, `Main`, `Cquote`.

### 1b. Licensing

All Wikipedia content is CC BY-SA 4.0. Forking templates requires:
- Attribution comment in each forked file using HTML comment syntax (`<!-- CC BY-SA 4.0, source: https://en.wikipedia.org/wiki/Template:Name -->`), which is invisible in rendered wikitext. Plain-text comments would appear in the rendered page.
- A `ATTRIBUTION.md` note in `wiki/Template/` listing all forked sources.

No viral concern for our wiki's own content (CC BY-SA → CC BY-SA is fine).

### 1c. Dependency trees

Wikipedia templates have transitive deps (e.g. `Infobox` pulls `Infobox/row`, `Nowrap`, `Delink`…). Options:
1. **Fork only leaf no-dep templates** (e.g. `Cquote`, `Color box`, `Did you mean box`) and leave complex trees to `templates_refresh`.
2. **Fork full trees** using Special:Export with `templates=1` to discover all deps, then add every dep file to `wiki/Template/`.

Lean toward option 1 for phase 1; option 2 is a follow-up if the refresh chore becomes a maintenance burden.

### 1d. Update `templates_refresh.zsh`

Remove forked entries from `template_list()`. If a forked template had complex deps that are still needed, keep just the deps.

### 1e. File placement

Forked templates land in `wiki/Template/<Name>.txt` (matching existing `TimelineBar.txt`). They are automatically picked up by `load_modules.zsh`.

### DoD — Phase 1

- Audit complete: in-use vs unused classified for all 9 templates
- Unused templates removed from `templates_refresh.zsh` `template_list()`
- Audit findings documented at `notes/templates/audit.md`
- All in-use template forks deferred (pivot triggered: range 25–116 transitive deps); follow-up path documented in audit note

---

## Phase 2 — Documentation Cleanup

**Status:** not started  
**Retires:** "are there stale docs / template READMEs cluttering the repo?"

### 2a. Audit for stale docs

Search for: any `.txt` files in `wiki/` that are pure documentation rather than wikitext pages, any top-level `README` or `NOTES` files that duplicate `notes/`, any template `/doc` subpages that were accidentally committed.

### 2b. Move + convert

For each stale doc:
- Convert to Markdown.
- Add a `_Source:_ <original URL>` line at the top if sourced externally.
- Move to `notes/` under an appropriate subdirectory (`notes/templates/`, etc.).
- Delete the original.

### DoD — Phase 2

- No `.txt` files in `wiki/` contain prose documentation (only actual wikitext/Lua)
- `notes/` has corresponding `.md` files with attribution where relevant

---

## Accepted Risks

- `maintenance/run.php edit` pattern mirrors existing chores; if MediaWiki accessibility from the update container breaks, all chores break equally.
- Forking Wikipedia templates with complex CSS/JS deps may require additional subpages; scoped to leaf templates with ≤5 transitive deps in phase 1.
- Checksum file lives in `images/` volume; if the volume is wiped, all pages re-push once on next run (acceptable — produces valid wiki revisions).

---

## Verification

1. `docker compose -f docker-compose.dev.yml run job-update` — observe load_modules.zsh output; confirm all 5 pages logged.
2. Edit one wiki/ file locally, rerun job-update — confirm only that page is updated (others logged "skipped").
3. Browse dev wiki for each forked template — confirm rendering matches prod.
4. `templates_refresh.zsh` dry-run on dev — confirm removed entries are gone, no error.
