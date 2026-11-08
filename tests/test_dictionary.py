"""Tests the compiler and the actual distributable, not a miniature word list."""
import hashlib
import importlib.util
import json
import sqlite3
import statistics
import tempfile
import time
import unittest
from contextlib import closing
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("builder", ROOT / "tools/build_dictionary.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def search(con, prefix, source=1):
    row = con.execute("SELECT ids FROM prefix_top WHERE prefix=? AND source=?", (prefix.lower(), source)).fetchone()
    if not row:
        return []
    ids = [int(x) for x in row[0].split(",")]
    return con.execute("SELECT norm,word,score FROM words WHERE id IN ({}) ORDER BY score DESC,norm".format(
        ",".join("?" for x in ids)), ids).fetchall()


class DictionaryTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(str(ROOT / "data/dictionary.db"))
        self.addCleanup(self.db.close)

    def test_headings(self):
        self.assertEqual(builder.heads("Alpha, ALPHA,beta\t意味\n"),
                         [("Alpha", "意味"), ("ALPHA", "意味"), ("beta", "意味")])
        self.assertEqual(builder.heads("bad line"), [])

    def test_normalization_and_validation(self):
        for original, norm in (("OpenAI", "openai"), ("getUserInfo", "getuserinfo"),
                               ("php-fpm", "php-fpm"), ("config.toml", "config.toml"),
                               ("snake_case2", "snake_case2"), ("can't", "can't")):
            self.assertEqual(builder.normalize(original), norm)
        for word in ("https://example.com", "x@y.com", "two words", "a\x00b", "a" * 65, "-word"):
            self.assertIsNone(builder.normalize(word))

    def test_full_dictionary_deduplicated(self):
        count, distinct = self.db.execute("SELECT count(*),count(distinct norm) FROM words").fetchone()
        self.assertGreater(count, 100000)
        self.assertEqual(count, distinct)
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 1)

    def test_sources_translation_and_inflections(self):
        for word in ("computer", "computers", "confirmed", "configuration"):
            source, = self.db.execute("SELECT source FROM words WHERE norm=?", (word,)).fetchone()
            self.assertTrue(source & 1, word)
        self.assertTrue(self.db.execute("SELECT translation FROM words WHERE norm='computer'").fetchone()[0])
        self.assertGreater(self.db.execute("SELECT count(*) FROM words WHERE source=2").fetchone()[0], 1000)
        self.assertGreater(self.db.execute("SELECT count(*) FROM phrases").fetchone()[0], 10000)
        self.assertEqual(self.db.execute("SELECT count(*) FROM words WHERE norm LIKE '% %'").fetchone()[0], 0)

    def test_prefix_case_unknown_edges(self):
        self.assertEqual(search(self.db, "CONFI"), search(self.db, "confi"))
        self.assertGreater(len(search(self.db, "confi")), 4)
        for prefix in ("confi", "compu", "zz", "absolutel"):
            for norm, word, score in search(self.db, prefix):
                self.assertTrue(norm.startswith(prefix))
                self.assertNotEqual(norm, prefix)
        self.assertEqual(search(self.db, "configurationx"), [])
        self.assertEqual(search(self.db, "zzzzzzzzzzzz"), [])
        self.assertEqual(search(self.db, ""), [])

    def test_ranking_and_frequency_missing(self):
        for prefix in ("con", "the", "compu"):
            rows = search(self.db, prefix)
            self.assertEqual(rows, sorted(rows, key=lambda r: (-r[2], r[0])))
        self.assertGreater(self.db.execute("SELECT score FROM words WHERE norm='the'").fetchone()[0], 5000)
        self.assertTrue(self.db.execute("SELECT count(*) FROM words WHERE score<1000").fetchone()[0])

    def test_index_bounded_and_query_plan(self):
        plan = " ".join(str(row) for row in self.db.execute(
            "EXPLAIN QUERY PLAN SELECT ids FROM prefix_top WHERE prefix='con' AND source=1"))
        self.assertIn("SEARCH", plan)
        # Every precomputed shortlist has the documented fixed bound.
        for ids, in self.db.execute("SELECT ids FROM prefix_top"):
            self.assertLessEqual(len(ids.split(",")), builder.TOP)
            self.assertTrue(all(x.isdecimal() for x in ids.split(",")))

    def test_build_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "dictionary.db"
            manifest = builder.compile_dictionary(builder.archives(), output)
            expected = json.loads((ROOT / "data/dictionary.manifest.json").read_text("utf-8"))
            self.assertEqual(manifest["sha256"], expected["sha256"])
            self.assertEqual(output.read_bytes(), (ROOT / "data/dictionary.db").read_bytes())

    def test_real_dictionary_performance(self):
        prefixes = [r[0] for r in self.db.execute(
            "SELECT prefix FROM prefix_top WHERE source=1 AND length(prefix)=3 ORDER BY prefix LIMIT 1000")]
        elapsed = []
        for prefix in prefixes * 3:
            start = time.perf_counter_ns()
            search(self.db, prefix)
            elapsed.append((time.perf_counter_ns() - start) / 1e6)
        elapsed.sort()
        p95 = elapsed[int(len(elapsed) * .95)]
        result = {"samples": len(elapsed), "p95_ms": p95,
                  "median_ms": statistics.median(elapsed), "engine": "Python sqlite3 static lookup only"}
        destination = ROOT / "tests/results/dictionary-benchmark.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        self.assertLess(p95, 10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
