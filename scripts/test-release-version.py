#!/usr/bin/env python3
"""Local release-script checks; no simulator, signing, or network access."""
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("release_version", Path(__file__).with_name("next-release-version.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / "project.yml"
        self.write_version("1.0")

    def write_version(self, version):
        self.project.write_text(f'  MARKETING_VERSION: "{version}"\n  CURRENT_PROJECT_VERSION: "5"\n  OTHER: keep\n')

    def test_minor_normalizes_existing_version_and_preserves_other_settings(self):
        self.assertEqual(release.advance(self.root, "minor", "6"), "1.0.1")
        self.assertIn('CURRENT_PROJECT_VERSION: "6"', self.project.read_text())
        self.assertIn("OTHER: keep", self.project.read_text())
        self.assertEqual(release.advance(self.root, "minor", "7"), "1.0.2")

    def test_big_resets_patch(self):
        self.write_version("1.0.8")
        self.assertEqual(release.advance(self.root, "big", "6"), "1.1.0")

    def test_patch_is_an_integer_not_decimal_arithmetic(self):
        self.write_version("1.0.9")
        self.assertEqual(release.advance(self.root, "minor", "6"), "1.0.10")

    def test_older_checkout_advances_past_existing_archive(self):
        info = self.root / "DerivedData/Archives/prior.xcarchive/Products/Applications/Untitled Faith.app/Info.plist"
        info.parent.mkdir(parents=True)
        info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.lukefournier.UntitledFaith", "CFBundleShortVersionString": "1.2.3"}))
        self.assertEqual(release.advance(self.root, "minor", "6"), "1.2.4")

    def test_invalid_inputs_leave_project_unchanged(self):
        original = self.project.read_text()
        for size, build in [("typo", "6"), ("minor", "0"), ("big", "bad")]:
            with self.subTest(size=size, build=build), self.assertRaises(ValueError):
                release.advance(self.root, size, build)
            self.assertEqual(self.project.read_text(), original)

    def test_ambiguous_settings_are_rejected(self):
        self.project.write_text(self.project.read_text() + '  MARKETING_VERSION: "2.0"\n')
        original = self.project.read_text()
        with self.assertRaises(ValueError):
            release.advance(self.root, "minor", "6")
        self.assertEqual(self.project.read_text(), original)


if __name__ == "__main__":
    unittest.main()
