#!/usr/bin/env python3
"""Prepend entry to manifest.json (no duplicates). Usage: update-manifest.py <manifest> <entry>"""
import json
import sys

def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: update-manifest.py <manifest.json> <entry>")
        return 2
    path, entry = sys.argv[1], sys.argv[2]
    with open(path, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    if not isinstance(manifest, list):
        manifest = []
    if entry in manifest:
        manifest.remove(entry)
    manifest.insert(0, entry)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"[MANIFEST] first={manifest[0]} count={len(manifest)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
