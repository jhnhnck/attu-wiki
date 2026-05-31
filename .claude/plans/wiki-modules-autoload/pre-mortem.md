# Pre-mortem — wiki-modules-autoload

**Bottom line:** proceed with revisions *(revisions folded into plan.md)*

---

### Risks

- [high] **integration** — `wiki.py wikitext` calls the live wiki HTTP API, but `load_modules.zsh` runs inside `job-update` *before* the `mediawiki` service starts (docker-compose: `mediawiki depends_on job-update`). The API is unreachable at that moment. **Resolution:** replaced with build-time checksum file; no API call needed at update time.

- [high] **premise** — wiki.py path inside the container is wrong. The Dockerfile does `COPY ./scripts $USER_HOME/` which copies the *contents* of `scripts/` directly into `$USER_HOME/`. Plan references `$USER_HOME/scripts/misc/wiki.py`; real container path is `$USER_HOME/misc/wiki.py`. **Resolution:** corrected in plan.

- [high] **integration** — `entry.zsh update` does `cd "$APP_HOME/mediawiki"` before calling load_modules.zsh; relative paths inside the script would resolve against `/app/mediawiki`. **Resolution:** plan now specifies all absolute paths using `$USER_HOME`.

- [medium] **dependency** — `php maintenance/run.php edit` flags (`--title`, `--user`, stdin) need verification against MediaWiki 1.44. · probe: run `php maintenance/run.php edit --help` in the mediawiki container.

- [medium] **dependency** — `maintenance/run.php edit` may create a new revision even for content-identical pushes. · probe: push a page twice in succession; confirm whether two revisions appear in wiki history.

- [medium] **premise** — `--user "Doom"` assumes this wiki user exists. · probe: check `SELECT user_name FROM user WHERE user_name='Doom'` on the dev DB.

- [medium] **scope** — Wikipedia "leaf template" assumption may not hold; `Color box` and `Cquote` may pull transitive deps. · probe: Special:Export `Template:Cquote` with `templates=1`, count pages returned.

- [medium] **operational** — Live wiki templates may have been manually edited since last `templates_refresh` import; forking from Wikipedia would overwrite local changes. · probe: diff live-wiki version vs current Wikipedia for each candidate before forking.

- [low] **premise** — Trailing newline handling: `wiki.py wikitext` appends `\n`; comparison must normalize trailing whitespace to avoid spurious pushes.

- [low] **scope** — `WIKI_TARGET` env var switching not needed in phase 0 (no API calls); note for future extension only.

- [low] **scope** — Phase 2 cleanup scope is unknown until phase 1 lands; may be trivially small or grow with forked templates.

---

### Walking-skeleton check

Phase 0 is the walking skeleton and correctly touches every layer (image build, new script, entry point, chore dispatch). The API-unreachability risk was a blocker; resolved by switching to the build-time checksum approach.

---

### Phase-order revisions

No reordering needed. Phase 0 → 1 → 2 is risk-first order.

---

### Definition-of-done additions (folded into plan.md)

- **Phase 0** — probe `maintenance/run.php edit` flags; idempotency test (second run logs all "skipped"); pivot criterion if duplicate revisions appear.
- **Phase 1** — diff each candidate against Wikipedia before forking; pivot criterion if >5 transitive deps.
