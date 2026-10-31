#!/usr/bin/env python3
"""Report old identifiers in tracked source paths, including Lua annotations."""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY = re.compile(r"orbitvim|orbit[_-]vim|nvchad|base46", re.IGNORECASE)
SOURCE_ROOTS = ("lua/", "tests/", "after/", "syntax/", ".github/")
SOURCE_FILES = {"init.lua", "settings.schema.json"}


def main():
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True
    )
    paths = (Path(raw.decode()) for raw in result.stdout.split(b"\0") if raw)
    matches = []
    for path in paths:
        name = path.as_posix()
        if not (name.startswith(SOURCE_ROOTS) or name in SOURCE_FILES):
            continue
        if path.suffix not in {".lua", ".json", ".scm", ".vim", ".yml", ".yaml", ".toml"}:
            continue
        if LEGACY.search(name):
            matches.append(f"legacy path: {name}")
        for line_number, line in enumerate((ROOT / path).read_text(encoding="utf-8").splitlines(), 1):
            if LEGACY.search(line):
                matches.append(f"{name}:{line_number}: {line.strip()}")

    print("\n".join(matches) if matches else "No legacy source identifiers found.")
    return int(bool(matches))


if __name__ == "__main__":
    sys.exit(main())
