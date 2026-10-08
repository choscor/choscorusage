#!/usr/bin/env python3
"""Enforce the per-layer banned-API table from CLAUDE.md on first-party Swift sources."""

from dataclasses import dataclass
from pathlib import Path
import re
import sys

from swift_sources import PACKAGE, ROOT

UI_AND_OS = {"SwiftUI", "AppKit", "UserNotifications", "ServiceManagement"}
UI_AND_OS_NAMES = {
    "NSApplication",
    "NSWorkspace",
    "UNUserNotificationCenter",
    "SMAppService",
}
KEYCHAIN_NAMES = {"SecItemCopyMatching", "SecItemAdd", "SecItemUpdate", "SecItemDelete"}


@dataclass(frozen=True)
class Layer:
    """One source directory with its allowed or banned imports and banned identifiers."""

    directory: str
    banned_names: frozenset
    allowed_imports: frozenset | None = None
    banned_imports: frozenset = frozenset()


LAYERS = (
    Layer(
        f"{PACKAGE}/Sources/ChoscorUsageCore",
        frozenset(
            {"URLSession", "FileManager", "ProcessInfo", "Logger", "os_log"}
            | {"JSONSerialization", "JSONDecoder", "JSONEncoder"}
            | UI_AND_OS_NAMES
            | KEYCHAIN_NAMES
        ),
        allowed_imports=frozenset({"Foundation", "CryptoKit"}),
    ),
    Layer(
        f"{PACKAGE}/Sources/ChoscorUsageProviders",
        frozenset(UI_AND_OS_NAMES),
        banned_imports=frozenset(UI_AND_OS),
    ),
    Layer(
        f"{PACKAGE}/Sources/ChoscorUsageKit",
        frozenset(UI_AND_OS_NAMES | KEYCHAIN_NAMES),
        banned_imports=frozenset(UI_AND_OS | {"Security"}),
    ),
    Layer(
        "ChoscorUsage",
        frozenset(KEYCHAIN_NAMES | {"URLSession", "JSONSerialization"}),
        banned_imports=frozenset(
            {"Security", "ChoscorUsageCore", "ChoscorUsageProviders"}
        ),
    ),
)

IMPORT = re.compile(r"^\s*(?:@\w+\s+)*import\s+(?:\w+\s+)?(\w+)")
CODE_NOISE = re.compile(r'//.*$|"(?:\\.|[^"\\])*"')
IDENTIFIER = re.compile(r"\b[A-Za-z_]\w*\b")


def keep_interpolations(match):
    """Drop a comment or string literal but keep the code inside its `\\( … )` segments."""
    text = match.group(0)
    if text.startswith("//"):
        return ""
    segments = []
    start = text.find("\\(")
    while start != -1:
        depth = 0
        for index in range(start + 1, len(text)):
            depth += {"(": 1, ")": -1}.get(text[index], 0)
            if depth == 0:
                segments.append(text[start + 2 : index])
                break
        start = text.find("\\(", start + 2)
    return " ".join(segments)


def line_findings(layer, label, number, line):
    imported = IMPORT.match(line)
    if imported:
        module = imported.group(1)
        allowed = layer.allowed_imports
        if module in layer.banned_imports or (
            allowed is not None and module not in allowed
        ):
            return [f"{label}:{number}: `import {module}` is not allowed in this layer"]
        return []
    code = CODE_NOISE.sub(keep_interpolations, line)
    banned = sorted(set(IDENTIFIER.findall(code)) & layer.banned_names)
    return [f"{label}:{number}: `{name}` is banned in this layer" for name in banned]


def findings(root=ROOT):
    """Return every banned import or identifier found under ``root``."""
    results = []
    for layer in LAYERS:
        directory = Path(root) / layer.directory
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*.swift")):
            label = path.relative_to(root)
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines, start=1):
                results.extend(line_findings(layer, label, number, line))
    return results


def main():
    problems = findings()
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
