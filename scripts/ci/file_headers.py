#!/usr/bin/env python3
"""Require every first-party Swift file to open with a one- or two-line purpose comment."""

from pathlib import Path
import re
import sys

from swift_sources import ROOT, swift_files

MAX_HEADER_LINES = 2
BARE_FILENAME = re.compile(r"^[\w+.-]+\.swift$")


def header_finding(name, source):
    """Return why ``source`` lacks a valid purpose header, or None when it has one."""
    header = []
    for line in source.splitlines():
        if not line.startswith("//") or line.startswith("///"):
            break
        header.append(line[2:].strip())
    if not header:
        return f"{name}:1: start the file with a `//` purpose comment"
    if len(header) > MAX_HEADER_LINES:
        return f"{name}:1: keep the purpose comment to one or two lines"
    text = " ".join(header).strip()
    if not text or BARE_FILENAME.match(text):
        return f"{name}:1: the purpose comment must say what the file owns, not repeat its name"
    return None


def main(argv=None):
    paths = [Path(arg) for arg in argv] if argv else [ROOT / p for p in swift_files()]
    findings = [
        finding
        for path in paths
        if (finding := header_finding(str(path), path.read_text(encoding="utf-8")))
    ]
    for finding in findings:
        print(finding, file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
