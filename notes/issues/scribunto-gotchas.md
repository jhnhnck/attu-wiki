confirmed Scribunto/Lua constraints and gotchas for MediaWiki module development on this wiki.

## mediawiki sanitizer blocks `<svg>` from all scribunto output paths

`svg` is not in `$htmlpairsStatic`. tested across all five output paths — `mw.html` builder, raw string return, `frame:extensionTag`, `tostring(mw.html.create(...))`, and template expansion — all produce escaped `&lt;svg&gt;` text in the DOM, not a live element.

also blocked: `img` data-URIs (`img` not in the HTML allowlist).

**what works:** CSS-div layout using `position:absolute`, `position:relative`, `background:`, and pixel dimensions (`width:`, `height:`, `left:`, `top:`). all survive sanitization unchanged. this is the correct approach for any visual widget (charts, timelines, progress bars) produced by a Lua module.

reference: `Module:Timeline` (igrs-timeline-lua plan) uses CSS-div throughout.

## `frame:getParent().args` is truthy even with no parent args

when a module is invoked directly via `{{#invoke:Module|func}}` (not from inside a template), `frame:getParent()` still returns a frame object. its `.args` is an empty table — truthy in Lua — not nil.

the naive guard fails silently:

```lua
-- WRONG: always true; can't distinguish "no parent" from "parent with args"
if frame:getParent().args then
    -- ...
end
```

use `next()` to test for at least one key:

```lua
local parent_args = frame:getParent() and next(frame:getParent().args) and frame:getParent().args
if parent_args then
    -- only runs when there are actual parent args
end
```

or merge parent args defensively:

```lua
local args = frame.args
local parent = frame:getParent()
if parent and next(parent.args) then
    for k, v in pairs(parent.args) do args[k] = args[k] or v end
end
```

this bit `Module:Timeline` during Phase 1 of igrs-timeline-lua; the `next()` guard is now in `M.main`.

## see also

- [drafts-stash-not-the-cause.md](drafts-stash-not-the-cause.md) - other MediaWiki 1.44 issue investigated locally

---

## metadata

```yaml
last_updated: 31 May 2026
```
