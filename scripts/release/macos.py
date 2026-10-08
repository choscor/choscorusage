#!/usr/bin/env python3
"""Prepare, package, notarize and verify a ChoscorUsage macOS release.

The app has no auto-update channel: a release is one Developer ID signed,
notarized and stapled DMG attached to a GitHub Release. This tool never creates
tags or publishes; the release-version skill does that after `verify` passes.
"""

import argparse
import contextlib
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PROJECT = "ChoscorUsage.xcodeproj/project.pbxproj"
APP = "ChoscorUsage"
BUNDLE_ID = "com.choscor.ChoscorUsage"
MINIMUM_MACOS = "26.0"
NOTARY_PROFILE = "agents-notary"
STABLE = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
# Bit 0x10000 in the CodeDirectory flags is the hardened runtime notarization requires.
HARDENED_RUNTIME = 0x10000
LOG_DIRECTORY = None


def sanitized(text):
    """Strip the home path, signer name, emails and secret-looking values from tool output."""
    text = text.replace(str(Path.home()), "<home>")
    text = re.sub(
        r"Developer ID Application:[^\n\"]+",
        "Developer ID Application: <redacted>",
        text,
    )
    text = re.sub(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", "<email>", text, flags=re.I)
    # Redact to the end of the line: header values such as `Bearer <token>` contain spaces.
    text = re.sub(
        r"(?i)(password|token|secret|authorization)\s*[:=][^\n]*",
        r"\1=<redacted>",
        text,
    )
    return text[-32000:]


def run(argv, output="stdout", **kwargs):
    """Run a tool and return its stdout (or stderr, where codesign prints details).

    Keeps a sanitized failure log and raises ValueError on a non-zero exit.
    """
    result = subprocess.run(
        [str(argument) for argument in argv],
        capture_output=True,
        text=True,
        timeout=7200,
        **kwargs,
    )
    if result.returncode:
        detail = sanitized(result.stdout + "\n" + result.stderr)
        if LOG_DIRECTORY is not None:
            with (LOG_DIRECTORY / "failures.log").open("a") as log:
                log.write(f"{Path(str(argv[0])).name} {argv[1:2]}\n{detail}\n")
        raise ValueError(
            f"{Path(str(argv[0])).name} failed (exit {result.returncode}); {detail[-4000:]}"
        )
    return result.stderr if output == "stderr" else result.stdout


def stable(value):
    """Return (major, minor, patch) for a stable X.Y.Z version without leading zeros."""
    match = re.fullmatch(STABLE, value) if isinstance(value, str) else None
    if match is None:
        raise ValueError(f"Release version must be stable X.Y.Z, got {value!r}")
    return tuple(map(int, match.groups()))


def project_versions(text):
    """Return the (marketing version, build number) every build configuration shares."""
    marketing = set(re.findall(r"\bMARKETING_VERSION = ([^;]+);", text))
    builds = set(re.findall(r"\bCURRENT_PROJECT_VERSION = ([^;]+);", text))
    if len(marketing) != 1:
        raise ValueError(
            f"MARKETING_VERSION differs between configurations: {sorted(marketing)}"
        )
    if len(builds) != 1 or not next(iter(builds)).isdigit():
        raise ValueError(
            f"CURRENT_PROJECT_VERSION must be one integer: {sorted(builds)}"
        )
    version = marketing.pop()
    stable(version)
    return version, int(builds.pop())


def bumped_project(text, version):
    """Return project text with a higher marketing version and the next build number."""
    current, build = project_versions(text)
    if stable(version) <= stable(current):
        raise ValueError(
            f"Version {version} must be greater than the project's {current}"
        )
    text = re.sub(
        r"\bMARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {version};", text
    )
    return re.sub(
        r"\bCURRENT_PROJECT_VERSION = [^;]+;",
        f"CURRENT_PROJECT_VERSION = {build + 1};",
        text,
    )


def has_release_heading(changelog, version):
    """Report whether CHANGELOG.md has a `## [X.Y.Z]` section for this version."""
    return (
        re.search(rf"^## \[{re.escape(version)}\](?:\s|$)", changelog, re.M) is not None
    )


def latest_tag(tags):
    """Return the highest stable `vX.Y.Z` tag, or None before the first release."""
    releases = [tag for tag in tags if re.fullmatch("v" + STABLE, tag)]
    return max(releases, key=lambda tag: stable(tag[1:]), default=None)


def developer_identity(listing, requested=None):
    """Pick a Developer ID Application identity from `security find-identity` output.

    Returns (certificate SHA-1, team ID). Raises when none, several without a
    request, or the requested one is unavailable.
    """
    found = dict(
        re.findall(
            r'\b([A-F0-9]{40}) "Developer ID Application:[^"]*\(([A-Z0-9]{10})\)"',
            listing,
        )
    )
    if requested is not None:
        requested = requested.upper()
        if requested not in found:
            raise ValueError("Requested Developer ID identity unavailable")
        return requested, found[requested]
    if len(found) != 1:
        raise ValueError(
            "Developer ID identity absent or ambiguous; pass --identity with the certificate SHA-1"
        )
    return next(iter(found.items()))


def git(root, *args):
    return run(["git", "-C", root, *args]).strip()


def preflight(root, version=None):
    """Check a clean checkout whose project version and changelog agree on the release."""
    root = Path(root).resolve(strict=True)
    if git(root, "status", "--porcelain", "--untracked-files=all"):
        raise ValueError(
            "Release packaging requires a clean tracked and untracked checkout"
        )
    marketing, build = project_versions((root / PROJECT).read_text())
    if version is not None and version != marketing:
        raise ValueError(
            f"Requested {version} does not match project version {marketing}"
        )
    if not has_release_heading((root / "CHANGELOG.md").read_text(), marketing):
        raise ValueError(f"CHANGELOG.md needs a `## [{marketing}]` section")
    return {
        "version": marketing,
        "build": build,
        "source_commit": git(root, "rev-parse", "HEAD"),
        "previous_tag": latest_tag(git(root, "tag", "--list", "v*").split()),
    }


def bump(root, version):
    path = Path(root) / PROJECT
    path.write_text(bumped_project(path.read_text(), version))
    marketing, build = project_versions(path.read_text())
    return {"version": marketing, "build": build}


def commit_log(root, revision):
    """Return commit subjects and bodies without trailers or email addresses.

    The text goes to a drafting model, so attribution trailers and addresses stay out.
    """
    text = git(root, "log", "--no-merges", "--format=### %s%n%n%b", revision)
    text = re.sub(
        r"(?m)^(?:[A-Za-z-]+: .*<[^>\n]*@[^>\n]*>|🤖 Generated with .*)\n?", "", text
    )
    return re.sub(r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", "<email>", text, flags=re.I)


def changes(root, since, output):
    """Write the commits and committed diff since a tag (or every commit) for note drafting."""
    root = Path(root).resolve(strict=True)
    if since is not None and not re.fullmatch("v" + STABLE, since):
        raise ValueError(f"--since must be a vX.Y.Z tag, got {since!r}")
    since = since or latest_tag(git(root, "tag", "--list", "v*").split())
    revision = f"{since}..HEAD" if since else "HEAD"
    # Compare with HEAD, not the working tree, so uncommitted edits never become notes.
    sections = [
        f"# Changes in {revision}",
        "## Commits",
        commit_log(root, revision),
        "## Files",
        git(root, "diff", "--stat", since, "HEAD") if since else git(root, "ls-files"),
    ]
    if since:
        # Tests, CI and scripts never reach users; the diff of shipped code backs each claim.
        shipped = ["ChoscorUsage", "Packages/ChoscorUsageKit/Sources", "CHANGELOG.md"]
        diff = git(root, "diff", since, "HEAD", "--", *shipped)
        sections += ["## Shipped code diff", diff]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n\n".join(sections) + "\n")
    return {"since": since, "revision": revision, "path": str(output)}


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def notarize(artifact, profile, logs):
    """Submit to the notary service and wait; keep only the id, status and a sanitized log."""
    process = subprocess.run(
        ["xcrun", "notarytool", "submit", str(artifact), "--keychain-profile", profile]
        + ["--wait", "--output-format", "json"],
        capture_output=True,
        text=True,
        timeout=7200,
    )
    try:
        result = json.loads(process.stdout)
    except ValueError:
        (logs / f"{artifact.name}.notary.log").write_text(
            sanitized(process.stdout + "\n" + process.stderr)
        )
        raise ValueError(
            "Notarization returned no JSON; see the sanitized log"
        ) from None
    save(
        logs / f"{artifact.name}.notary.json",
        {k: result.get(k) for k in ["id", "status"]},
    )
    if process.returncode or result.get("status") != "Accepted":
        log = logs / f"{artifact.name}.notary.log"
        log.write_text(sanitized(process.stdout + "\n" + process.stderr))
        if re.fullmatch(r"[0-9a-fA-F-]{36}", str(result.get("id") or "")):
            detail = subprocess.run(
                [
                    "xcrun",
                    "notarytool",
                    "log",
                    result["id"],
                    "--keychain-profile",
                    profile,
                ],
                capture_output=True,
                text=True,
                timeout=300,
            )
            with log.open("a") as stream:
                stream.write(sanitized(detail.stdout + "\n" + detail.stderr))
        raise ValueError(
            "Notarization was not Accepted; see the sanitized submission log"
        )


def check_app(app, version, build):
    """Require the expected bundle, Developer ID with hardened runtime, and a staple."""
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    expected = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": str(build),
        "LSMinimumSystemVersion": MINIMUM_MACOS,
    }
    actual = {key: info.get(key) for key in expected}
    if actual != expected:
        raise ValueError(f"Bundle metadata mismatch: {actual}")
    if run(["lipo", "-archs", app / f"Contents/MacOS/{APP}"]).split() != ["arm64"]:
        raise ValueError("The app must contain only arm64 code")
    run(["codesign", "--verify", "--deep", "--strict", app])
    details = run(["codesign", "-d", "--verbose=4", app], output="stderr")
    flags = re.search(r"^CodeDirectory .*\bflags=(0x[0-9a-fA-F]+)\b", details, re.M)
    if (
        not re.search(r"^Authority=Developer ID Application:", details, re.M)
        or not re.search(r"^Timestamp=", details, re.M)
        or flags is None
        or not int(flags[1], 16) & HARDENED_RUNTIME
    ):
        raise ValueError(
            "The app needs a timestamped Developer ID signature with hardened runtime"
        )
    entitlements = run(["codesign", "-d", "--entitlements", "-", "--xml", app])
    if "get-task-allow" in entitlements:
        raise ValueError(
            "The app must not carry the get-task-allow debugging entitlement"
        )


def check_privacy(app, root):
    """Reject a bundle that embeds the maintainer's home or checkout path."""
    needles = [str(Path.home()).encode(), str(Path(root).resolve()).encode()]
    for path in app.rglob("*"):
        if path.is_file() and not path.is_symlink():
            data = path.read_bytes()
            if any(needle in data for needle in needles):
                raise ValueError(f"{path.relative_to(app)} embeds a local build path")


def assess(app, dmg):
    run(["xcrun", "stapler", "validate", app])
    run(["spctl", "--assess", "--type", "execute", app])
    run(["codesign", "--verify", "--strict", dmg])
    run(["xcrun", "stapler", "validate", dmg])
    run(
        [
            "spctl",
            "--assess",
            "--type",
            "open",
            "--context",
            "context:primary-signature",
            dmg,
        ]
    )


def export_options(path, identity, team):
    with Path(path).open("wb") as stream:
        plistlib.dump(
            {
                "method": "developer-id",
                "signingStyle": "manual",
                "signingCertificate": identity,
                "teamID": team,
            },
            stream,
        )


def archive_and_export(root, output, identity, team):
    """Build a Release archive signed with Developer ID, then export the app from it."""
    archive = output / f"{APP}.xcarchive"
    run(
        ["xcodebuild", "-project", f"{APP}.xcodeproj", "-scheme", APP]
        + ["-configuration", "Release", "-destination", "generic/platform=macOS"]
        + [
            "-derivedDataPath",
            output / "DerivedData",
            "-archivePath",
            archive,
            "archive",
        ]
        + ["CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={identity}"]
        + [f"DEVELOPMENT_TEAM={team}", "OTHER_CODE_SIGN_FLAGS=--timestamp"]
        + ["SWIFT_TREAT_WARNINGS_AS_ERRORS=YES"],
        cwd=root,
    )
    options = output / "ExportOptions.plist"
    export_options(options, identity, team)
    exported = output / "export"
    run(
        ["xcodebuild", "-exportArchive", "-archivePath", archive]
        + ["-exportOptionsPlist", options, "-exportPath", exported],
        cwd=root,
    )
    return exported / f"{APP}.app"


def make_dmg(app, output, version, identity):
    staging = output / "dmg-root"
    staging.mkdir()
    run(["ditto", app, staging / app.name])
    (staging / "Applications").symlink_to("/Applications")
    dmg = output / f"{APP}-{version}.dmg"
    run(
        ["hdiutil", "create", "-volname", APP, "-srcfolder", staging]
        + ["-ov", "-format", "UDZO", "-fs", "APFS", dmg]
    )
    run(["codesign", "--sign", identity, "--timestamp", dmg])
    return dmg


def package(args):
    """Archive, sign, notarize and staple the app and its DMG, then write a manifest."""
    global LOG_DIRECTORY
    root = args.root.resolve()
    record = preflight(root, args.version)
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(root / "build"):
        raise ValueError(
            "Release output must be a new directory beneath ignored build/"
        )
    identity, team = developer_identity(
        run(["security", "find-identity", "-v", "-p", "codesigning"]), args.identity
    )
    # Fail before a long build when the stored notary credentials are missing or expired.
    run(["xcrun", "notarytool", "history", "--keychain-profile", args.notary_profile])
    output.mkdir(parents=True)
    LOG_DIRECTORY = output / "logs"
    LOG_DIRECTORY.mkdir()
    save(output / "INCOMPLETE.json", record)
    version, build = record["version"], record["build"]
    app = archive_and_export(root, output, identity, team)
    check_app(app, version, build)
    check_privacy(app, root)
    submission = output / f"{APP}-{version}-notarize.zip"
    run(["ditto", "-c", "-k", "--keepParent", app, submission])
    notarize(submission, args.notary_profile, LOG_DIRECTORY)
    run(["xcrun", "stapler", "staple", app])
    dmg = make_dmg(app, output, version, identity)
    notarize(dmg, args.notary_profile, LOG_DIRECTORY)
    run(["xcrun", "stapler", "staple", dmg])
    assess(app, dmg)
    manifest = {
        **record,
        "bundle_id": BUNDLE_ID,
        "minimum_macos": MINIMUM_MACOS,
        "architecture": "arm64",
        "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dmg": {"path": dmg.name, "sha256": digest(dmg), "size": dmg.stat().st_size},
    }
    save(output / "manifest.json", manifest)
    (output / "INCOMPLETE.json").unlink()
    return {"manifest": str(output / "manifest.json"), **manifest["dmg"]}


def detach(mount):
    try:
        run(["hdiutil", "detach", mount])
    except ValueError:
        run(["hdiutil", "detach", "-force", mount])


def verify_manifest(path):
    """Re-check the DMG bytes, its signature and staple, and the app inside it."""
    path = Path(path).resolve(strict=True)
    manifest = json.loads(path.read_text())
    dmg = path.parent / Path(manifest["dmg"]["path"]).name
    if digest(dmg) != manifest["dmg"]["sha256"]:
        raise ValueError("DMG SHA-256 does not match the manifest")
    # A volume that stays mounted after a failed detach must not hide the real error.
    with tempfile.TemporaryDirectory(
        prefix="choscorusage-verify-", ignore_cleanup_errors=True
    ) as mount:
        run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg])
        try:
            app = Path(mount) / f"{APP}.app"
            check_app(app, manifest["version"], manifest["build"])
            assess(app, dmg)
            if os.readlink(Path(mount) / "Applications") != "/Applications":
                raise ValueError("The DMG needs an Applications shortcut")
        except BaseException:
            with contextlib.suppress(ValueError):
                detach(mount)
            raise
        detach(mount)
    return {"verified": manifest["dmg"]["path"], "sha256": manifest["dmg"]["sha256"]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["preflight", "bump", "changes", "package"]:
        command = sub.add_parser(name)
        command.add_argument("--root", type=Path, default=ROOT)
    sub.choices["preflight"].add_argument("--version")
    sub.choices["bump"].add_argument("--version", required=True)
    sub.choices["changes"].add_argument(
        "--since", help="tag to compare; default latest vX.Y.Z"
    )
    sub.choices["changes"].add_argument("--output", type=Path, required=True)
    pack = sub.choices["package"]
    pack.add_argument("--version")
    pack.add_argument("--output", type=Path, required=True)
    pack.add_argument(
        "--identity", default=os.environ.get("CHOSCORUSAGE_SIGNING_IDENTITY")
    )
    pack.add_argument(
        "--notary-profile",
        default=os.environ.get("CHOSCORUSAGE_NOTARY_PROFILE", NOTARY_PROFILE),
    )
    sub.add_parser("verify").add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "preflight":
            result = preflight(args.root, args.version)
        elif args.command == "bump":
            result = bump(args.root, args.version)
        elif args.command == "changes":
            result = changes(args.root, args.since, args.output)
        elif args.command == "package":
            result = package(args)
        else:
            result = verify_manifest(args.manifest)
        print(json.dumps(result, indent=2))
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"Release rejected: {sanitized(str(error))}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
