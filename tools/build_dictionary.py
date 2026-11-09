"""Reproducible SCOWLv2 + EJDict compiler. Python 3.8+, standard library only.

Runtime consumes SQLite, not Python or upstream source files. No upstream code
is executed. Prefix top lists bound runtime work independently of vocabulary size.
"""
import argparse
from contextlib import closing
import hashlib
import json
import re
import sqlite3
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "scowl": ("engramtech/scowl", "3373b9f12dce7016c9df2713ef733131e9022bc1"),
    "ejdict": ("kujirahand/EJDict", "2dd9e71ffcefce89b4d946ce07bf51fa0573aac0"),
}
TOP = 12
WORD = re.compile(r"[A-Za-z][A-Za-z0-9_]*(?:['.-][A-Za-z0-9_]+)*\Z")
PHRASE = re.compile(r"[A-Za-z][A-Za-z0-9_' .-]{2,95}\Z")
# These can be contractions even when SCOWL has no translation for them.
CONTRACTIONS_S = frozenset(("it's", "he's", "she's", "that's", "what's", "there's",
                            "here's", "how's", "where's", "when's", "why's", "who's", "let's"))


def redundant_possessive(norm, entries):
    return (norm.endswith("'s") and norm not in CONTRACTIONS_S
            and norm[:-2] in entries and not entries[norm][3])


def normalize(word):
    word = word.strip().replace("’", "'")
    return word.lower() if len(word) <= 64 and WORD.fullmatch(word) else None


def heads(line):
    """EJDict alternative headings, including whitespace after comma."""
    if "\t" not in line:
        return []
    head, translation = line.rstrip("\r\n").split("\t", 1)
    translation = " ".join(translation.split())[:240]
    return [(w.strip(), translation) for w in head.split(",") if w.strip()]


def archives(fetch=False):
    cache = ROOT / "tools" / "sources"
    cache.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / "tools" / "sources.lock.json").read_text("utf-8"))
    result = {}
    for name, (repo, commit) in SOURCES.items():
        path = cache / (name + ".zip")
        if fetch and not path.exists():
            url = "https://codeload.github.com/{}/zip/{}".format(repo, commit)
            request = urllib.request.Request(url, headers={"User-Agent": "EnglishAutocomplete-builder"})
            with urllib.request.urlopen(request, timeout=90) as response:
                path.write_bytes(response.read())
        if not path.exists():
            raise FileNotFoundError("Run with --fetch: " + str(path))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != lock[name]["sha256"]:
            raise ValueError("Source checksum mismatch: " + name)
        result[name] = path
    return result


