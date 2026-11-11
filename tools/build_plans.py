#!/usr/bin/env python3
"""Generate Anchor's seed reading plans from the bundled KJV (verse counts
are used as weights so each day's reading is about the same length).
Mirrors ReadingPlanGenerator.split in AnchorCore.

Usage: build_plans.py <Bibles/KJV.json> <out_dir>
"""
import json, sys, pathlib

def split(chapters, weights, days):
    days = min(days, len(chapters))
    total = sum(weights)
    out, i, cum = [], 0, 0.0
    for d in range(days):
        remaining = days - d - 1
        target = total * (d + 1) / days
        today = []
        while True:
            today.append(chapters[i]); cum += weights[i]; i += 1
            if not (i < len(chapters) and len(chapters) - i > remaining
                    and (d == days - 1 or cum + weights[i] / 2 <= target)):
                break
        out.append(today)
    if i < len(chapters): out[-1].extend(chapters[i:])
    return out

def main():
    bible = json.load(open(sys.argv[1], encoding="utf-8"))
    books = bible["books"]
    ids = [b["id"] for b in books]
    def chaps(book_ids):
        res = []
        for b in books:
            if b["id"] in book_ids:
                for c, verses in enumerate(b["chapters"], 1):
                    res.append(({"bookID": b["id"], "chapter": c}, len(verses)))
        res.sort(key=lambda x: (book_ids.index(x[0]["bookID"]), x[0]["chapter"]))
        return [r[0] for r in res], [r[1] for r in res]

    plans = []
    c, w = chaps(ids)
    plans.append(dict(id="bible-in-a-year", name="Bible in a Year",
                      summary="Genesis to Revelation in 365 days, about 85 verses a day.",
                      days=split(c, w, 365)))
    c, w = chaps(ids[39:])
    plans.append(dict(id="nt-90", name="New Testament in 90 Days",
                      summary="Matthew to Revelation in 90 days, about 88 verses a day.",
                      days=split(c, w, 90)))
    # Psalms & Proverbs: one Proverb for each day of the month + a share of the Psalms.
    pc, pw = chaps(["PSA"])
    psalms = split(pc, pw, 31)
    prov, _ = chaps(["PRO"])
    plans.append(dict(id="psalms-proverbs", name="Psalms & Proverbs",
                      summary="A month of wisdom and worship: a chapter of Proverbs and about five Psalms a day.",
                      days=[psalms[d] + [prov[d]] for d in range(31)]))
    c, w = chaps(["MAT", "MRK", "LUK", "JHN"])
    plans.append(dict(id="gospels-45", name="The Gospels",
                      summary="Matthew, Mark, Luke and John in 45 days.",
                      days=split(c, w, 45)))

    out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
    for p in plans:
        flat = [x for d in p["days"] for x in d]
        print(p["id"], len(p["days"]), "days,", len(flat), "chapters")
        json.dump(p, open(out / f"{p['id']}.json", "w"), separators=(",", ":"))

main()
