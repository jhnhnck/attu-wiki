#!/usr/bin/env python3
"""Attu Project wiki CLI.

Run with the project venv: ./.venv/bin/python scripts/wiki.py <subcommand> ...

Subcommands wrap the operations that recur across sessions so each one no longer
needs the requests/mwparserfromhell boilerplate inlined.

Use --wiki dev to target dev.attuproject.org; the edit subcommand is only
available on the dev wiki.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Iterable, Iterator

import requests
import mwparserfromhell as mwp

WIKIS = {
    "prod": {
        "api": "https://attuproject.org/api.php",
        "wiki": "https://attuproject.org/wiki/",
    },
    "dev": {
        "api": "https://dev.attuproject.org/api.php",
        "wiki": "https://dev.attuproject.org/wiki/",
    },
}

# Set by main() based on --wiki; referenced by api() and title_url().
API = WIKIS["prod"]["api"]
WIKI = WIKIS["prod"]["wiki"]

UA = "tietero-tools/1.0 (jhn, attuproject)"

SESSION = requests.Session()
SESSION.headers["User-Agent"] = UA


def api(**params) -> dict:
    params.setdefault("format", "json")
    params.setdefault("formatversion", 2)
    r = SESSION.get(API, params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def paginate(**params) -> Iterator[dict]:
    """Yield successive `data` payloads, walking the MediaWiki `continue` cursor."""
    cont: dict = {}
    while True:
        data = api(**{**params, **cont})
        yield data
        if "continue" not in data:
            return
        cont = data["continue"]


def title_url(title: str) -> str:
    return WIKI + title.replace(" ", "_")


def chunks(seq: list, n: int) -> Iterator[list]:
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


def fetch_wikitext(titles: list[str]) -> dict[str, str | None]:
    """Return {title: wikitext or None if missing}. Batches up to 50 per call."""
    out: dict[str, str | None] = {t: None for t in titles}
    for batch in chunks(titles, 50):
        data = api(
            action="query",
            prop="revisions",
            rvprop="content",
            rvslots="main",
            titles="|".join(batch),
            redirects=1,
        )
        # Map normalized/redirected results back to the user-supplied titles.
        norm = {n["from"]: n["to"] for n in data["query"].get("normalized", [])}
        redir = {r["from"]: r["to"] for r in data["query"].get("redirects", [])}

        def resolve(t: str) -> str:
            t = norm.get(t, t)
            t = redir.get(t, t)
            return t

        by_title = {p["title"]: p for p in data["query"]["pages"]}
        for t in batch:
            page = by_title.get(resolve(t))
            if page is None or page.get("missing"):
                continue
            out[t] = page["revisions"][0]["slots"]["main"]["content"]
    return out


# ---------- auth (dev wiki only) ----------


def _login() -> str:
    """Authenticate and return a CSRF token. Reads WIKI_USERNAME / WIKI_PASSWORD."""
    username = os.environ.get("WIKI_USERNAME")
    password = os.environ.get("WIKI_PASSWORD")
    if not username or not password:
        print("edit requires WIKI_USERNAME and WIKI_PASSWORD env vars", file=sys.stderr)
        raise SystemExit(4)

    login_token = api(action="query", meta="tokens", type="login")["query"]["tokens"]["logintoken"]

    r = SESSION.post(API, data={
        "format": "json",
        "formatversion": "2",
        "action": "login",
        "lgname": username,
        "lgpassword": password,
        "lgtoken": login_token,
    }, timeout=30)
    r.raise_for_status()
    result = r.json()["login"]
    if result["result"] != "Success":
        print(f"login failed: {result['result']}", file=sys.stderr)
        raise SystemExit(4)

    return api(action="query", meta="tokens")["query"]["tokens"]["csrftoken"]


# ---------- subcommands ----------


def cmd_wikitext(args: argparse.Namespace) -> int:
    text = fetch_wikitext([args.title])[args.title]
    if text is None:
        print(f"missing: {args.title}", file=sys.stderr)
        return 1
    sys.stdout.write(text)
    if not text.endswith("\n"):
        sys.stdout.write("\n")
    return 0


def cmd_extract(args: argparse.Namespace) -> int:
    params = dict(
        action="query",
        prop="extracts",
        explaintext=1,
        titles=args.title,
        redirects=1,
    )
    if args.intro:
        params["exintro"] = 1
    page = api(**params)["query"]["pages"][0]
    if page.get("missing"):
        print(f"missing: {args.title}", file=sys.stderr)
        return 1
    sys.stdout.write(page.get("extract", ""))
    sys.stdout.write("\n")
    return 0


def cmd_infobox(args: argparse.Namespace) -> int:
    text = fetch_wikitext([args.title])[args.title]
    if text is None:
        print(f"missing: {args.title}", file=sys.stderr)
        return 1
    code = mwp.parse(text)
    for tpl in code.filter_templates():
        name = str(tpl.name).strip()
        if name.lower().startswith("infobox"):
            fields = {
                str(p.name).strip(): p.value.strip_code().strip()
                for p in tpl.params
            }
            if args.format == "json":
                print(json.dumps({"template": name, "fields": fields}, indent=2, ensure_ascii=False))
            else:
                print(f"# {name}")
                for k, v in fields.items():
                    print(f"{k}\t{v}")
            return 0
    print(f"no infobox found in: {args.title}", file=sys.stderr)
    return 2


def cmd_members(args: argparse.Namespace) -> int:
    cat = args.category
    if not cat.lower().startswith("category:"):
        cat = "Category:" + cat
    remaining = args.limit
    seen = 0
    for data in paginate(
        action="query",
        list="categorymembers",
        cmtitle=cat,
        cmlimit=min(500, remaining) if remaining else 500,
    ):
        for m in data["query"]["categorymembers"]:
            print(m["title"])
            seen += 1
            if remaining and seen >= remaining:
                return 0
    return 0


def cmd_categories(args: argparse.Namespace) -> int:
    out: list[str] = []
    for data in paginate(
        action="query",
        prop="categories",
        titles=args.title,
        redirects=1,
        cllimit=500,
    ):
        page = data["query"]["pages"][0]
        if page.get("missing"):
            print(f"missing: {args.title}", file=sys.stderr)
            return 1
        for c in page.get("categories", []):
            out.append(c["title"])
    for c in out:
        print(c)
    return 0


def _strip_html(s: str) -> str:
    return re.sub(r"<[^>]+>", "", s)


def cmd_search(args: argparse.Namespace) -> int:
    params = dict(
        action="query",
        list="search",
        srsearch=args.query,
        srlimit=min(args.limit, 50),
    )
    if args.namespace is not None:
        params["srnamespace"] = args.namespace
    hits = api(**params)["query"]["search"]
    if args.format == "json":
        print(json.dumps(hits, indent=2, ensure_ascii=False))
        return 0
    for h in hits:
        snippet = _strip_html(h.get("snippet", "")).replace("\n", " ")
        print(f"{h['title']}\t{snippet}")
    return 0


def cmd_opensearch(args: argparse.Namespace) -> int:
    data = api(action="opensearch", search=args.prefix, limit=args.limit)
    for t in data[1]:
        print(t)
    return 0


def cmd_exists(args: argparse.Namespace) -> int:
    titles = args.titles
    if not titles:
        titles = [line.strip() for line in sys.stdin if line.strip()]
    results: dict[str, bool] = {}
    for batch in chunks(titles, 50):
        data = api(
            action="query",
            prop="info",
            titles="|".join(batch),
            redirects=1,
        )
        norm = {n["from"]: n["to"] for n in data["query"].get("normalized", [])}
        redir = {r["from"]: r["to"] for r in data["query"].get("redirects", [])}
        by_title = {p["title"]: p for p in data["query"]["pages"]}
        for t in batch:
            resolved = redir.get(norm.get(t, t), norm.get(t, t))
            page = by_title.get(resolved)
            results[t] = bool(page and not page.get("missing"))
    rc = 0
    for t in titles:
        ok = results.get(t, False)
        print(f"{'EXISTS' if ok else 'missing'}\t{t}")
        if not ok:
            rc = 1
    return rc


def cmd_batch(args: argparse.Namespace) -> int:
    titles = args.titles
    if not titles:
        titles = [line.strip() for line in sys.stdin if line.strip()]
    elif args.from_category:
        cat = args.from_category
        if not cat.lower().startswith("category:"):
            cat = "Category:" + cat
        titles = []
        for data in paginate(
            action="query",
            list="categorymembers",
            cmtitle=cat,
            cmlimit=500,
        ):
            titles.extend(m["title"] for m in data["query"]["categorymembers"])
    out = fetch_wikitext(titles)
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def cmd_url(args: argparse.Namespace) -> int:
    for t in args.titles:
        print(title_url(t))
    return 0


def cmd_edit(args: argparse.Namespace) -> int:
    if args.wiki != "dev":
        print("edit: only allowed with --wiki dev", file=sys.stderr)
        return 4

    csrf = _login()

    if args.text is not None:
        text = args.text
    elif args.file:
        with open(args.file) as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    params: dict = {
        "action": "edit",
        "title": args.title,
        "token": csrf,
        "format": "json",
        "formatversion": "2",
    }
    if args.append:
        params["appendtext"] = text
    elif args.prepend:
        params["prependtext"] = text
    else:
        params["text"] = text

    if args.summary:
        params["summary"] = args.summary
    if args.section is not None:
        params["section"] = args.section
    if args.sectiontitle:
        params["sectiontitle"] = args.sectiontitle
    if args.minor:
        params["minor"] = "1"
    if args.bot:
        params["bot"] = "1"

    r = SESSION.post(API, data=params, timeout=30)
    r.raise_for_status()
    result = r.json()
    edit = result.get("edit", {})
    if edit.get("result") == "Success":
        print(f"ok: {args.title} (rev {edit.get('newrevid', '?')})")
        return 0
    print(f"edit failed: {result}", file=sys.stderr)
    return 3


# ---------- entrypoint ----------


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wiki",
        description="Attu Project wiki CLI (MediaWiki Action API wrapper).",
    )
    p.add_argument(
        "--wiki",
        choices=("prod", "dev"),
        default="prod",
        help="target wiki: prod (attuproject.org) or dev (dev.attuproject.org); default: prod",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("wikitext", help="raw wikitext of a page")
    s.add_argument("title")
    s.set_defaults(func=cmd_wikitext)

    s = sub.add_parser("extract", help="plaintext extract (no markup)")
    s.add_argument("title")
    s.add_argument("--intro", action="store_true", help="lede only")
    s.set_defaults(func=cmd_extract)

    s = sub.add_parser("infobox", help="extract first Infobox* template as fields")
    s.add_argument("title")
    s.add_argument("--format", choices=("tsv", "json"), default="json")
    s.set_defaults(func=cmd_infobox)

    s = sub.add_parser("members", help="list pages in a category (paginated)")
    s.add_argument("category", help="with or without the 'Category:' prefix")
    s.add_argument("--limit", type=int, default=0, help="0 = all (default)")
    s.set_defaults(func=cmd_members)

    s = sub.add_parser("categories", help="list categories a page belongs to")
    s.add_argument("title")
    s.set_defaults(func=cmd_categories)

    s = sub.add_parser("search", help="full-text search")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=10)
    s.add_argument("--namespace", type=int, default=None,
                   help="restrict to namespace id, e.g. 1 for Meta")
    s.add_argument("--format", choices=("tsv", "json"), default="tsv")
    s.set_defaults(func=cmd_search)

    s = sub.add_parser("opensearch", help="title autocomplete")
    s.add_argument("prefix")
    s.add_argument("--limit", type=int, default=10)
    s.set_defaults(func=cmd_opensearch)

    s = sub.add_parser("exists", help="bulk existence check; stdin or args")
    s.add_argument("titles", nargs="*")
    s.set_defaults(func=cmd_exists)

    s = sub.add_parser("batch", help="bulk wikitext fetch as {title: wikitext} JSON")
    s.add_argument("titles", nargs="*", help="omit to read from stdin")
    s.add_argument("--from-category", help="fetch every member of this category instead")
    s.set_defaults(func=cmd_batch)

    s = sub.add_parser("url", help="print the canonical wiki URL for a title")
    s.add_argument("titles", nargs="+")
    s.set_defaults(func=cmd_url)

    s = sub.add_parser("edit", help="edit a page (--wiki dev only)")
    s.add_argument("title")
    s.add_argument("--text", help="new page text; reads stdin if omitted")
    s.add_argument("--file", help="read new page text from this file")
    s.add_argument("--summary", "-s", help="edit summary")
    s.add_argument("--section", help="section to edit: number, 0 for lead, or 'new'")
    s.add_argument("--sectiontitle", help="title for a new section")
    s.add_argument("--append", action="store_true", help="append text instead of replacing")
    s.add_argument("--prepend", action="store_true", help="prepend text instead of replacing")
    s.add_argument("--minor", action="store_true", help="mark as minor edit")
    s.add_argument("--bot", action="store_true", help="mark as bot edit")
    s.set_defaults(func=cmd_edit)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    global API, WIKI
    cfg = WIKIS[args.wiki]
    API = cfg["api"]
    WIKI = cfg["wiki"]
    try:
        return args.func(args)
    except requests.HTTPError as e:
        print(f"http error: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
