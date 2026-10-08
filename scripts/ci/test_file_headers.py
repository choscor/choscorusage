"""Tests for the Swift purpose-comment header gate."""

from pathlib import Path
import tempfile
import unittest

import file_headers


class FileHeaderTest(unittest.TestCase):
    def finding(self, source, name="UsageWindow.swift"):
        return file_headers.header_finding(name, source)

    def test_accepts_a_one_line_purpose_comment(self):
        source = (
            "// Normalized usage window shared by every provider.\nimport Foundation\n"
        )
        self.assertIsNone(self.finding(source))

    def test_accepts_a_two_line_purpose_comment(self):
        source = "// Owns the Claude usage decoder.\n// Endpoint is undocumented.\n\nimport X\n"
        self.assertIsNone(self.finding(source))

    def test_rejects_a_file_without_a_header(self):
        self.assertIn("purpose comment", self.finding("import Foundation\n"))

    def test_rejects_a_bare_filename_header(self):
        self.assertIsNotNone(self.finding("// UsageWindow.swift\nimport Foundation\n"))

    def test_rejects_a_doc_comment_in_place_of_a_purpose_comment(self):
        self.assertIsNotNone(self.finding("/// A window.\nstruct UsageWindow {}\n"))

    def test_rejects_a_header_longer_than_two_lines(self):
        source = "// One.\n// Two.\n// Three.\nimport Foundation\n"
        self.assertIsNotNone(self.finding(source))

    def test_rejects_an_empty_comment(self):
        self.assertIsNotNone(self.finding("//\nimport Foundation\n"))

    def test_main_fails_for_a_directory_containing_an_unheaded_file(self):
        with tempfile.TemporaryDirectory() as temp:
            good = Path(temp) / "Good.swift"
            good.write_text("// Owns good things.\n", encoding="utf-8")
            bad = Path(temp) / "Bad.swift"
            bad.write_text("import Foundation\n", encoding="utf-8")
            self.assertEqual(file_headers.main([str(good)]), 0)
            self.assertEqual(file_headers.main([str(good), str(bad)]), 1)


if __name__ == "__main__":
    unittest.main()
