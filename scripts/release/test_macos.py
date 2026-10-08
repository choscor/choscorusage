"""Tests for the macOS release tool's version, tag, identity and manifest rules."""

import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import macos

PROJECT = """\
\t\t\t\tCURRENT_PROJECT_VERSION = 7;
\t\t\t\tMARKETING_VERSION = 0.2.3;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.choscor.ChoscorUsage;
\t\t\t\tCURRENT_PROJECT_VERSION = 7;
\t\t\t\tMARKETING_VERSION = 0.2.3;
"""


class VersionTest(unittest.TestCase):
    def test_stable_accepts_x_y_z_and_rejects_prereleases_and_leading_zeros(self):
        self.assertEqual(macos.stable("1.20.3"), (1, 20, 3))
        for value in ["1.2", "01.2.3", "1.2.3-beta", "v1.2.3", "1.2.3.4", ""]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                macos.stable(value)

    def test_project_versions_reads_the_shared_marketing_and_build_numbers(self):
        self.assertEqual(macos.project_versions(PROJECT), ("0.2.3", 7))

    def test_project_versions_rejects_configurations_that_disagree(self):
        mixed = PROJECT.replace(
            "MARKETING_VERSION = 0.2.3;", "MARKETING_VERSION = 0.2.4;", 1
        )
        with self.assertRaisesRegex(ValueError, "MARKETING_VERSION"):
            macos.project_versions(mixed)

    def test_bump_sets_every_configuration_and_increments_the_build_number(self):
        bumped = macos.bumped_project(PROJECT, "0.3.0")
        self.assertEqual(macos.project_versions(bumped), ("0.3.0", 8))
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.choscor.ChoscorUsage;", bumped)

    def test_bump_refuses_a_version_that_does_not_increase(self):
        for version in ["0.2.3", "0.2.2", "0.1.9"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                macos.bumped_project(PROJECT, version)


class ChangelogTest(unittest.TestCase):
    def test_release_heading_requires_the_exact_version(self):
        text = "# Changelog\n\n## [0.3.0] - 2026-10-08\n\n### Features\n"
        self.assertTrue(macos.has_release_heading(text, "0.3.0"))
        self.assertFalse(macos.has_release_heading(text, "0.3.1"))
        self.assertFalse(macos.has_release_heading("## [10.3.0]\n", "0.3.0"))
        self.assertFalse(macos.has_release_heading("## Unreleased\n", "0.3.0"))


class TagTest(unittest.TestCase):
    def test_latest_tag_picks_the_highest_stable_version_not_the_newest_name(self):
        tags = ["v0.9.0", "v0.10.0", "v0.10.1-rc1", "nightly", "v0.2.0"]
        self.assertEqual(macos.latest_tag(tags), "v0.10.0")

    def test_latest_tag_is_none_before_the_first_release(self):
        self.assertIsNone(macos.latest_tag(["nightly", "v1.0"]))


class IdentityTest(unittest.TestCase):
    LISTING = (
        '  1) 1111111111111111111111111111111111111111 "Apple Development: A (AAAAAAAAAA)"\n'
        '  2) 2222222222222222222222222222222222222222 "Developer ID Application: B (TEAM123456)"\n'
        "     2 valid identities found\n"
    )

    def test_selects_the_only_developer_id_and_its_team(self):
        self.assertEqual(
            macos.developer_identity(self.LISTING),
            ("2222222222222222222222222222222222222222", "TEAM123456"),
        )

    def test_rejects_missing_ambiguous_or_unknown_identities(self):
        second = self.LISTING.replace(
            "     2 valid",
            '  3) 3333333333333333333333333333333333333333 "Developer ID Application: C (TEAM999999)"\n'
            "     3 valid",
        )
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            macos.developer_identity(second)
        self.assertEqual(
            macos.developer_identity(
                second, "3333333333333333333333333333333333333333"
            ),
            ("3333333333333333333333333333333333333333", "TEAM999999"),
        )
        with self.assertRaisesRegex(ValueError, "unavailable"):
            macos.developer_identity(
                self.LISTING, "1111111111111111111111111111111111111111"
            )
        with self.assertRaisesRegex(ValueError, "absent"):
            macos.developer_identity(self.LISTING.splitlines()[0])

    def test_accepts_a_lowercase_requested_sha1(self):
        listing = self.LISTING.replace("2" * 40, "ABCDEF" + "2" * 34)
        self.assertEqual(
            macos.developer_identity(listing, "abcdef" + "2" * 34),
            ("ABCDEF" + "2" * 34, "TEAM123456"),
        )


class SanitizeTest(unittest.TestCase):
    def test_removes_home_signer_names_emails_and_secrets(self):
        text = (
            f"{Path.home()}/x Developer ID Application: Jane Roe (TEAM123456)\n"
            "contact me@example.com password=hunter2"
        )
        cleaned = macos.sanitized(text)
        for leaked in [str(Path.home()), "Jane Roe", "me@example.com", "hunter2"]:
            self.assertNotIn(leaked, cleaned)

    def test_removes_the_whole_authorization_header_value(self):
        cleaned = macos.sanitized("Authorization: Bearer abc123\nnext line")
        self.assertNotIn("abc123", cleaned)
        self.assertIn("next line", cleaned)


class PreflightTest(unittest.TestCase):
    def repository(self, directory, changelog):
        root = Path(directory)
        (root / "ChoscorUsage.xcodeproj").mkdir()
        (root / "ChoscorUsage.xcodeproj/project.pbxproj").write_text(PROJECT)
        (root / "CHANGELOG.md").write_text(changelog)
        for command in [
            ["init", "-q"],
            ["add", "."],
            ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init"],
        ]:
            subprocess.run(["git", "-C", root, *command], check=True)
        return root

    def test_reports_version_build_and_commit_of_a_clean_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.repository(directory, "## [0.2.3] - 2026-10-08\n")
            record = macos.preflight(root, "0.2.3")
            self.assertEqual((record["version"], record["build"]), ("0.2.3", 7))
            self.assertRegex(record["source_commit"], r"^[0-9a-f]{40}$")
            self.assertIsNone(record["previous_tag"])

    def test_rejects_dirty_trees_version_mismatch_and_missing_changelog_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.repository(directory, "## Unreleased\n")
            with self.assertRaisesRegex(ValueError, "CHANGELOG"):
                macos.preflight(root)
            with self.assertRaisesRegex(ValueError, "does not match"):
                macos.preflight(root, "0.2.4")
            (root / "stray.txt").write_text("x")
            with self.assertRaisesRegex(ValueError, "clean"):
                macos.preflight(root)


def commit(root, message, **files):
    for name, text in files.items():
        (Path(root) / name).write_text(text)
    subprocess.run(["git", "-C", root, "add", "."], check=True)
    subprocess.run(
        ["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t"]
        + ["commit", "-qm", message],
        check=True,
    )


class ChangesTest(unittest.TestCase):
    def history(self, directory):
        root = Path(directory)
        subprocess.run(["git", "init", "-q", root], check=True)
        (root / "ChoscorUsage").mkdir()
        commit(root, "feat(app): first feature", **{"ChoscorUsage/a.swift": "one\n"})
        return root

    def test_covers_commits_and_shipped_diff_since_the_tag_but_not_the_working_tree(
        self,
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = self.history(directory)
            subprocess.run(["git", "-C", root, "tag", "v0.1.0"], check=True)
            body = "fix(app): show the reset time\n\nWhy it matters.\n\nCo-Authored-By: Bot <bot@example.com>"
            commit(root, body, **{"ChoscorUsage/a.swift": "two\n"})
            (root / "ChoscorUsage/a.swift").write_text("uncommitted\n")
            output = root / "changes.md"
            result = macos.changes(root, None, output)
            text = output.read_text()
            self.assertEqual(
                (result["since"], result["revision"]), ("v0.1.0", "v0.1.0..HEAD")
            )
            self.assertIn("fix(app): show the reset time", text)
            self.assertIn("Why it matters.", text)
            self.assertIn("+two", text)
            self.assertNotIn("first feature", text)
            self.assertNotIn("uncommitted", text)
            self.assertNotIn("bot@example.com", text)

    def test_first_release_covers_every_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.history(directory)
            output = root / "changes.md"
            self.assertIsNone(macos.changes(root, None, output)["since"])
            self.assertIn("feat(app): first feature", output.read_text())

    def test_rejects_a_since_value_that_is_not_a_release_tag(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.history(directory)
            for since in ["--output=/tmp/x", "main", "v1.0"]:
                with self.subTest(since=since), self.assertRaises(ValueError):
                    macos.changes(root, since, root / "changes.md")


class NotarizeTest(unittest.TestCase):
    def submit(self, stdout, returncode=1):
        with tempfile.TemporaryDirectory() as directory:
            logs = Path(directory)
            completed = subprocess.CompletedProcess(
                [], returncode, stdout, "stderr detail"
            )
            with patch.object(macos.subprocess, "run", return_value=completed) as run:
                with self.assertRaisesRegex(ValueError, "not Accepted"):
                    macos.notarize(logs / "a.dmg", "profile", logs)
            return run, (logs / "a.dmg.notary.log").read_text()

    def test_a_failure_without_a_submission_id_keeps_the_sanitized_reason(self):
        for stdout in [
            '{"message": "token=abc auth failed"}',
            '{"id": null, "status": null}',
        ]:
            with self.subTest(stdout=stdout):
                run, log = self.submit(stdout)
                self.assertEqual(run.call_count, 1)
                self.assertIn("stderr detail", log)
                self.assertNotIn("abc", log)

    def test_a_rejected_submission_fetches_its_notary_log(self):
        submission = "0123abcd-0123-0123-0123-0123456789ab"
        run, _ = self.submit(json.dumps({"id": submission, "status": "Invalid"}), 0)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(
            run.call_args_list[1].args[0][:4],
            ["xcrun", "notarytool", "log", submission],
        )


SIGNED = (
    "CodeDirectory v=20500 size=1892 flags=0x10000(runtime) hashes=48+7\n"
    "Authority=Developer ID Application: Someone (TEAM123456)\n"
    "Timestamp=8 Oct 2026 at 23:58:42\n"
)


class CheckAppTest(unittest.TestCase):
    def check(self, details=SIGNED, entitlements="<dict/>"):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "ChoscorUsage.app"
            (app / "Contents").mkdir(parents=True)
            with (app / "Contents/Info.plist").open("wb") as stream:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "com.choscor.ChoscorUsage",
                        "CFBundleShortVersionString": "0.2.3",
                        "CFBundleVersion": "7",
                        "LSMinimumSystemVersion": "26.0",
                    },
                    stream,
                )

            def fake(argv, **kwargs):
                argv = [str(argument) for argument in argv]
                if argv[0] == "lipo":
                    return "arm64\n"
                if "--entitlements" in argv:
                    return entitlements
                if argv[:2] == ["codesign", "-d"]:
                    self.assertEqual(kwargs.get("output"), "stderr")
                    return details
                return ""

            with patch.object(macos, "run", side_effect=fake):
                macos.check_app(app, "0.2.3", 7)

    def test_accepts_a_timestamped_developer_id_with_hardened_runtime(self):
        self.check()

    def test_rejects_missing_runtime_timestamp_or_developer_id_and_debug_entitlement(
        self,
    ):
        for details in [
            SIGNED.replace("flags=0x10000(runtime)", "flags=0x0(none)"),
            SIGNED.replace("Timestamp=", "Signed Time="),
            SIGNED.replace("Developer ID Application", "Apple Development"),
        ]:
            with (
                self.subTest(details=details),
                self.assertRaisesRegex(ValueError, "hardened"),
            ):
                self.check(details)
        with self.assertRaisesRegex(ValueError, "get-task-allow"):
            self.check(
                entitlements="<key>com.apple.security.get-task-allow</key><true/>"
            )


class ManifestTest(unittest.TestCase):
    def test_verify_rejects_a_dmg_whose_bytes_changed_after_packaging(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            dmg = output / "ChoscorUsage-0.2.3.dmg"
            dmg.write_bytes(b"signed bytes")
            manifest = output / "manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "version": "0.2.3",
                        "dmg": {"path": dmg.name, "sha256": macos.digest(dmg)},
                    }
                )
            )
            dmg.write_bytes(b"tampered bytes")
            with (
                patch.object(macos, "run") as run,
                self.assertRaisesRegex(ValueError, "SHA-256"),
            ):
                macos.verify_manifest(manifest)
            run.assert_not_called()

    def test_verify_detaches_after_a_failed_check_and_reports_that_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            dmg = output / "ChoscorUsage-0.2.3.dmg"
            dmg.write_bytes(b"signed bytes")
            manifest = output / "manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "version": "0.2.3",
                        "build": 7,
                        "dmg": {"path": dmg.name, "sha256": macos.digest(dmg)},
                    }
                )
            )
            commands = []

            def fake(argv, **_kwargs):
                commands.append([str(argument) for argument in argv][:2])
                if argv[:2] == ["hdiutil", "detach"]:
                    raise ValueError("hdiutil failed: busy")
                return ""

            with (
                patch.object(macos, "run", side_effect=fake),
                patch.object(macos, "check_app", side_effect=ValueError("bad bundle")),
                self.assertRaisesRegex(ValueError, "bad bundle"),
            ):
                macos.verify_manifest(manifest)
            self.assertEqual(commands.count(["hdiutil", "detach"]), 2)


if __name__ == "__main__":
    unittest.main()
