commit-message conventions for this repo: conventional commits, lowercase, no body.

## message format

`type(scope): description`, all lowercase, no body.

| type | meaning |
|---|---|
| `feat` | addition; also used for removals and intentional behavior changes with negative or ironic framing |
| `fix` | actual bug |
| `patch` | minor tweak that is not a bug (wording, small tuning, typo) |
| `refactor` | structural change with no behavior change |
| `chore` | linting, formatting, housekeeping; always isolated from other work |
| `test` | tests added or changed without changing the thing under test |

**scope**: the most relevant one when multiple are touched; pick the primary, do not list them.

**description**: plain noun phrases or casual statements. describe what changed, not what was done to achieve it. no formal imperative verbs (`implement`, `introduce`, `centralize`). personality and humor where it fits naturally; do not force it.

## examples

```
fix(hatch): enable one week early; i'm impatient :tieteran:   ← honest why via semicolon
chore: oops all linting fixes                                  ← owns the mistake
fix(wiki): lookup buttons don't die on restart                 ← the bug, not the fix
fix(modlog): bot users were ignored in kick/ban messages       ← same
feat(hatch): trading and collection info                       ← noun phrase, not "implement trading"
patch(hatch): fix up responses and progress message length     ← minor tweak
feat(hatch): less aggressive trade timeout                     ← ironic feat for a behavior change
feat(hatch): no more screaming snakes                          ← negative framing for a removal
```

## when to commit

do not create commits unless explicitly asked to. finish the work first; ask if the scope is unclear.

the working tree will often have changes from multiple tasks in progress at once. that is fine; deployment only happens from a clean tree, so intermediate states do not matter. the job is to pick out the hunks that belong together and commit them as one complete unit.

## what makes a unit complete

| change type | unit |
|---|---|
| `feat` | implementation + tests + notes/docs + config/assets, all in one; done when the thing it describes is actually done, not when the code compiles |
| `fix` / `patch` | the change itself plus any test that covers it; if making it work right required touching the DB layer or a script, that goes in too |
| `refactor` | every file that references the thing being changed, swept in one commit; no partial refactors left dangling |
| data / config | minimal: just the value and its docs; nothing else |
| `chore` | linting and formatting never ride along with other work; collect them separately |
| `test` | can go in with the feature it covers, or as a standalone commit filling coverage later; both are fine. if no tests are included, add a to-do entry in the test section |

after a large feature commit, small `fix` or `patch` commits for issues that surface in use are normal and expected; do not try to anticipate everything upfront.

## see also

- [../agents.md](../agents.md) - rule 3: do not create commits without being explicitly asked
- [../.meta.md](../.meta.md) - notes-system conventions

---

## metadata

```yaml
last_updated: 24 May 2026
```
