"""Tests for the pinned, checksum-verified SwiftLint installation."""

import contextlib
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

import quality


def make_archive(directory):
    """Write a portable_swiftlint.zip look-alike and return its file URL and SHA-256."""
    archive = Path(directory) / "portable_swiftlint.zip"
    with zipfile.ZipFile(archive, "w") as bundle:
        bundle.writestr("swiftlint", "#!/bin/sh\necho 0.0.1\n")
        bundle.writestr("LICENSE", "MIT")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    return archive.as_uri(), digest


class SwiftLintInstallTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        url, digest = make_archive(self.root)
        self.spec = {"version": "0.0.1", "url": url, "sha256": digest}
        self.tools = self.root / "tools"

    def install(self, spec):
        with contextlib.redirect_stdout(io.StringIO()):
            return quality.install_swiftlint(spec, self.tools)

    def test_installs_an_executable_binary_under_the_versioned_directory(self):
        binary = self.install(self.spec)
        self.assertEqual(binary, self.tools / "swiftlint" / "0.0.1" / "swiftlint")
        self.assertTrue(binary.is_file())
        self.assertTrue(binary.stat().st_mode & 0o111)

    def test_rejects_an_archive_whose_checksum_does_not_match(self):
        tampered = dict(self.spec, sha256="0" * 64)
        with self.assertRaisesRegex(quality.QualityError, "SHA-256 mismatch"):
            self.install(tampered)
        self.assertFalse((self.tools / "swiftlint" / "0.0.1" / "swiftlint").exists())

    def test_second_install_is_a_no_op_once_a_verified_copy_exists(self):
        self.install(self.spec)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            quality.install_swiftlint(
                dict(self.spec, url="file:///missing.zip"), self.tools
            )
        self.assertIn("already installed", output.getvalue())

    def test_missing_binary_names_the_install_command(self):
        with self.assertRaisesRegex(
            quality.QualityError,
            r"run `python scripts/ci/quality.py swiftlint-install`",
        ):
            quality.swiftlint_binary(self.spec, self.tools)

    def test_a_binary_changed_after_install_is_rejected_and_reinstalled(self):
        binary = self.install(self.spec)
        binary.write_text("#!/bin/sh\necho tampered\n")
        with self.assertRaisesRegex(quality.QualityError, "not installed"):
            quality.swiftlint_binary(self.spec, self.tools)
        self.install(self.spec)
        self.assertIn("0.0.1", binary.read_text())

    def test_installed_binary_is_resolved_from_the_cache_not_path(self):
        installed = self.install(self.spec)
        self.assertEqual(quality.swiftlint_binary(self.spec, self.tools), installed)


if __name__ == "__main__":
    unittest.main()
