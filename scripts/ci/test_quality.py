"""Tests for the repository-owned quality command interface and workflow policy."""

import contextlib
import io
from pathlib import Path
import re
import unittest
from unittest.mock import patch

import quality

WORKFLOWS = quality.ROOT / ".github/workflows"
USES = re.compile(r"^\s*-?\s*uses:\s*(\S+)(.*)$", re.MULTILINE)


class QualityCommandTest(unittest.TestCase):
    def run_stage(self, stage):
        calls = []

        def record(command, **_kwargs):
            calls.append([str(argument) for argument in command])

        with (
            patch.object(quality, "require_tool", side_effect=lambda tool, **_: tool),
            patch.object(quality, "actionlint_tool", return_value="actionlint"),
            patch.object(quality, "swiftlint_binary", return_value=Path("swiftlint")),
            patch.object(quality, "check_suppressions"),
            patch.object(quality, "require_compiler_log"),
            patch.dict(
                quality.STAGES, {"app-build": lambda: calls.append(["app-build"])}
            ),
            patch.object(quality, "run_command", side_effect=record),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(quality.main([stage]), 0)
        return calls

    def test_fast_runs_format_lint_policy_python_workflow_and_kit_gates_in_order(self):
        commands = self.run_stage("fast")
        self.assertEqual(
            [command[:3] for command in commands],
            [
                ["swift", "format", "lint"],
                ["swiftlint", "lint", "--strict"],
                [quality.PYTHON, "scripts/ci/architecture.py"],
                [quality.PYTHON, "scripts/ci/file_headers.py"],
                [quality.PYTHON, "scripts/ci/secrets_policy.py"],
                ["ruff", "check", "scripts"],
                ["ruff", "format", "--check"],
                [quality.PYTHON, "-m", "unittest"],
                ["actionlint", "-color"],
                ["swift", "test", "--package-path"],
            ],
        )

    def test_full_adds_app_build_then_swiftlint_analyze(self):
        commands = self.run_stage("full")
        self.assertEqual(commands[-2], ["app-build"])
        self.assertEqual(commands[-1][:3], ["swiftlint", "analyze", "--strict"])
        self.assertIn(quality.XCODE_LOG, commands[-1])

    def test_swift_format_lint_is_strict_and_recursive_over_first_party_roots(self):
        [command] = self.run_stage("swift-format")
        self.assertEqual(
            command,
            [
                "swift",
                "format",
                "lint",
                "--strict",
                "--recursive",
                *quality.SWIFT_ROOTS,
            ],
        )

    def test_format_is_a_focused_stage_outside_fast_and_full(self):
        self.assertNotIn("format", quality.FULL_STAGES)
        [command] = self.run_stage("format")
        self.assertEqual(command[:4], ["swift", "format", "--in-place", "--recursive"])

    def test_missing_tool_reports_the_install_command(self):
        stderr = io.StringIO()
        with (
            patch.object(quality.shutil, "which", return_value=None),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(stderr),
        ):
            self.assertEqual(quality.main(["actionlint"]), 2)
        self.assertIn(
            "go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7",
            stderr.getvalue(),
        )

    def test_help_lists_the_aggregate_stages(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout), self.assertRaises(SystemExit):
            quality.main(["--help"])
        self.assertIn("swiftlint-install", stdout.getvalue())
        self.assertIn("full", stdout.getvalue())


class WorkflowPolicyTest(unittest.TestCase):
    def workflows(self):
        paths = sorted(WORKFLOWS.glob("*.yml"))
        self.assertEqual([path.name for path in paths], ["ci.yml", "security.yml"])
        return {path.name: path.read_text(encoding="utf-8") for path in paths}

    def test_every_action_is_pinned_by_full_commit_sha_with_a_version_comment(self):
        for name, text in self.workflows().items():
            uses = USES.findall(text)
            self.assertTrue(uses, name)
            for reference, comment in uses:
                with self.subTest(workflow=name, action=reference):
                    self.assertRegex(reference, r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")
                    self.assertRegex(comment, r"#\s*v\d")

    def test_every_workflow_is_read_only_concurrent_and_time_bounded(self):
        for name, text in self.workflows().items():
            with self.subTest(workflow=name):
                self.assertRegex(text, r"(?m)^permissions:\n  contents: read$")
                self.assertIn("cancel-in-progress: true", text)
                jobs = len(re.findall(r"(?m)^    runs-on:", text))
                self.assertEqual(
                    jobs, len(re.findall(r"(?m)^    timeout-minutes:", text))
                )
                checkouts = text.count("actions/checkout@")
                self.assertEqual(checkouts, text.count("persist-credentials: false"))

    def test_ci_runs_only_the_quality_entry_point(self):
        text = self.workflows()["ci.yml"]
        runs = re.findall(r"python scripts/ci/quality\.py (\S+)", text)
        self.assertEqual(runs, ["swiftlint-install", "full"])

    def test_security_reviews_dependencies_on_pull_requests_and_weekly(self):
        text = self.workflows()["security.yml"]
        self.assertIn("pull_request:", text)
        self.assertRegex(text, r"cron: '\d+ \d+ \* \* 1'")
        self.assertIn("actions/dependency-review-action@", text)


if __name__ == "__main__":
    unittest.main()
