"""Behavioral checks for the schema generator and its module contract."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("orbit_schema_generator", ROOT / "scripts" / "generate_schema.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class SchemaGenerationTest(unittest.TestCase):
    def test_generated_schema_matches_source(self):
        self.assertEqual(
            (ROOT / "settings.schema.json").read_text(encoding="utf-8"),
            GENERATOR.generate(),
        )

    def test_module_order_is_the_single_inventory(self):
        manifest = json.loads((GENERATOR.MODULES / "manifest.json").read_text(encoding="utf-8"))
        schema = GENERATOR.build()
        self.assertEqual(
            list(schema["properties"]["modules"]["properties"]), manifest["order"]
        )
        for name in manifest["order"]:
            self.assertTrue((GENERATOR.MODULES / name / "init.lua").is_file())
            self.assertIn(
                "enabled", schema["properties"]["modules"]["properties"][name]["properties"]
            )

    def test_duplicate_modules_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "manifest.json").write_text('{"order":["editor","editor"]}')
            with patch.object(GENERATOR, "MODULES", root):
                with self.assertRaisesRegex(ValueError, "unique module names"):
                    GENERATOR.build()

    def test_malformed_module_schema_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "manifest.json").write_text('{"order":["broken"]}')
            (root / "broken").mkdir()
            (root / "broken" / "schema.json").write_text(
                json.dumps({"type": "object", "additionalProperties": True})
            )
            with patch.object(GENERATOR, "MODULES", root):
                with self.assertRaisesRegex(ValueError, "closed object"):
                    GENERATOR.build()

    def test_json_schema_validates_module_overrides(self):
        import jsonschema
        schema = GENERATOR.build()
        jsonschema.validate({"modules": {"editor": {"shiftwidth": 4}}}, schema)
        for invalid in (-1, 17, "four", None):
            with self.subTest(invalid=invalid):
                with self.assertRaises(jsonschema.ValidationError):
                    jsonschema.validate({"modules": {"editor": {"shiftwidth": invalid}}}, schema)
        with self.assertRaises(jsonschema.ValidationError):
            jsonschema.validate({"modules": {"undefined": {}}}, schema)


if __name__ == "__main__":
    unittest.main()
