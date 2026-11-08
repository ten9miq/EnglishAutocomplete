"""Package source + ready-to-run dictionary, excluding every personal artifact."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOP = ("EnglishAutocomplete.ahk", "ManageDictionary.ahk", "settings.default.ini",
       "README.md", "LICENSE", "LICENSES.md", "AGENTS.md")
EXCLUDE = {"sources", "results", "__pycache__", "dist", "user"}


def package():
    destination = ROOT / "dist/EnglishAutocomplete-portable.zip"
    destination.parent.mkdir(parents=True, exist_ok=True)
    paths = [ROOT / name for name in TOP]
    for directory in ("Lib", "data", "licenses", "tools", "tests", "docs"):
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and not EXCLUDE.intersection(path.relative_to(ROOT).parts):
                if path.name.startswith("resident-metrics") and path.suffix == ".json":
                    continue
                if path.suffix.lower() in {".ahk", ".db", ".json", ".md", ".txt", ".py", ".ps1", ".html"}:
                    paths.append(path)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(set(paths)):
            info = zipfile.ZipInfo("EnglishAutocomplete/" + path.relative_to(ROOT).as_posix(), (2026, 11, 8, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        assert archive.testzip() is None
        assert "EnglishAutocomplete/data/dictionary.db" in archive.namelist()
        assert not any("/user/" in name or "/sources/" in name or "/results/" in name for name in archive.namelist())
        assert not any("/resident-metrics" in name for name in archive.namelist())
        assert "EnglishAutocomplete/licenses/SCOWL-Copyright.txt" in archive.namelist()
        assert "EnglishAutocomplete/licenses/EJDict-CC0.txt" in archive.namelist()
        count = len(archive.namelist())
    return {"archive": str(destination), "files": count, "bytes": destination.stat().st_size,
            "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}


if __name__ == "__main__":
    print(json.dumps(package(), indent=2))
