#!/usr/bin/env python3
"""Run ChoscorUsage's canonical local quality gates."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

from swift_sources import PACKAGE, SWIFT_ROOTS, swift_files


ROOT = Path(__file__).resolve().parents[2]
PYTHON = sys.executable
TOOLS = json.loads((ROOT / "scripts/ci/tools.json").read_text(encoding="utf-8"))
TOOLS_ROOT = ROOT / "build/tools"
XCODE_LOG = "build/xcodebuild.log"
# No `--config`: SwiftLint then reads `.swiftlint.yml` from the repository root and merges
# nested configs such as the package's `explicit_acl` opt-in, which `--config` would ignore.
SWIFTLINT_LINT_ARGS = ("lint", "--strict", "--quiet")
INSTALL_SWIFTLINT = "run `python scripts/ci/quality.py swiftlint-install`"
INSTALL_PYTHON_TOOLS = f"{PYTHON} -m pip install -r scripts/ci/requirements.txt"


class QualityError(RuntimeError):
    """A quality stage cannot start because its prerequisites are unavailable."""


def run_command(command, **kwargs):
    """Print and run a quality command from the repository root."""
    rendered = subprocess.list2cmdline([str(argument) for argument in command])
    print(f"Running: {rendered}", flush=True)
    subprocess.run(command, check=True, cwd=ROOT, **kwargs)


def require_tool(tool, *, install):
    """Require an executable and provide stage-specific installation guidance."""
    if shutil.which(tool) is None:
        raise QualityError(
            f"Required tool '{tool}' was not found. Install it with: {install}"
        )
    return tool


def require_pinned_tool(tool, version_args, expected, *, install):
    """Require a tool and reject a version outside the repository pin."""
    executable = require_tool(tool, install=install)
    command = [executable, *version_args]
    print(f"Running: {subprocess.list2cmdline(command)}", flush=True)
    completed = subprocess.run(
        command,
        check=True,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    reported = completed.stdout.strip()
    versions = re.findall(r"(?<![\d.])v?(\d+\.\d+\.\d+)(?![\d.])", reported)
    if not versions or versions[0] != expected:
        raise QualityError(
            f"{tool} must be version {expected}, but reported: {reported or '<no version>'}. "
            f"Install it with: {install}"
        )
    return executable


def sha256_of(path):
    """Return the hex SHA-256 of a file."""
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def swiftlint_directory(spec, tools_root):
    return Path(tools_root) / "swiftlint" / spec["version"]


def verified_install(spec, tools_root):
    """Return the cached binary only if the archive matches the pin and the binary is unchanged."""
    directory = swiftlint_directory(spec, tools_root)
    archive = directory / "portable_swiftlint.zip"
    binary = directory / "swiftlint"
    recorded = directory / "swiftlint.sha256"
    if not (archive.is_file() and binary.is_file() and recorded.is_file()):
        return None
    if sha256_of(archive) != spec["sha256"]:
        return None
    if sha256_of(binary) != recorded.read_text(encoding="utf-8").strip():
        return None
    return binary


def install_swiftlint(spec, tools_root):
    """Download, verify, and unpack the pinned SwiftLint; a verified copy is kept."""
    directory = swiftlint_directory(spec, tools_root)
    binary = directory / "swiftlint"
    if verified_install(spec, tools_root):
        print(f"SwiftLint {spec['version']} already installed at {binary}", flush=True)
        return binary
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=directory) as staging:
        download = Path(staging) / "portable_swiftlint.zip"
        print(f"Downloading: {spec['url']}", flush=True)
        with urllib.request.urlopen(spec["url"], timeout=120) as response:
            download.write_bytes(response.read())
        actual = sha256_of(download)
        if actual != spec["sha256"]:
            raise QualityError(
                f"SwiftLint archive SHA-256 mismatch: expected {spec['sha256']}, got {actual}"
            )
        with zipfile.ZipFile(download) as bundle:
            bundle.extract("swiftlint", staging)
        extracted = Path(staging) / "swiftlint"
        extracted.chmod(0o755)
        # The archive lands last: it marks a complete install, so an interrupted one is redone.
        (directory / "portable_swiftlint.zip").unlink(missing_ok=True)
        extracted.replace(binary)
        (directory / "swiftlint.sha256").write_text(sha256_of(binary), encoding="utf-8")
        download.replace(directory / "portable_swiftlint.zip")
    print(f"Installed SwiftLint {spec['version']} at {binary}", flush=True)
    return binary


def swiftlint_binary(spec=None, tools_root=TOOLS_ROOT):
    """Return the cached, verified SwiftLint; never a copy found on PATH."""
    spec = spec or TOOLS["swiftlint"]
    binary = verified_install(spec, tools_root)
    if binary is None:
        raise QualityError(
            f"Pinned SwiftLint {spec['version']} is not installed; {INSTALL_SWIFTLINT}"
        )
    return binary


def swiftlint_install():
    install_swiftlint(TOOLS["swiftlint"], TOOLS_ROOT)


def swift_format_tool():
    return require_tool(
        "swift", install="xcode-select --install (or install Xcode 26 and select it)"
    )


def format_sources():
    run_command(
        [swift_format_tool(), "format", "--in-place", "--recursive", *SWIFT_ROOTS]
    )


def swift_format():
    run_command(
        [swift_format_tool(), "format", "lint", "--strict", "--recursive", *SWIFT_ROOTS]
    )


SUPPRESSION = re.compile(r"swiftlint:(?:disable|enable)\S*")
ALLOWED_SUPPRESSION = re.compile(
    r"swiftlint:disable:(?:next|this|previous) (?!all\b)[a-z_]+ - \S"
)


def suppression_findings(name, source):
    """Return suppressions that are file-wide, cover several rules, or lack a reason."""
    findings = []
    for number, line in enumerate(source.splitlines(), start=1):
        if SUPPRESSION.search(line) and not ALLOWED_SUPPRESSION.search(line):
            findings.append(
                f"{name}:{number}: use `swiftlint:disable:next <rule> - <reason>` "
                "naming one rule; file-wide, `all`, and unexplained disables are rejected"
            )
    return findings


def check_suppressions():
    findings = []
    for path in swift_files():
        source = (ROOT / path).read_text(encoding="utf-8")
        findings.extend(suppression_findings(str(path), source))
    if findings:
        print("\n".join(findings), file=sys.stderr)
        raise QualityError(f"{len(findings)} SwiftLint suppression(s) violate policy")


def swiftlint():
    binary = swiftlint_binary()
    check_suppressions()
    run_command([binary, *SWIFTLINT_LINT_ARGS])


def architecture():
    run_command([PYTHON, "scripts/ci/architecture.py"])


def file_headers():
    run_command([PYTHON, "scripts/ci/file_headers.py"])


def secrets_policy():
    run_command([PYTHON, "scripts/ci/secrets_policy.py"])


def python_checks():
    ruff = require_tool("ruff", install=INSTALL_PYTHON_TOOLS)
    run_command([ruff, "check", "scripts"])
    run_command([ruff, "format", "--check", "scripts"])
    run_command(
        [PYTHON, "-m", "unittest", "discover", "-s", "scripts/ci", "-p", "test_*.py"]
    )


def actionlint_tool():
    version = TOOLS["actionlint"]["version"]
    return require_pinned_tool(
        "actionlint",
        ["-version"],
        version,
        install=f"go install github.com/rhysd/actionlint/cmd/actionlint@v{version}",
    )


def actionlint():
    run_command([actionlint_tool(), "-color"])


def kit_tests():
    swift = require_tool("swift", install="install Xcode 26 and run xcode-select")
    run_command([swift, "test", "--package-path", PACKAGE])


def app_build():
    xcodebuild = require_tool(
        "xcodebuild", install="install Xcode 26 from the App Store"
    )
    (ROOT / "build").mkdir(exist_ok=True)
    command = [
        xcodebuild,
        "-project",
        "ChoscorUsage.xcodeproj",
        "-scheme",
        "ChoscorUsage",
        "-destination",
        "platform=macOS,arch=arm64",
        "-derivedDataPath",
        "build/DerivedData",
        # `clean` keeps every file's compiler invocation in the log for `swiftlint analyze`.
        "clean",
        "build",
        "test",
        "CODE_SIGNING_ALLOWED=NO",
        "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
    ]
    rendered = subprocess.list2cmdline(command)
    print(f"Running: {rendered} > {XCODE_LOG}", flush=True)
    with open(ROOT / XCODE_LOG, "w", encoding="utf-8") as log:
        completed = subprocess.run(
            command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT
        )
    if completed.returncode != 0:
        print(f"xcodebuild failed; see {XCODE_LOG}", file=sys.stderr)
        tail = (ROOT / XCODE_LOG).read_text(encoding="utf-8").splitlines()[-40:]
        print("\n".join(tail), file=sys.stderr)
        raise subprocess.CalledProcessError(completed.returncode, command)


def require_compiler_log():
    if not (ROOT / XCODE_LOG).is_file():
        raise QualityError(
            f"{XCODE_LOG} is missing; run `python scripts/ci/quality.py app-build` first"
        )


def swiftlint_analyze():
    binary = swiftlint_binary()
    require_compiler_log()
    run_command(
        [
            binary,
            "analyze",
            "--strict",
            "--quiet",
            "--config",
            ".swiftlint.yml",
            "--compiler-log-path",
            XCODE_LOG,
        ]
    )


STAGES = {
    "swiftlint-install": swiftlint_install,
    "format": format_sources,
    "swift-format": swift_format,
    "swiftlint": swiftlint,
    "architecture": architecture,
    "file-headers": file_headers,
    "secrets-policy": secrets_policy,
    "python": python_checks,
    "actionlint": actionlint,
    "kit-tests": kit_tests,
    "app-build": app_build,
    "swiftlint-analyze": swiftlint_analyze,
}

FAST_STAGES = (
    "swift-format",
    "swiftlint",
    "architecture",
    "file-headers",
    "secrets-policy",
    "python",
    "actionlint",
    "kit-tests",
)
FULL_STAGES = (*FAST_STAGES, "app-build", "swiftlint-analyze")
STAGE_HELP = """stages:
  fast               swift-format, swiftlint, architecture, file-headers,
                     secrets-policy, python, actionlint, kit-tests
  full               fast plus app-build and swiftlint-analyze
  swiftlint-install  download and verify the pinned SwiftLint (run before fast/full)
  format             rewrite first-party Swift with swift-format (not part of fast/full)
"""


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=STAGE_HELP,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("stage", choices=["fast", "full", *STAGES])
    args = parser.parse_args(argv)
    selected = (
        FAST_STAGES
        if args.stage == "fast"
        else FULL_STAGES
        if args.stage == "full"
        else (args.stage,)
    )
    try:
        for stage in selected:
            print(f"\n== {stage} ==", flush=True)
            STAGES[stage]()
    except QualityError as error:
        print(f"quality: {error}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as error:
        return error.returncode or 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
