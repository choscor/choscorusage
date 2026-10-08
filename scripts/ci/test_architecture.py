"""Tests for the per-layer banned-API gate."""

from pathlib import Path
import tempfile
import unittest

import architecture

SOURCES = "Packages/ChoscorUsageKit/Sources"


class ArchitectureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative, source):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")

    def findings(self):
        return architecture.findings(self.root)

    def test_clean_layers_pass(self):
        self.write(f"{SOURCES}/ChoscorUsageCore/Clock.swift", "import Foundation\n")
        self.write(
            f"{SOURCES}/ChoscorUsageProviders/T.swift",
            "import Security\nlet s = URLSession.shared\n",
        )
        self.write(
            f"{SOURCES}/ChoscorUsageKit/S.swift", "import Observation\nimport os\n"
        )
        self.write("ChoscorUsage/App.swift", "import SwiftUI\nimport ChoscorUsageKit\n")
        self.assertEqual(self.findings(), [])

    def test_url_session_in_core_fails(self):
        self.write(
            f"{SOURCES}/ChoscorUsageCore/Fetch.swift", "let s = URLSession.shared\n"
        )
        [finding] = self.findings()
        self.assertIn("ChoscorUsageCore/Fetch.swift:1", finding)
        self.assertIn("URLSession", finding)

    def test_swiftui_in_kit_fails(self):
        self.write(
            f"{SOURCES}/ChoscorUsageKit/Store.swift",
            "import Foundation\nimport SwiftUI\n",
        )
        [finding] = self.findings()
        self.assertIn("ChoscorUsageKit/Store.swift:2", finding)

    def test_security_in_the_app_fails(self):
        self.write("ChoscorUsage/Glue.swift", "import Security\n")
        self.assertEqual(len(self.findings()), 1)

    def test_app_may_not_import_lower_layers_directly(self):
        self.write("ChoscorUsage/Glue.swift", "import ChoscorUsageProviders\n")
        self.assertEqual(len(self.findings()), 1)

    def test_core_rejects_unlisted_modules_and_json_decoding(self):
        self.write(
            f"{SOURCES}/ChoscorUsageCore/A.swift",
            "import OSLog\nlet d = JSONDecoder()\n",
        )
        self.assertEqual(len(self.findings()), 2)

    def test_names_in_comments_and_strings_are_ignored(self):
        source = '// Never uses URLSession here.\nlet note = "FileManager"\n'
        self.write(f"{SOURCES}/ChoscorUsageCore/Doc.swift", source)
        self.assertEqual(self.findings(), [])

    def test_names_inside_string_interpolation_are_still_code(self):
        source = 'let home = "\\(FileManager.default.homeDirectoryForCurrentUser)"\n'
        self.write(f"{SOURCES}/ChoscorUsageCore/Home.swift", source)
        self.assertEqual(len(self.findings()), 1)


if __name__ == "__main__":
    unittest.main()
