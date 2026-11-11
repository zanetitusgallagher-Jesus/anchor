#!/usr/bin/env python3
"""Build the 'Verse a Day' seed plan from tools/verse_a_day.txt, checking every
reference against the bundled KJV. Usage: build_verse_a_day.py <KJV.json> <list> <out.json>"""
import json, sys
bible = {b["id"]: b for b in json.load(open(sys.argv[1], encoding="utf-8"))["books"]}
days, seen = [], set()
for line in open(sys.argv[2]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    book, cv = line.split()
    ch, vv = cv.split(":")
    a, _, b = vv.partition("-")
    ch, a, b = int(ch), int(a), int(b or a)
    verses = bible[book]["chapters"][ch - 1]
    assert 1 <= a <= b <= len(verses) and all(verses[a - 1:b]), line
    assert line not in seen, "duplicate " + line
    seen.add(line)
    days.append([{"bookID": book, "chapter": ch, "verseStart": a, "verseEnd": b}])
plan = {"id": "verse-a-day", "name": "Verse a Day",
        "summary": f"One well-known verse or short passage each day for {len(days)} days. About a minute of reading.",
        "days": days}
json.dump(plan, open(sys.argv[3], "w"), separators=(",", ":"))
print(len(days), "days")
