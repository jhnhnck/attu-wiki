open work items for the Attu wiki repo, grouped by area; see [format](#format) for tag conventions.

## tasks

### config

- :o: `medium priority` `low effort` route the Parsoid render stash through Redis and lengthen its TTL: set `$wgParsoidCacheConfig['StashType'] = CACHE_REDIS;` and `$wgParsoidCacheConfig['StashDuration'] = 7 * 24 * 60 * 60;` in `config/LocalSettings.php`. default is `CACHE_DB` + 24h, which produces the "No stashed content found" 412 in NWE/VE save dialogs after a day. full root-cause investigation in [`notes/issues/drafts-stash-not-the-cause.md`](issues/drafts-stash-not-the-cause.md); Drafts extension is innocent and the UUID "non-uniqueness" was just normal UUID v1 structure
- :o: `medium priority` `low effort` move misplaced `Record:_*` pages from `NS_MAIN` into `NS_RECORD` (102); two known: `Record:_On_Passports`, `Record:_The_Sound_Heard_Across_La_Rossa`. worth grepping `page` for other `page_namespace=0 AND page_title LIKE '%:%'` rows whose prefix matches a defined namespace
- :o: `low priority` `medium effort` deny IP block list from Cloudflare in Caddyfile (`config/Caddyfile:61`)

### docker

- :o: `medium priority` `high effort` project-root reorganization; see [`notes/plans/wiki-root-reorg.md`](plans/wiki-root-reorg.md) (post-migration)
- :o: `low priority` `low effort` remove git objects/modules after NovaDiscord clone in prod build (`mediawiki.Dockerfile:199`)
- :o: `low priority` `high effort` port doom-bot `deploy.py` pattern to wiki repo (version bump, tag, ff-merge dev → trunk, build, health-check, push, rollback)
- :o: `low priority` `medium effort` publish FamilyTreeEditor to a repo prod can clone at build time, then drop the dev-only `Caddyfile.trees` gate
- :o: `low priority` `low effort` verify host caddy GID matches `976` after server migration (`scripts/chores/certbot_renew.zsh`)

### search

- :o: `medium priority` `medium effort` browser search suggestion API not returning suggestions; investigate OpenSearch / `api.php?action=opensearch` endpoint that the browser address bar and search box query for autocomplete

### upstream

- :o: `low priority` `low effort` file MediaWiki search `PreconditionException` issue ([`notes/issues/mediawiki-search-precondition.md`](issues/mediawiki-search-precondition.md))

### wiki

- :o: `low priority` `low effort` delete Phase 0 probe pages (`Module:TimelineTest`, `Project:TimelineTest`, `Project:OsTest`) from dev and prod wikis — 🎯 carried in from plan: igrs-timeline-lua (2026-05-31)

### recurring

- `high priority` `low effort` assign any to-dos without an effort or category; update priorities; move completed and sort all

## completed

## format

open item: `- :o: \`priority\` \`effort\` description`

completed item: `- :red_circle: \`26 March 2026\` description`

priority levels (highest to lowest): `high priority`, `medium priority`, `low priority`, `future idea`

effort levels: `no effort`, `low effort`, `medium effort`, `high effort`, `very high effort`

items without a checkbox are recurring; they repeat each maintenance cycle rather than being tracked as one-time work. these live in the `## tasks` > `### recurring` subsection.

when an item is completed, move it to the `## completed` section under the appropriate category, strip the priority/effort tags, and add a date stamp. sort completed entries chronologically within each category (oldest first). remove completed entries that are no longer relevant and not referenced by any open to-do. increment `total_completed` in the metadata each time an item is marked done.

when adding a new item, sort it into the appropriate section by topic, or add a new section if none fits. assign priority and effort tags. if the scope, priority, or effort is unclear, ask clarifying questions before adding. split larger projects into multiple entries.

## sections

| section | purpose |
|---|---|
| `## tasks` | active items grouped by area; sorted within each section by priority (high first) |
| `## completed` | done items kept for reference; sorted chronologically; pruned when no longer relevant |
| `## format` | tag conventions and rules for moving items between sections |
| `## sections` | what each top-level section is for |

## see also

- [.template.to-do.md](.template.to-do.md) - starter template for a new to-do list
- [.meta.md](.meta.md) - notes-system conventions

---

## metadata

```yaml
last_updated: 24 May 2026
total_completed: 0
```
