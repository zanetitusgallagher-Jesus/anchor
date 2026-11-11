#!/usr/bin/env python3
"""Convert public-domain KJV (scrollmapper) and WEB (TehShrike) sources into
Anchor's compact bundle format:

{"id":"KJV","name":"...","books":[{"id":"GEN","name":"Genesis","chapters":[["v1","v2",...],...]}]}

Usage: build_bibles.py <KJV.json> <web_dir> <out_dir>
"""
import json, re, sys, pathlib

BOOKS = [
 ("GEN","Genesis"),("EXO","Exodus"),("LEV","Leviticus"),("NUM","Numbers"),("DEU","Deuteronomy"),
 ("JOS","Joshua"),("JDG","Judges"),("RUT","Ruth"),("1SA","1 Samuel"),("2SA","2 Samuel"),
 ("1KI","1 Kings"),("2KI","2 Kings"),("1CH","1 Chronicles"),("2CH","2 Chronicles"),("EZR","Ezra"),
 ("NEH","Nehemiah"),("EST","Esther"),("JOB","Job"),("PSA","Psalms"),("PRO","Proverbs"),
 ("ECC","Ecclesiastes"),("SNG","Song of Solomon"),("ISA","Isaiah"),("JER","Jeremiah"),
 ("LAM","Lamentations"),("EZK","Ezekiel"),("DAN","Daniel"),("HOS","Hosea"),("JOL","Joel"),
 ("AMO","Amos"),("OBA","Obadiah"),("JON","Jonah"),("MIC","Micah"),("NAM","Nahum"),
 ("HAB","Habakkuk"),("ZEP","Zephaniah"),("HAG","Haggai"),("ZEC","Zechariah"),("MAL","Malachi"),
 ("MAT","Matthew"),("MRK","Mark"),("LUK","Luke"),("JHN","John"),("ACT","Acts"),("ROM","Romans"),
 ("1CO","1 Corinthians"),("2CO","2 Corinthians"),("GAL","Galatians"),("EPH","Ephesians"),
 ("PHP","Philippians"),("COL","Colossians"),("1TH","1 Thessalonians"),("2TH","2 Thessalonians"),
 ("1TI","1 Timothy"),("2TI","2 Timothy"),("TIT","Titus"),("PHM","Philemon"),("HEB","Hebrews"),
 ("JAS","James"),("1PE","1 Peter"),("2PE","2 Peter"),("1JN","1 John"),("2JN","2 John"),
 ("3JN","3 John"),("JUD","Jude"),("REV","Revelation"),
]

def clean(s):
    return re.sub(r"\s+", " ", s).strip()

def kjv(path):
    src = json.load(open(path, encoding="utf-8"))["books"]
    assert len(src) == 66
    books = []
    for (bid, name), b in zip(BOOKS, src):
        chapters = []
        for ch in b["chapters"]:
            verses = sorted(ch["verses"], key=lambda v: v["verse"])
            chapters.append([clean(v["text"]) for v in verses])
        books.append({"id": bid, "name": name, "chapters": chapters})
    return {"id": "KJV", "name": "King James Version (1769)", "books": books}

def web(dirpath):
    books = []
    for bid, name in BOOKS:
        fn = name.lower().replace(" ", "")
        items = json.load(open(pathlib.Path(dirpath) / f"{fn}.json", encoding="utf-8"))
        verses = {}
        for it in items:
            if it.get("type") not in ("paragraph text", "line text"):
                continue
            key = (it["chapterNumber"], it["verseNumber"])
            verses[key] = verses.get(key, "") + " " + it["value"]
        nch = max(c for c, _ in verses)
        chapters = []
        for c in range(1, nch + 1):
            nv = max((v for cc, v in verses if cc == c), default=0)
            chapters.append([clean(verses.get((c, v), "")) for v in range(1, nv + 1)])
        books.append({"id": bid, "name": name, "chapters": chapters})
    return {"id": "WEB", "name": "World English Bible", "books": books}

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[3]); out.mkdir(parents=True, exist_ok=True)
    for bible in (kjv(sys.argv[1]), web(sys.argv[2])):
        total = sum(len(c) for b in bible["books"] for c in b["chapters"])
        print(bible["id"], "verses:", total)
        with open(out / f"{bible['id']}.json", "w", encoding="utf-8") as f:
            json.dump(bible, f, ensure_ascii=False, separators=(",", ":"))
