"""Run the pinned SwiftLint with the repository config against synthetic limit breaches."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import quality

HEADER = "// Synthetic source for the SwiftLint limits test.\n"


def function_with_body(lines):
    body = "".join(f"    _ = {index}\n" for index in range(lines))
    return f"{HEADER}func sample() {{\n{body}}}\n"


class SwiftLintLimitsTest(unittest.TestCase):
    def lint(self, source, name="Sample.swift", directory="ChoscorUsage"):
        """Lint one file in a temporary copy of the repository's SwiftLint configs."""
        binary = quality.swiftlint_binary()
        nested = "Packages/ChoscorUsageKit/Sources/.swiftlint.yml"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copy(quality.ROOT / ".swiftlint.yml", root / ".swiftlint.yml")
            (root / nested).parent.mkdir(parents=True)
            shutil.copy(quality.ROOT / nested, root / nested)
            target = root / directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source, encoding="utf-8")
            completed = subprocess.run(
                [binary, *quality.SWIFTLINT_LINT_ARGS],
                cwd=root,
                text=True,
                capture_output=True,
            )
        return completed.returncode, completed.stdout

    def assert_violates(
        self, rule, source, name="Sample.swift", directory="ChoscorUsage"
    ):
        code, output = self.lint(source, name, directory)
        self.assertNotEqual(code, 0, output)
        self.assertIn(f"({rule})", output)

    def test_a_forty_line_function_body_passes(self):
        code, output = self.lint(function_with_body(40))
        self.assertEqual(code, 0, output)

    def test_a_forty_one_line_function_body_fails(self):
        self.assert_violates("function_body_length", function_with_body(41))

    def test_a_four_hundred_one_line_file_fails(self):
        source = HEADER + "".join(f"let value{n} = {n}\n" for n in range(400))
        self.assert_violates("file_length", source)

    def test_a_line_longer_than_one_hundred_twenty_fails(self):
        self.assert_violates("line_length", HEADER + f'let text = "{"x" * 120}"\n')

    def test_six_parameters_fail(self):
        source = HEADER + "func f(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {}\n"
        self.assert_violates("function_parameter_count", source)

    def test_a_todo_without_an_issue_fails_but_one_with_an_issue_passes(self):
        self.assert_violates("todo_requires_issue", HEADER + "// TODO: later\n")
        code, output = self.lint(HEADER + "// TODO(#12): handle plan changes\n")
        self.assertEqual(code, 0, output)

    def test_print_and_commented_out_code_fail(self):
        self.assert_violates("no_print", HEADER + 'func f() { print("x") }\n')
        self.assert_violates("no_commented_out_code", HEADER + "// let old = 1\n")

    def test_package_sources_require_explicit_access_control(self):
        package = "Packages/ChoscorUsageKit/Sources/ChoscorUsageCore"
        source = HEADER + "struct Implicit {}\n"
        self.assert_violates("explicit_acl", source, directory=package)
        code, output = self.lint(source)
        self.assertEqual(code, 0, "the app target does not require explicit ACL")

    def test_catch_all_file_names_fail(self):
        self.assert_violates(
            "no_catch_all_files", HEADER + "enum Text {}\n", "Helpers.swift"
        )


if __name__ == "__main__":
    unittest.main()
