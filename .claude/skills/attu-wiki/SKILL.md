---
name: attu-wiki
description: Query the Attu Project wiki (https://attuproject.org/) via its MediaWiki API and parse wikitext with mwparserfromhell. Use when the user asks about Attu Project lore, nations, characters, places, infobox fields, categories, or otherwise wants to look something up or extract structured data from attuproject.org.
---

# Attu Project wiki — MediaWiki API + mwparserfromhell

The Attu Project (https://attuproject.org/) runs MediaWiki 1.44 with the Citizen skin. It exposes the standard MediaWiki Action API.

This project already has all requirements installed. prefer the Python workflow over raw curl + regex when you need anything beyond a one-shot lookup.

## First reach: `scripts/misc/wiki.py`

For the common operations, **do not write Python from scratch**. `scripts/misc/wiki.py` wraps them as subcommands. Run with the project venv:

```bash
uv run scripts/misc/wiki.py <subcommand> [args]
```

Subcommands (`--help` on any for flags):

| Command | Purpose |
|---|---|
| `wikitext <title>` | Raw wikitext (follows redirects). |
| `extract <title> [--intro]` | Plaintext, optionally lede only. |
| `infobox <title> [--format tsv|json]` | First `Infobox*` template as `{field: value}`. JSON by default. |
| `members <category> [--limit N]` | Paginated category walk; `Category:` prefix optional. `--limit 0` = all (default). |
| `categories <title>` | Categories the page belongs to (paginated). |
| `search <query> [--limit N] [--namespace ID] [--format tsv|json]` | Full-text search. Use `--namespace 1` for Meta. |
| `opensearch <prefix> [--limit N]` | Title autocomplete. |
| `exists <title>...` | Bulk existence check; titles via args or stdin. Exit 1 if any missing. |
| `batch <title>... \| --from-category <cat>` | Bulk wikitext as `{title: wikitext}` JSON. Reads stdin if no args. |
| `url <title>...` | Print canonical wiki URL(s). |

Examples:

```bash
uv run scripts/misc/wiki.py extract "Kingdom of Tietero" --intro
uv run scripts/misc/wiki.py infobox "Kingdom of Tietero"
uv run scripts/misc/wiki.py members "Tietero pages" | head
uv run scripts/misc/wiki.py batch --from-category "Tietero pages" > /tmp/tietero.json
printf 'Zamenhof\nAvanguardo\n' | uv run scripts/misc/wiki.py exists
```

The script handles UA headers, `formatversion=2`, `redirects=1`, normalization, `continue` pagination, and 50-title batching for you. Drop into the raw Python below only when you need an operation the CLI does not cover (e.g. `recentchanges`, `action=parse` HTML, link graph traversal, edit attempts).

## Endpoint and gotchas

- **API endpoint:** `https://attuproject.org/api.php` (note: **not** `/w/api.php` — that path returns 403).
- **Article URL pattern:** `https://attuproject.org/wiki/<Title_With_Underscores>`.
- **User-Agent is mandatory.** The site returns `403 Forbidden` to default `curl`, `wget`, and Claude Code's `WebFetch` tool. Always send a real browser/identifying UA. Because of this, **prefer `curl` via Bash (or `requests`) over the WebFetch tool** for this site.
- **Titles:** spaces become `_` or `%20`; the API normalizes either. Case-sensitive after the first letter (`case=first-letter`).
- **Format:** pass `format=json` and prefer `formatversion=2` (cleaner shape: list-shaped `pages`, content under `content` instead of `*`).
- **Read-only access is anonymous.** No login or token needed for `query`/`parse`/`opensearch`.

## Python workflow (preferred)

Always invoke with the project venv: `uv run script.py` (or `uv run -` for stdin).

A small reusable client — copy into a script or paste into `uv run -`:

```python
import requests
import mwparserfromhell as mwp

API = "https://attuproject.org/api.php"
S = requests.Session()
S.headers["User-Agent"] = "tietero-tools/1.0 (jhn, attuproject)"

def _get(**params):
    params.setdefault("format", "json")
    params.setdefault("formatversion", 2)
    r = S.get(API, params=params, timeout=20)
    r.raise_for_status()
    return r.json()

def search(query, limit=10):
    """Full-text search. Returns list of {title, pageid, snippet, timestamp, ...}."""
    return _get(action="query", list="search",
                srsearch=query, srlimit=limit)["query"]["search"]

def suggest(query, limit=10):
    """Fast title autocomplete via opensearch. Returns list of titles."""
    return _get(action="opensearch", search=query, limit=limit)[1]

def page_wikitext(title):
    """Raw wikitext of the latest revision, or None if the page is missing."""
    data = _get(action="query", prop="revisions", rvprop="content",
                rvslots="main", titles=title, redirects=1)
    page = data["query"]["pages"][0]
    if page.get("missing"):
        return None
    return page["revisions"][0]["slots"]["main"]["content"]

def page_plaintext(title, intro_only=False):
    """Plaintext extract (no wiki markup). intro_only=True returns just the lede."""
    params = dict(action="query", prop="extracts", explaintext=1,
                  titles=title, redirects=1)
    if intro_only:
        params["exintro"] = 1
    page = _get(**params)["query"]["pages"][0]
    return None if page.get("missing") else page.get("extract", "")

def page_html(title):
    """Rendered HTML via action=parse."""
    return _get(action="parse", page=title, prop="text")["parse"]["text"]

def parse(title):
    """Fetch wikitext and return a parsed mwparserfromhell Wikicode tree."""
    text = page_wikitext(title)
    return mwp.parse(text) if text is not None else None
```

### Pulling structured data out of wikitext

`mwparserfromhell` is the right tool for: infoboxes, link graphs, categories, sections. Don't regex wikitext — templates nest and quotes get hairy fast.

```python
code = parse("Attu Archipelago")

# 1. Plain text view (strips markup, links, templates)
print(code.strip_code())

# 2. Read an infobox
for tpl in code.filter_templates():
    name = tpl.name.strip().lower()
    if name.startswith("infobox"):
        for p in tpl.params:
            print(f"{p.name.strip()} = {p.value.strip_code().strip()}")

# 3. Helper to read a single infobox field safely
def infobox_field(code, field, template_prefix="infobox"):
    for tpl in code.filter_templates():
        if tpl.name.strip().lower().startswith(template_prefix):
            if tpl.has(field):
                return tpl.get(field).value.strip_code().strip()
    return None

# 4. Outgoing wikilinks (targets only, deduped, drops files/categories)
links = {str(w.title).split("#")[0].strip()
         for w in code.filter_wikilinks()
         if not str(w.title).lower().startswith(("file:", "category:", "image:"))}

# 5. Categories the page belongs to
cats = [str(w.title).split(":", 1)[1].strip()
        for w in code.filter_wikilinks()
        if str(w.title).lower().startswith("category:")]

# 6. Iterate top-level sections
for sec in code.get_sections(levels=[2], include_lead=True):
    headings = sec.filter_headings()
    title = headings[0].title.strip() if headings else "(lead)"
    body = sec.strip_code().strip()
    print(f"--- {title} ---\n{body[:200]}\n")
```

### Common pipelines

- **"What does the wiki say about X?"** → `suggest(X)` to resolve title, then `page_plaintext(title, intro_only=True)` for a summary.
- **"List all nations / characters / etc."** → `category_members("Category:Nations")` (see below), then batch-fetch with `titles="A|B|C"` (up to 50 per request).
- **"Pull infobox fields for every place"** → category walk + `parse()` + `infobox_field()`.
- **"What links to / from page X?"** → `filter_wikilinks()` on `parse(X)` for outgoing; `action=query&list=backlinks&bltitle=X` for incoming.

```python
def category_members(category, limit=500):
    """Yield titles in a category. category includes the 'Category:' prefix."""
    cont = {}
    while True:
        data = _get(action="query", list="categorymembers",
                    cmtitle=category, cmlimit=min(limit, 500), **cont)
        for m in data["query"]["categorymembers"]:
            yield m["title"]
        if "continue" not in data:
            return
        cont = data["continue"]

def batch_wikitext(titles):
    """Fetch wikitext for up to 50 titles in a single call."""
    data = _get(action="query", prop="revisions", rvprop="content",
                rvslots="main", titles="|".join(titles), redirects=1)
    out = {}
    for page in data["query"]["pages"]:
        if page.get("missing"):
            continue
        out[page["title"]] = page["revisions"][0]["slots"]["main"]["content"]
    return out
```

## Curl recipes (for quick shell exploration)

Set a UA env var once:

```bash
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
```

Then any of:

```bash
# Full-text search
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&list=search&srsearch=Attu&srlimit=5&format=json&formatversion=2"

# Title autocomplete
curl -sS -A "$UA" "https://attuproject.org/api.php?action=opensearch&search=attu&limit=10&format=json"

# Plaintext intro
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&prop=extracts&exintro=1&explaintext=1&titles=Attu_Archipelago&format=json&formatversion=2"

# Raw wikitext
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&titles=Attu_Games&format=json&formatversion=2"

# Rendered HTML
curl -sS -A "$UA" "https://attuproject.org/api.php?action=parse&page=Attu_Games&prop=text&format=json&formatversion=2"

# Category members
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&list=categorymembers&cmtitle=Category:Sport&cmlimit=50&format=json&formatversion=2"

# Recent changes
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&list=recentchanges&rclimit=20&rcprop=title|timestamp|user|comment&format=json&formatversion=2"
```

`srsearch` snippets contain `<span class="searchmatch">…</span>` — strip them with `re.sub(r"<[^>]+>", "", snippet)` if you want clean text.

## Meta namespace (out-of-universe)

The wiki's namespace 1 (MediaWiki's `Talk` namespace) has been renamed to **`Meta`**. It holds out-of-universe content: author commentary on articles, behind-the-scenes notes, jokes. Keep it distinct from in-universe lore when answering.

- **Namespace ID:** `1`. The canonical name is still `Talk` and `Talk` is registered as a namespace alias, so `Talk:Foo` and `Meta:Foo` resolve to the same page. Always write `Meta:` in titles and URLs you surface to the user, since that is the current display name.
- **Title pattern:** `Meta:<Article Title>`, mirroring the main-namespace article it comments on. URL: `https://attuproject.org/wiki/Meta:<Title_With_Underscores>`.
- **Existence is not guaranteed.** Unlike conventional talk pages, only a subset of articles have a Meta counterpart; check before quoting.

### Check whether a Meta page exists

Use `prop=info` and read the `missing` flag; `page_wikitext()` also returns `None` for missing pages.

```python
def meta_exists(title):
    """True if Meta:<title> exists. Pass the main-article title, no prefix."""
    data = _get(action="query", prop="info",
                titles=f"Meta:{title}", redirects=1)
    return not data["query"]["pages"][0].get("missing", False)

def meta_wikitext(title):
    """Wikitext of Meta:<title>, or None if it doesn't exist."""
    return page_wikitext(f"Meta:{title}")
```

### List or search Meta pages

```python
def meta_pages(limit=500):
    """Yield every title in the Meta namespace (already prefixed with 'Meta:')."""
    cont = {}
    while True:
        data = _get(action="query", list="allpages",
                    apnamespace=1, aplimit=min(limit, 500), **cont)
        for p in data["query"]["allpages"]:
            yield p["title"]
        if "continue" not in data:
            return
        cont = data["continue"]

def meta_search(query, limit=10):
    """Full-text search restricted to Meta (namespace 1)."""
    return _get(action="query", list="search", srsearch=query,
                srnamespace=1, srlimit=limit)["query"]["search"]
```

Curl equivalents:

```bash
# Existence check (look for "missing": true on the page object)
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&prop=info&titles=Meta:Avanguardo&format=json&formatversion=2"

# Raw wikitext of a Meta page
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&titles=Meta:Avanguardo&format=json&formatversion=2"

# List every Meta page
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&list=allpages&apnamespace=1&aplimit=50&format=json&formatversion=2"

# Search within Meta only
curl -sS -A "$UA" "https://attuproject.org/api.php?action=query&list=search&srsearch=joke&srnamespace=1&srlimit=10&format=json&formatversion=2"
```

When citing Meta content, label it as out-of-universe commentary; do not blend it into in-universe descriptions.

## Tips and pitfalls

- **Resolve the title before fetching.** If the user gives a fuzzy phrase, run `suggest()` or `search(limit=1)` first, then use the canonical title for content calls. Always pass `redirects=1` to follow redirects automatically.
- **Wikitext > HTML for facts.** Infoboxes are `{{Template|key=value}}`; mwparserfromhell parses them cleanly. The rendered HTML wraps them in nested `<table>`s.
- **Batch up to 50 titles** with pipe-separated `titles=A|B|C` — far cheaper than N round-trips.
- **Pagination:** when a response includes a top-level `continue` object, pass its fields back on the next request (`**data["continue"]`). The `category_members` helper above shows the pattern.
- **Don't hammer it.** This is a small community wiki — keep batches modest and cache locally if you're doing more than a handful of reads.
- **Read-only.** This skill does not cover editing. `action=edit` requires login, a CSRF token, and is out of scope here.
