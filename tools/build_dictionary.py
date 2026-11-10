"""Reproducible SCOWLv2 + EJDict + IT compiler. Python 3.8+, stdlib only.

Runtime consumes SQLite, not Python or upstream source files. No upstream code
is executed. Prefix top lists bound runtime work independently of vocabulary size.
"""
import argparse
from contextlib import closing
from datetime import date
import hashlib
import json
import re
import sqlite3
import tempfile
import urllib.request
from urllib.parse import urlsplit
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "scowl": ("engramtech/scowl", "3373b9f12dce7016c9df2713ef733131e9022bc1"),
    "ejdict": ("kujirahand/EJDict", "2dd9e71ffcefce89b4d946ce07bf51fa0573aac0"),
    "cspell": ("streetsidesoftware/cspell-dicts", "db01cf70052ad247fa7d8ea94a9d8e87af6e358a"),
}
CSPELL_FILES = ("coding-terms.txt", "software-terms.txt", "computing-acronyms.txt",
                "software-services.txt", "network-os.txt", "network-protocols.txt",
                "cybersecurity-terms.txt", "software-tools.txt")
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


def cspell_words(content):
    """Take supported full tokens, never code, comment words, or fragments."""
    for line in content.splitlines():
        word = line.partition("#")[0].strip()
        if len(word) >= 2 and normalize(word):
            yield word


