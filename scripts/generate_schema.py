#!/usr/bin/env python3
"""Build the public JSON schema from per-module source schemas."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "lua" / "orbit" / "modules"
OUTPUT = ROOT / "settings.schema.json"


def build():
    manifest = json.loads((MODULES / "manifest.json").read_text(encoding="utf-8"))
    names = manifest["order"]
    if not names or len(names) != len(set(names)):
        raise ValueError("module order must contain unique module names")

    properties = {}
    for name in names:
        if not isinstance(name, str) or not name.isidentifier():
            raise ValueError(f"invalid module name: {name!r}")
        module = json.loads((MODULES / name / "schema.json").read_text(encoding="utf-8"))
        if module.get("type") != "object" or module.get("additionalProperties") is not False:
            raise ValueError(f"module {name} must declare a closed object schema")
        if "enabled" not in module.get("properties", {}):
            raise ValueError(f"module {name} must expose the enabled option")
        properties[name] = module

    return {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "orbit.nvim settings",
        "description": "Configuration for orbit.nvim modules.",
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "$schema": {"type": "string"},
            "modules": {
                "type": "object",
                "additionalProperties": False,
                "properties": properties,
            },
        },
    }


def generate():
    return json.dumps(build(), ensure_ascii=False, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated schema differs")
    args = parser.parse_args()
    expected = generate()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != expected:
            parser.error("settings.schema.json is stale; run scripts/generate_schema.py")
    else:
        OUTPUT.write_text(expected, encoding="utf-8")


if __name__ == "__main__":
    main()