def compile_dictionary(paths, output, size=60):
    entries, phrases = {}, {}

    def add(word, source, level=99, translation="", frequency=0):
        norm = normalize(word)
        if not norm:
            if " " in word and PHRASE.fullmatch(word):
                phrases.setdefault(word.lower(), (word, translation, source))
            return
        if norm not in entries:
            entries[norm] = [word, source, level, translation, frequency]
        else:
            e = entries[norm]
            # Prefer SCOWL display spelling; keep case-sensitive proper names.
            if source == 1 and (not e[1] & 1 or word == norm):
                e[0] = word
            e[1] |= source
            e[2] = min(e[2], level)
            if translation and not e[3]:
                e[3] = translation
            e[4] = max(e[4], frequency)

    with zipfile.ZipFile(paths["scowl"]) as archive:
        base = archive.namelist()[0]
        (ROOT / "licenses" / "SCOWL-Copyright.txt").write_bytes(archive.read(base + "Copyright"))
        # Work on an explicitly named temporary DB; no extraction of paths/code.
        with tempfile.TemporaryDirectory() as directory:
            scowl_db = Path(directory) / "scowl.db"
            scowl_db.write_bytes(archive.read(base + "scowl.db"))
            with closing(sqlite3.connect(str(scowl_db))) as con:
                # Equivalent US/default spelling filter documented by SCOWLv2.
                rows = con.execute("""SELECT word, min(level) FROM scowl_v0
                    WHERE level<=? AND spelling IN ('_', 'A')
                    AND region IN ('', 'US') AND variant_level<=1
                    AND pos_category='' AND usage_note NOT IN
                    ('vulgar-1','vulgar-2','offensive-1','offensive-2')
                    GROUP BY word ORDER BY word COLLATE BINARY""", (size,))
                for word, level in rows:
                    add(word, 1, level)

    with zipfile.ZipFile(paths["ejdict"]) as archive:
        base = archive.namelist()[0]
        (ROOT / "licenses" / "EJDict-CC0.txt").write_bytes(archive.read(base + "LICENSE"))
        for name in sorted(archive.namelist()):
            if re.search(r"/src/[a-z]\.txt$", name):
                for line in archive.read(name).decode("utf-8-sig").splitlines():
                    for word, translation in heads(line):
                        add(word, 2, translation=translation)
        for tier, score in (("2000", 1500), ("850", 3000), ("100", 5000)):
            for line in archive.read(base + "frequency/" + tier + ".txt").decode("utf-8-sig").splitlines():
                norm = normalize(line)
                if norm in entries:
                    entries[norm][4] = max(entries[norm][4], score)

    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".tmp")
    if temporary.exists():
        temporary.unlink()
    con = sqlite3.connect(str(temporary))
    try:
        con.executescript("""
            PRAGMA page_size=4096;
            PRAGMA journal_mode=OFF;
            CREATE TABLE words(id INTEGER PRIMARY KEY, norm TEXT UNIQUE NOT NULL,
                word TEXT NOT NULL, source INTEGER NOT NULL, level INTEGER,
                score INTEGER NOT NULL, translation TEXT NOT NULL);
            CREATE TABLE prefix_top(prefix TEXT NOT NULL, source INTEGER NOT NULL,
                ids TEXT NOT NULL, PRIMARY KEY(prefix,source)) WITHOUT ROWID;
            CREATE TABLE phrases(norm TEXT PRIMARY KEY, phrase TEXT, translation TEXT,
                source INTEGER) WITHOUT ROWID;
            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT) WITHOUT ROWID;
            PRAGMA user_version=1;
        """)
        ranked = []
        for ident, (norm, e) in enumerate(sorted(entries.items()), 1):
            word, source, level, translation, frequency = e
            score = (100 - level) * 10 + frequency
            con.execute("INSERT INTO words VALUES (?,?,?,?,?,?,?)",
                        (ident, norm, word, source, level, score, translation))
            ranked.append((ident, norm, source, score))
        # Sorted by descending score, stable alphabetical tie: first TOP wins.
        prefixes = {}
        for ident, norm, source, score in sorted(ranked, key=lambda r: (-r[3], r[1])):
            for length in range(2, len(norm)):
                # Preserve dictionary data and explicit apostrophe completion,
                # but keep generated possessives out of ordinary shortlists.
                if redundant_possessive(norm, entries) and length <= len(norm) - 2:
                    continue
                for kind in (1, 2):
                    if source & kind:
                        ids = prefixes.setdefault((norm[:length], kind), [])
                        if len(ids) < TOP:
                            ids.append(str(ident))
        con.executemany("INSERT INTO prefix_top VALUES (?,?,?)",
                        ((p, s, ",".join(ids)) for (p, s), ids in sorted(prefixes.items())))
        con.executemany("INSERT INTO phrases VALUES (?,?,?,?)",
                        ((norm,) + e for norm, e in sorted(phrases.items())))
        metadata = {"schema": "1", "size": str(size), "dialect": "American",
                    "prefix_top": str(TOP), "word_count": str(len(entries)),
                    "phrase_count": str(len(phrases)), "prefix_rows": str(len(prefixes)),
                    "sources": json.dumps(SOURCES, sort_keys=True),
                    "frequency": "EJDict CC0 100/850/2000 tiers; SCOWL level"}
        metadata["possessives"] = "untranslated base+'s excluded until apostrophe; contractions retained"
        con.executemany("INSERT INTO metadata VALUES (?,?)", sorted(metadata.items()))
        con.commit()
        con.execute("VACUUM")
        assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    finally:
        con.close()
    temporary.replace(output)
    manifest = dict(metadata, bytes=output.stat().st_size,
                    sha256=hashlib.sha256(output.read_bytes()).hexdigest())
    output.with_suffix(".manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="download pinned, checksum-verified sources")
    parser.add_argument("--size", type=int, choices=(60, 70), default=60)
    parser.add_argument("--output", type=Path, default=ROOT / "data" / "dictionary.db")
    args = parser.parse_args()
    print(json.dumps(compile_dictionary(archives(args.fetch), args.output, args.size), indent=2))
