#!/usr/bin/env python3
"""Attu Project wiki CLI.

Run with the project venv: ./.venv/bin/python scripts/wiki.py <subcommand> ...

Subcommands wrap the operations that recur across sessions so each one no longer
needs the requests/mwparserfromhell boilerplate inlined.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Iterable, Iterator

import requests
import mwparserfromhell as mwp

API = "https://attuproject.org/api.php"
WIKI = "https://attuproject.org/wiki/"
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


# ---------- entrypoint ----------


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wiki",
        description="Attu Project wiki CLI (MediaWiki Action API wrapper).",
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

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except requests.HTTPError as e:
        print(f"http error: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
