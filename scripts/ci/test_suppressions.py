"""Tests for the narrow, justified SwiftLint suppression policy."""

import unittest

import quality


class SuppressionPolicyTest(unittest.TestCase):
    def findings(self, source):
        return quality.suppression_findings("Sample.swift", source)

    def test_accepts_a_single_rule_next_line_disable_with_a_reason(self):
        source = "// swiftlint:disable:next force_unwrapping - literal URL is valid\n"
        self.assertEqual(self.findings(source), [])

    def test_rejects_an_em_dash_reason_that_swiftlint_would_parse_as_rules(self):
        source = (
            "// swiftlint:disable:next force_unwrapping \u2014 literal URL is valid\n"
        )
        self.assertEqual(len(self.findings(source)), 1)

    def test_rejects_a_disable_without_a_reason(self):
        findings = self.findings("// swiftlint:disable:next force_unwrapping\n")
        self.assertEqual(len(findings), 1)
        self.assertIn("Sample.swift:1", findings[0])

    def test_rejects_a_file_wide_disable_even_with_a_reason(self):
        findings = self.findings("// swiftlint:disable line_length - long table\n")
        self.assertEqual(len(findings), 1)

    def test_rejects_disabling_all_rules(self):
        self.assertEqual(len(self.findings("// swiftlint:disable:next all - x\n")), 1)

    def test_rejects_more_than_one_rule(self):
        source = "// swiftlint:disable:next line_length force_cast - reason\n"
        self.assertEqual(len(self.findings(source)), 1)

    def test_reports_the_offending_line_number(self):
        source = "import Foundation\n\n// swiftlint:disable:this todo\n"
        self.assertIn("Sample.swift:3", self.findings(source)[0])


if __name__ == "__main__":
    unittest.main()
