#!/usr/bin/env python3
"""Create Document/{date}_News/{date}_news.json for GitHub Pages.

Sources (first available wins, then merge articles if present):
  1) Document/{date}_Facebook/{date}_facebook_briefing.json
  2) News/Articles/**/{date}/**/article.json
  3) existing data/{date}_news.json (normalize)

Usage:
  python create-news-json.py [YYYY-MM-DD]
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


def load_json(path: Path) -> dict | list | None:
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
        "slug": slugify(pid) if pid.startswith("fb-") else slugify(title) or slugify(pid),
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
    }


def post_from_article(art: dict, date: str) -> dict | None:
    fetch = art.get("fetch") or {}
    if fetch.get("status") and str(fetch.get("status")).lower() not in ("pass", "ok", "success"):
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
    return {
        "id": art.get("article_id") or slug,
        "slug": slug,
        "title": title,
        "topic": meta.get("category_label") or meta.get("category") or "ทั่วไป / general",
        "agency": agency_label,
        "origin": source.get("origin") or ("direct" if "go.th" in (source.get("url") or "") else "indirect"),
        "priority": priority_for(urgency) if urgency else (meta.get("priority") or "B"),
        "urgency": urgency,
        "content": body.strip() if isinstance(body, str) else "",
        "source_url": source.get("url") or "",
        "bd_opportunity": bd.get("opportunity") or "",
        "category_label": meta.get("category_label") or "",
        "published_at": meta.get("published_at") or date,
        "tags": meta.get("tags") or [],
    }


def collect_articles(date: str) -> list[dict]:
    posts: list[dict] = []
    if not ARTICLES.is_dir():
        return posts
    for path in ARTICLES.rglob("article.json"):
        if f"\\{date}\\" not in str(path) and f"/{date}/" not in str(path):
            # also allow .../{date}/slug/article.json via parts
            if date not in path.parts:
                continue
        art = load_json(path)
        if not isinstance(art, dict):
            continue
        post = post_from_article(art, date)
        if post:
            posts.append(post)
    return posts


def collect_briefing(date: str) -> list[dict]:
    path = DOCROOT / f"{date}_Facebook" / f"{date}_facebook_briefing.json"
    data = load_json(path)
    if not isinstance(data, dict):
        return []
    raw = data.get("posts") or []
    return [post_from_briefing(p, date, i) for i, p in enumerate(raw, start=1) if isinstance(p, dict)]


def dedupe(posts: list[dict]) -> list[dict]:
    seen_url: set[str] = set()
    seen_title: set[str] = set()
    out: list[dict] = []
    for p in posts:
        url = (p.get("source_url") or "").strip()
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
    for p in posts:
        key = (p.get("category_label") or p.get("topic") or "GENERAL").split("/")[0].strip() or "GENERAL"
        cats[key] = cats.get(key, 0) + 1
    return {
        "total": len(posts),
        "direct": sum(1 for p in posts if p.get("origin") == "direct"),
        "indirect": sum(1 for p in posts if p.get("origin") != "direct"),
        "categories": cats,
    }


def create_for_date(date: str) -> Path:
    briefing_posts = collect_briefing(date)
    article_posts = collect_articles(date)
    posts = dedupe(article_posts + briefing_posts)

    if not posts:
        # last resort: normalize existing data file
        existing = load_json(DATA / f"{date}_news.json")
        if isinstance(existing, dict) and existing.get("posts"):
            raw = existing["posts"]
            # if already pages-shaped, keep; else map briefing-shaped
            if raw and "content" in raw[0]:
                posts = raw
            else:
                posts = [post_from_briefing(p, date, i) for i, p in enumerate(raw, start=1)]

    if not posts:
        raise SystemExit(
            f"ERROR: no source to build {date}_news.json "
            f"(need Document/{date}_Facebook/{date}_facebook_briefing.json "
            f"or News/Articles/**/{date}/**/article.json)"
        )

    payload = {
        "date": date,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "pipeline": "create-news-json",
        "posts": posts,
        "stats": build_stats(posts),
    }

    news_dir = DOCROOT / f"{date}_News"
    news_dir.mkdir(parents=True, exist_ok=True)
    out_doc = news_dir / f"{date}_news.json"
    out_doc.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    DATA.mkdir(parents=True, exist_ok=True)
    out_data = DATA / f"{date}_news.json"
    out_data.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"[OK] wrote {out_doc} ({len(posts)} posts)")
    print(f"[OK] wrote {out_data}")
    return out_doc


def main() -> int:
    date = sys.argv[1] if len(sys.argv) > 1 else today_str()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        print("Usage: create-news-json.py [YYYY-MM-DD]")
        return 2
    create_for_date(date)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
