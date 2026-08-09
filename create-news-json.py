#!/usr/bin/env python3
"""Force-rebuild Document/{date}_News/{date}_news.json for GitHub Pages.

ALWAYS combines:
  1) ALL News/Articles/**/{date}/**/article.json (fetch pass)
  2) Document/{date}_Facebook/{date}_facebook_briefing.json posts

Usage:
  python create-news-json.py [YYYY-MM-DD] [--force]
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent
PARENT = REPO.parent
DOCROOT = PARENT / "Document"
ARTICLES = PARENT / "News" / "Articles"
DATA = REPO / "data"

CAT_TOPIC = {
    "ECONOMY": "เศรษฐกิจ / economy",
    "POLICY": "นโยบาย / policy",
    "DIGITAL": "ดิจิทัล / digital",
    "HEALTH": "สาธารณสุข / health",
    "INFRA": "โครงสร้างพื้นฐาน / infra",
    "TRADE": "การค้า / trade",
    "SOCIAL": "สังคม / social",
    "GENERAL": "ทั่วไป / general",
}


def today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")


def slugify(text: str) -> str:
    text = (text or "").strip().lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text).strip("-")
    return text[:80] or "post"


def priority_for(urgency: str) -> str:
    return {"high": "A", "medium": "B", "low": "C"}.get((urgency or "").lower(), "B")


def load_json(path: Path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"[WARN] bad JSON {path}: {exc}")
        return None


def post_from_briefing(p: dict, date: str, idx: int) -> dict:
    title = (p.get("title") or "").strip() or f"ข่าว {date} #{idx}"
    pid = (p.get("id") or f"fb-{date}-{idx:03d}").strip()
    urgency = (p.get("urgency") or "medium").lower()
    cat = (p.get("category") or "GENERAL").upper()
    content = (p.get("summary") or p.get("content") or "").strip()
    return {
        "id": pid,
        "slug": slugify(pid) if str(pid).startswith("fb-") else (slugify(title) or slugify(pid)),
        "title": title,
        "topic": p.get("category_label") or CAT_TOPIC.get(cat, cat),
        "agency": p.get("agency") or "Facebook / Social",
        "origin": "indirect",
        "priority": priority_for(urgency),
        "urgency": urgency,
        "content": content,
        "source_url": p.get("url") or p.get("source_url") or "",
        "bd_opportunity": p.get("bd_opportunity") or "",
        "category_label": p.get("category_label") or CAT_TOPIC.get(cat, cat),
        "published_at": p.get("date") or p.get("published_at") or date,
        "tags": p.get("tags") or [],
        "_source": "facebook_briefing",
    }


def post_from_article(art: dict, date: str) -> dict | None:
    fetch = art.get("fetch") or {}
    status = str(fetch.get("status") or "pass").lower()
    if status not in ("pass", "ok", "success", ""):
        return None
    content_obj = art.get("content") or {}
    meta = art.get("meta") or {}
    agency = art.get("agency") or {}
    source = art.get("source") or {}
    bd = art.get("bd_insights") or {}
    title = (content_obj.get("title") or art.get("title") or "").strip()
    if not title:
        return None
    slug = content_obj.get("slug") or art.get("slug") or slugify(title)
    urgency = (bd.get("urgency") or meta.get("urgency") or "medium").lower()
    parent = agency.get("parent") or ""
    name = agency.get("name") or agency.get("short_name") or "Agency"
    agency_label = f"{parent} > {name}" if parent else name
    body = (
        content_obj.get("summary_1")
        or content_obj.get("summary")
        or content_obj.get("body_text")
        or art.get("content")
        or ""
    )
    url = source.get("url") or ""
    return {
        "id": art.get("article_id") or slug,
        "slug": slug,
        "title": title,
        "topic": meta.get("category_label") or meta.get("category") or "ทั่วไป / general",
        "agency": agency_label,
        "origin": source.get("origin") or ("direct" if "go.th" in url else "indirect"),
        "priority": meta.get("priority") or priority_for(urgency),
        "urgency": urgency,
        "content": body.strip() if isinstance(body, str) else "",
        "source_url": url,
        "bd_opportunity": bd.get("opportunity") or "",
        "category_label": meta.get("category_label") or "",
        "published_at": meta.get("published_at") or date,
        "tags": meta.get("tags") or [],
        "_source": "articles",
    }


def path_is_for_date(path: Path, date: str) -> bool:
    """True if article path is under a TARGET_DATE folder segment."""
    return date in path.parts


def collect_articles(date: str) -> list[dict]:
    posts: list[dict] = []
    scanned = 0
    if not ARTICLES.is_dir():
        print(f"[INFO] Articles root missing: {ARTICLES}")
        return posts
    for path in ARTICLES.rglob("article.json"):
        if not path_is_for_date(path, date):
            continue
        scanned += 1
        art = load_json(path)
        if not isinstance(art, dict):
            continue
        post = post_from_article(art, date)
        if post:
            posts.append(post)
    print(f"[INFO] Articles scanned for {date}: {scanned} files -> {len(posts)} posts")
    return posts


def collect_briefing(date: str) -> list[dict]:
    path = DOCROOT / f"{date}_Facebook" / f"{date}_facebook_briefing.json"
    data = load_json(path)
    if not isinstance(data, dict):
        print(f"[INFO] Facebook briefing missing: {path}")
        return []
    raw = data.get("posts") or []
    posts = [post_from_briefing(p, date, i) for i, p in enumerate(raw, start=1) if isinstance(p, dict)]
    print(f"[INFO] Facebook briefing posts: {len(posts)} from {path}")
    return posts


def dedupe(posts: list[dict]) -> list[dict]:
    seen_url: set[str] = set()
    seen_title: set[str] = set()
    out: list[dict] = []
    for p in posts:
        url = (p.get("source_url") or "").strip().lower()
        title = (p.get("title") or "").strip().lower()
        if url and url in seen_url:
            continue
        if title and title in seen_title:
            continue
        if url:
            seen_url.add(url)
        if title:
            seen_title.add(title)
        out.append(p)
    return out


def build_stats(posts: list[dict]) -> dict:
    cats: dict[str, int] = {}
    sources: dict[str, int] = {}
    for p in posts:
        key = (p.get("category_label") or p.get("topic") or "GENERAL").split("/")[0].strip() or "GENERAL"
        cats[key] = cats.get(key, 0) + 1
        src = p.pop("_source", "unknown") if "_source" in p else p.get("_source", "unknown")
        # keep _source out of final payload via pop above when present on copy
        sources[str(src)] = sources.get(str(src), 0) + 1
    return {
        "total": len(posts),
        "direct": sum(1 for p in posts if p.get("origin") == "direct"),
        "indirect": sum(1 for p in posts if p.get("origin") != "direct"),
        "from_articles": sources.get("articles", 0),
        "from_facebook": sources.get("facebook_briefing", 0),
        "categories": cats,
    }


def strip_internal(posts: list[dict]) -> list[dict]:
    clean = []
    for p in posts:
        q = dict(p)
        q.pop("_source", None)
        clean.append(q)
    return clean


def create_for_date(date: str, force: bool = True) -> Path:
    news_dir = DOCROOT / f"{date}_News"
    out_doc = news_dir / f"{date}_news.json"
    out_data = DATA / f"{date}_news.json"

    print(f"[START] rebuild {date}_news.json force={force}")
    article_posts = collect_articles(date)
    briefing_posts = collect_briefing(date)

    # Articles first (official/pipeline), then Facebook fill gaps
    combined = dedupe(article_posts + briefing_posts)
    print(f"[INFO] combined unique posts: {len(combined)} (articles={len(article_posts)} fb={len(briefing_posts)})")

    if not combined:
        raise SystemExit(
            f"ERROR: nothing to combine for {date}. "
            f"Need News/Articles/**/{date}/**/article.json and/or "
            f"Document/{date}_Facebook/{date}_facebook_briefing.json"
        )

    # stats needs _source before strip
    stats_posts = [dict(p) for p in combined]
    sources = {"articles": 0, "facebook_briefing": 0}
    for p in stats_posts:
        sources[p.get("_source", "unknown")] = sources.get(p.get("_source", "unknown"), 0) + 1

    final_posts = strip_internal(combined)
    payload = {
        "date": date,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "pipeline": "create-news-json-combine",
        "sources": {
            "articles_count": len(article_posts),
            "facebook_count": len(briefing_posts),
            "combined_unique": len(final_posts),
        },
        "posts": final_posts,
        "stats": {
            "total": len(final_posts),
            "direct": sum(1 for p in final_posts if p.get("origin") == "direct"),
            "indirect": sum(1 for p in final_posts if p.get("origin") != "direct"),
            "from_articles": sources.get("articles", 0),
            "from_facebook": sources.get("facebook_briefing", 0),
            "categories": {},
        },
    }
    cats: dict[str, int] = {}
    for p in final_posts:
        key = (p.get("category_label") or p.get("topic") or "GENERAL").split("/")[0].strip() or "GENERAL"
        cats[key] = cats.get(key, 0) + 1
    payload["stats"]["categories"] = cats

    news_dir.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    out_doc.write_text(text, encoding="utf-8")
    DATA.mkdir(parents=True, exist_ok=True)
    out_data.write_text(text, encoding="utf-8")

    print(f"[OK] wrote {out_doc} ({len(final_posts)} posts, {out_doc.stat().st_size} bytes)")
    print(f"[OK] wrote {out_data}")
    return out_doc


def main() -> int:
    args = [a for a in sys.argv[1:] if a]
    force = True  # always rebuild — schedule expects recreate
    date = today_str()
    for a in args:
        if a in ("--force", "-f"):
            force = True
        elif re.fullmatch(r"\d{4}-\d{2}-\d{2}", a):
            date = a
        elif a in ("--help", "-h"):
            print(__doc__)
            return 0
        else:
            print(f"Unknown arg: {a}")
            print("Usage: create-news-json.py [YYYY-MM-DD] [--force]")
            return 2
    create_for_date(date, force=force)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
