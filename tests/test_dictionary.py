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
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], 2)

    def test_cspell_input_filter(self):
        self.assertEqual(list(builder.cspell_words("# comment\nKubernetes # tool\nC++\nC#\ntwo words\n!banned\n*fragment\nfoo/bar\npnpm\nA\n")),
                         ["Kubernetes", "pnpm"])

    def test_it_provenance_and_spelling(self):
        for word in ("kubernetes", "terraform", "kubectl", "pnpm", "ripgrep", "typescript"):
            row = self.db.execute("SELECT source FROM words WHERE norm=?", (word,)).fetchone()
            self.assertIsNotNone(row, word)
            self.assertTrue(row[0] & 4, word)
        for word in ("OpenAI", "ChatGPT", "Codex", "Ollama", "LangChain", "LangGraph", "vLLM"):
            row = self.db.execute("SELECT it.word FROM it_entries it JOIN words w ON w.id=it.word_id WHERE w.norm=? AND it.source=8", (word.lower(),)).fetchone()
            self.assertEqual(row, (word,))
        self.assertGreater(self.db.execute("SELECT count(*) FROM it_entries WHERE source=4").fetchone()[0], 3000)
        self.assertEqual(self.db.execute("SELECT count(*) FROM it_entries WHERE source=8").fetchone()[0], 16)
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])
        # IT/AI use separate spellings; disabling them can restore normal English.
        self.assertEqual(self.db.execute("SELECT word FROM words WHERE norm='codex'").fetchone()[0], "codex")

    def test_it_indexes_and_ai_manifest(self):
        self.assertIn("kubernetes", [r[0] for r in search(self.db, "kuber", 4)])
        self.assertIn("chatgpt", [r[0] for r in search(self.db, "chatg", 8)])
        self.assertNotIn("kubernetes", [r[0] for r in search(self.db, "kuber", 1)])
        manifest = json.loads((ROOT / "data/dictionary.manifest.json").read_text("utf-8"))
        self.assertEqual(manifest["ai_supplement_sha256"], hashlib.sha256((ROOT / "data/ai-supplement.json").read_bytes()).hexdigest())
        paths = builder.archives()
        lock = json.loads((ROOT / "tools/sources.lock.json").read_text("utf-8"))
        self.assertEqual(lock["cspell"]["commit"], builder.SOURCES["cspell"][1])
        for name, path in paths["cspell"].items():
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), lock["cspell"]["files"][name])

    def test_base_vocabulary_unchanged_by_it(self):
        rows = self.db.execute("SELECT norm,word,score,translation,(source & 3) FROM words WHERE (source & 3)!=0 ORDER BY norm").fetchall()
        self.assertEqual(len(rows), 113438)
        digest = hashlib.sha256(json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode('utf-8')).hexdigest()
        self.assertEqual(digest, "f392a564dc101b4e029aa7b7e27c25e8525ed05a85f4213aa737b13806ac5bf1")

    def test_original_it_descriptions_and_provenance(self):
        path = ROOT / "data/it-descriptions.jsonl"
        document = path.read_text("utf-8")
        available = {row[0] for row in self.db.execute("SELECT w.norm FROM words w JOIN it_entries it ON it.word_id=w.id WHERE it.source=4")}
        records = builder.description_records(document, available)
        self.assertGreaterEqual(len(records), 128)
        self.assertEqual(self.db.execute("SELECT count(*) FROM it_description_provenance").fetchone()[0], len(records))
        for norm, entry in records.items():
            with self.subTest(word=norm):
                self.assertRegex(entry["description"], r"[\u3040-\u30ff\u4e00-\u9fff]")
                row = self.db.execute("SELECT it.translation,p.reference_url,p.license,p.verified_on,p.origin,p.review_status "
                    "FROM it_entries it JOIN words w ON w.id=it.word_id "
                    "JOIN it_description_provenance p ON p.word_id=w.id WHERE it.source=4 AND w.norm=?", (norm,)).fetchone()
                self.assertEqual(row, tuple(entry[k] for k in ("description", "reference_url", "license", "verified_on", "origin", "review_status")))
        manifest = json.loads((ROOT / "data/dictionary.manifest.json").read_text("utf-8"))
        self.assertEqual(manifest["it_descriptions_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertEqual(manifest["it_descriptions_file"], path.name)
        self.assertEqual(manifest["it_description_count"], str(len(records)))
        self.assertEqual(manifest["it_description_license"], "MIT")

    def test_description_validation_and_review_gate(self):
        entry = {"word": "Kubernetes", "description": "コンテナの管理基盤",
            "reference_url": "https://kubernetes.io/", "license": "MIT", "verified_on": "2026-11-10",
            "origin": "original", "review_status": "reviewed"}
        available = {"kubernetes"}
        line = json.dumps(entry, ensure_ascii=False)
        self.assertIn("kubernetes", builder.description_records(line + "\n", available))
        self.assertIn("kubernetes", builder.description_records(line + "\r\n", available))
        draft = dict(entry, review_status="draft")
        self.assertEqual(builder.description_records(json.dumps(draft), available), {})
        for key, value in [("word", "UnknownFixture"), ("word", "Kubernetes "), ("word", 42),
                           ("description", ""), ("description", "a" * 101), ("description", "bad\nline"),
                           ("reference_url", "http://example.com"), ("reference_url", "https://"),
                           ("reference_url", "https://user:password@example.com"), ("reference_url", "https://example.com/a b"),
                           ("license", "CC-BY-4.0"), ("origin", "translation"),
                           ("verified_on", "2026-02-30"), ("verified_on", "20261110"), ("review_status", "unverified")]:
            invalid = dict(entry, **{key: value})
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, "line 1:"):
                builder.description_records(json.dumps(invalid), available)
        duplicate = line + "\n" + json.dumps(dict(entry, word="KUBERNETES", review_status="draft"))
        with self.assertRaisesRegex(ValueError, "line 2:"):
            builder.description_records(duplicate, available)
        for invalid in (None, [], "", "\n", "[]", "null", "{}", "{bad}",
                        line + "\n\n", line + "\n \n", line + "\n{bad}",
                        line.replace('"word":', '"word": "Kubernetes", "word":', 1),
                        json.dumps(dict(entry, unexpected="field"))):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                builder.description_records(invalid, available)
        for key in entry:
            invalid = dict(entry)
            del invalid[key]
            with self.subTest(missing=key), self.assertRaisesRegex(ValueError, "line 1:"):
                builder.description_records(json.dumps(invalid), available)
        for invalid in ("{bad}", json.dumps(dict(entry, license="CC0")), " "):
            with self.subTest(second_line=invalid), self.assertRaisesRegex(ValueError, "line 2:"):
                builder.description_records(line + "\n" + invalid, available)

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

    def test_possessive_noise_and_contractions(self):
        self.assertIsNotNone(self.db.execute("SELECT norm FROM words WHERE norm=?", ("teacher's",)).fetchone())
        self.assertNotIn("teacher's", [r[0] for r in search(self.db, "teacher")])
        self.assertIn("teacher's", [r[0] for r in search(self.db, "teacher'")])
        entries = {"it": ["it", 1, 10, "", 0], "it's": ["it's", 1, 10, "", 0],
                   "teacher": ["teacher", 1, 10, "", 0], "teacher's": ["teacher's", 1, 10, "", 0]}
        self.assertFalse(builder.redundant_possessive("it's", entries))
        self.assertTrue(builder.redundant_possessive("teacher's", entries))
        self.assertIn("it's", [r[0] for r in search(self.db, "it'")])

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