def description_records(document, available):
    """Validate the original-description source of truth before touching output."""
    if (not isinstance(document, dict) or type(document.get("version")) is not int
            or document.get("version") != 1 or document.get("language") != "ja"):
        raise ValueError("Unsupported IT description format")
    if not isinstance(document.get("entries"), list):
        raise ValueError("IT descriptions must contain an entries array")
    reviewed, seen = {}, set()
    for entry in document["entries"]:
        if not isinstance(entry, dict):
            raise ValueError("Invalid IT description record")
        word = entry.get("word", "")
        norm = normalize(word) if isinstance(word, str) else None
        if not norm or len(word) < 2 or word != word.strip() or norm not in available or norm in seen:
            raise ValueError("Unknown or duplicate IT description word: " + str(word))
        seen.add(norm)
        text = entry.get("description", "")
        if (not isinstance(text, str) or not 1 <= len(text) <= 100 or text != text.strip()
                or any(ord(c) < 32 or ord(c) == 127 or c in "\u2028\u2029" for c in text)):
            raise ValueError("IT descriptions must be short, nonempty single lines: " + word)
        reference = entry.get("reference_url", "")
        if not isinstance(reference, str) or any(c.isspace() for c in reference):
            raise ValueError("Invalid IT description reference: " + word)
        parsed = urlsplit(reference)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError("IT descriptions require an HTTPS reference: " + word)
        if entry.get("license") != "MIT" or entry.get("origin") != "original":
            raise ValueError("Only original MIT descriptions are supported: " + word)
        verified = entry.get("verified_on", "")
        if not isinstance(verified, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", verified):
            raise ValueError("IT descriptions require an ISO verification date: " + word)
        date.fromisoformat(verified)
        status = entry.get("review_status")
        if status not in ("draft", "reviewed"):
            raise ValueError("Invalid IT description review status: " + word)
        if status == "reviewed":
            reviewed[norm] = entry
    return reviewed


def archives(fetch=False):
    cache = ROOT / "tools" / "sources"
    cache.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / "tools" / "sources.lock.json").read_text("utf-8"))
    result = {}
    for name in ("scowl", "ejdict"):
        repo, commit = SOURCES[name]
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
    repo, commit = SOURCES["cspell"]
    if lock["cspell"]["commit"] != commit:
        raise ValueError("CSpell commit mismatch")
    selected = {}
    for name in ("LICENSE",) + CSPELL_FILES:
        path = cache / "cspell" / name
        expected = lock["cspell"]["files"][name]
        if fetch and not path.exists():
            relative = "LICENSE" if name == "LICENSE" else "src/" + name
            url = "https://raw.githubusercontent.com/{}/{}/dictionaries/software-terms/{}".format(repo, commit, relative)
            request = urllib.request.Request(url, headers={"User-Agent": "EnglishAutocomplete-builder"})
            with urllib.request.urlopen(request, timeout=90) as response:
                content = response.read()
            if hashlib.sha256(content).hexdigest() != expected:
                raise ValueError("Source checksum mismatch: cspell/" + name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        if not path.exists():
            raise FileNotFoundError("Run with --fetch: " + str(path))
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError("Source checksum mismatch: cspell/" + name)
        selected[name] = path
    result["cspell"] = selected
    return result


def compile_dictionary(paths, output, size=60):
    entries, phrases, it_entries = {}, {}, {}

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

    def add_it(word, source, description=""):
        norm = normalize(word)
        if not norm or len(word) < 2:
            raise ValueError("Invalid IT entry: " + word)
        if norm not in entries:
            entries[norm] = [word, source, 99, "", 0]
        else:
            entries[norm][1] |= source
        # Keep independent spelling/score per IT source; no change to base English.
        it_entries[norm, source] = (word, 1000, description)

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

    (ROOT / "licenses" / "CSpell-software-terms-MIT.txt").write_bytes(paths["cspell"]["LICENSE"].read_bytes())
    for name in CSPELL_FILES:
        for word in cspell_words(paths["cspell"][name].read_text("utf-8-sig")):
            add_it(word, 4)
    description_path = ROOT / "data" / "it-descriptions.json"
    descriptions = description_records(json.loads(description_path.read_text("utf-8")),
                                       {norm for norm, source in it_entries if source == 4})
    for norm, entry in descriptions.items():
        display, score, _ = it_entries[norm, 4]
        it_entries[norm, 4] = (display, score, entry["description"])
    supplement_path = ROOT / "data" / "ai-supplement.json"
    supplement = json.loads(supplement_path.read_text("utf-8"))
    if supplement["version"] != 1:
        raise ValueError("Unsupported AI supplement format")
    seen = set()
    for entry in supplement["entries"]:
        norm = normalize(entry["word"])
        if norm in seen or not entry["url"].startswith("https://"):
            raise ValueError("Duplicate AI entry or missing provenance")
        seen.add(norm)
        add_it(entry["word"], 8, entry["description"])

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
            CREATE TABLE it_entries(word_id INTEGER NOT NULL REFERENCES words(id),
                  source INTEGER NOT NULL, word TEXT NOT NULL, score INTEGER NOT NULL,
                  translation TEXT NOT NULL, PRIMARY KEY(word_id,source)) WITHOUT ROWID;
            CREATE TABLE it_description_provenance(word_id INTEGER PRIMARY KEY REFERENCES words(id),
                  reference_url TEXT NOT NULL, license TEXT NOT NULL, verified_on TEXT NOT NULL,
                  origin TEXT NOT NULL, review_status TEXT NOT NULL);
            CREATE TABLE phrases(norm TEXT PRIMARY KEY, phrase TEXT, translation TEXT,
                source INTEGER) WITHOUT ROWID;
            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT) WITHOUT ROWID;
            PRAGMA user_version=2;
        """)
        ranked = []
        for ident, (norm, e) in enumerate(sorted(entries.items()), 1):
            word, source, level, translation, frequency = e
            score = (100 - level) * 10 + frequency
            con.execute("INSERT INTO words VALUES (?,?,?,?,?,?,?)",
                        (ident, norm, word, source, level, score, translation))
            ranked.append((ident, norm, source, score))
            for kind in (4, 8):
                if (norm, kind) in it_entries:
                    display, it_score, note = it_entries[norm, kind]
                    con.execute("INSERT INTO it_entries VALUES (?,?,?,?,?)", (ident, kind, display, it_score, note))
            if norm in descriptions:
                entry = descriptions[norm]
                con.execute("INSERT INTO it_description_provenance VALUES (?,?,?,?,?,?)", (
                    ident, entry["reference_url"], entry["license"], entry["verified_on"], entry["origin"], entry["review_status"]))
        # Sorted by descending score, stable alphabetical tie: first TOP wins.
        prefixes = {}
        for kind in (1, 2, 4, 8):
            eligible = [(ident, norm, source, it_entries[norm, kind][1] if kind >= 4 else score)
                        for ident, norm, source, score in ranked if source & kind]
            for ident, norm, source, score in sorted(eligible, key=lambda r: (-r[3], r[1])):
                for length in range(2, len(norm)):
                    # Preserve explicit apostrophe completion without shortlist noise.
                    if redundant_possessive(norm, entries) and length <= len(norm) - 2:
                        continue
                    ids = prefixes.setdefault((norm[:length], kind), [])
                    if len(ids) < TOP:
                        ids.append(str(ident))
        con.executemany("INSERT INTO prefix_top VALUES (?,?,?)",
                        ((p, s, ",".join(ids)) for (p, s), ids in sorted(prefixes.items())))
        con.executemany("INSERT INTO phrases VALUES (?,?,?,?)",
                        ((norm,) + e for norm, e in sorted(phrases.items())))
        metadata = {"schema": "2", "size": str(size), "dialect": "American",
                    "prefix_top": str(TOP), "word_count": str(len(entries)),
                    "phrase_count": str(len(phrases)), "prefix_rows": str(len(prefixes)),
                    "sources": json.dumps(SOURCES, sort_keys=True),
                    "frequency": "EJDict CC0 100/850/2000 tiers; SCOWL level; IT base=1000 + configured boost",
                    "cspell_files": json.dumps(CSPELL_FILES),
                    "cspell_word_count": str(sum(kind == 4 for norm, kind in it_entries)),
                    "ai_word_count": str(sum(kind == 8 for norm, kind in it_entries)),
                    "ai_supplement_sha256": hashlib.sha256(supplement_path.read_bytes()).hexdigest(),
                    "ai_verified_on": supplement["verified_on"],
                    "it_description_count": str(len(descriptions)),
                    "it_descriptions_sha256": hashlib.sha256(description_path.read_bytes()).hexdigest(),
                    "it_description_license": "MIT"}
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
