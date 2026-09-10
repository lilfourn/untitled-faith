#!/usr/bin/env python3
"""Build the bundled Bible database from a tab-separated verse file.

Input lines look like "John 3:16<TAB>For God so loved..."; other lines are ignored.
The output is a read-only SQLite file with an FTS5 index for exact and keyword search.

    scripts/bible/build.py --source https://bereanbible.com/bsb.txt --id BSB \
        --name "Berean Standard Bible" --license "Public domain" \
        --notice "The Holy Bible, Berean Standard Bible, BSB is produced in cooperation with Bible Hub, Discovery Bible, unfoldingWord, Bible Aquifer, OpenBible.com, and the Berean Bible Translation Committee. This text of God's Word has been dedicated to the public domain."

A licensed translation (for example the ESV from Crossway) is built the same way once its
text has been exported to this format. Never commit licensed text without the license.
"""
import argparse
import datetime
import os
import re
import sqlite3
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUTPUT = os.path.join(ROOT, "Untitled Faith", "Resources", "Bible.sqlite")

# Canonical Protestant order. Names must match the source file's book names or aliases below.
BOOKS = [
    "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
    "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra",
    "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon",
    "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos",
    "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah",
    "Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians",
    "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians",
    "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James",
    "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation",
]
ALIASES = {"Psalm": "Psalms", "Song of Songs": "Song of Solomon", "Canticles": "Song of Solomon"}
LINE = re.compile(r"^((?:[1-3] )?[A-Za-z ]+?) (\d+):(\d+)\t(.*)$")


def read_source(source):
    if re.match(r"^https?://", source):
        with urllib.request.urlopen(source, timeout=120) as response:
            return response.read().decode("utf-8-sig")
    with open(source, encoding="utf-8-sig") as handle:
        return handle.read()


def parse(text):
    ids = {name: index + 1 for index, name in enumerate(BOOKS)}
    verses, skipped = [], []
    for line in text.splitlines():
        match = LINE.match(line.rstrip("\r"))
        if not match:
            skipped.append(line)
            continue
        book, chapter, verse, body = match.groups()
        book = ALIASES.get(book, book)
        if book not in ids:
            raise SystemExit(f"Unknown book in source: {book!r}")
        body = body.strip()
        if not body:
            continue  # verses absent from the translation's base text
        verses.append((ids[book], int(chapter), int(verse), body))
    return verses, skipped


def build(output, verses, meta):
    if os.path.exists(output):
        os.remove(output)
    os.makedirs(os.path.dirname(output), exist_ok=True)
    db = sqlite3.connect(output)
    db.executescript(
        """
        PRAGMA journal_mode = DELETE;
        CREATE TABLE translation (id TEXT NOT NULL, name TEXT NOT NULL, license TEXT NOT NULL,
            notice TEXT NOT NULL, source TEXT NOT NULL, built TEXT NOT NULL);
        CREATE TABLE books (id INTEGER PRIMARY KEY, name TEXT NOT NULL, chapters INTEGER NOT NULL);
        CREATE TABLE verses (id INTEGER PRIMARY KEY, book INTEGER NOT NULL, chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL, text TEXT NOT NULL);
        CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='verses', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2');
        """
    )
    db.execute("INSERT INTO translation VALUES (?, ?, ?, ?, ?, ?)", meta)
    chapters = {}
    for book, chapter, _, _ in verses:
        chapters[book] = max(chapters.get(book, 0), chapter)
    db.executemany("INSERT INTO books VALUES (?, ?, ?)",
                   [(index + 1, name, chapters.get(index + 1, 0)) for index, name in enumerate(BOOKS)])
    db.executemany("INSERT INTO verses VALUES (?, ?, ?, ?, ?)",
                   [(book * 1_000_000 + chapter * 1_000 + verse, book, chapter, verse, text)
                    for book, chapter, verse, text in verses])
    db.execute("INSERT INTO verses_fts(rowid, text) SELECT id, text FROM verses")
    db.execute("INSERT INTO verses_fts(verses_fts) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, help="URL or path of the tab-separated verse file")
    parser.add_argument("--id", required=True, help="Translation abbreviation shown in citations, e.g. BSB")
    parser.add_argument("--name", required=True)
    parser.add_argument("--license", required=True)
    parser.add_argument("--notice", required=True, help="Attribution or copyright notice shown in Settings")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    verses, skipped = parse(read_source(args.source))
    if len(verses) < 30_000:
        raise SystemExit(f"Only {len(verses)} verses parsed; expected a complete Bible.")
    built = datetime.date.today().isoformat()
    build(args.output, verses, (args.id, args.name, args.license, args.notice, args.source, built))
    print(f"{args.output}: {len(verses)} verses, {len(set(v[0] for v in verses))} books, "
          f"{os.path.getsize(args.output) / 1_048_576:.1f} MB; skipped {len(skipped)} non-verse lines", file=sys.stderr)


if __name__ == "__main__":
    main()
