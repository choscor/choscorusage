#!/usr/bin/env python3
"""Reject first-party Swift that passes token-bearing values into log or print output."""

from pathlib import Path
import re
import sys

from swift_sources import ROOT, swift_files

SENSITIVE = re.compile(
    r"accessToken|access_token|refreshToken|Authorization|\btoken\b|[Bb]earer|"
    r"\bheaders\b|accountI[Dd]|\.body\b"
)
LOG_CALL = re.compile(
    r"\b(?:print|NSLog|os_log)\(|"
    r"\b\w*[lL]ogger\.(?:trace|debug|info|notice|warning|error|critical|fault|log)\("
)


def call_text(source, open_paren):
    """Return the argument text of the call whose `(` is at ``open_paren``."""
    depth = 0
    for index in range(open_paren, len(source)):
        if source[index] == "(":
            depth += 1
        elif source[index] == ")":
            depth -= 1
            if depth == 0:
                return source[open_paren : index + 1]
    return source[open_paren:]


def findings(name, source):
    """Return one finding per logging call whose arguments mention a token identifier."""
    results = []
    for match in LOG_CALL.finditer(source):
        arguments = call_text(source, match.end() - 1)
        if SENSITIVE.search(arguments):
            line = source.count("\n", 0, match.start()) + 1
            results.append(
                f"{name}:{line}: token-bearing value passed to {match.group(0)[:-1]}"
            )
    return results


def main(argv=None):
    paths = [Path(arg) for arg in argv] if argv else [ROOT / p for p in swift_files()]
    problems = []
    for path in paths:
        problems.extend(findings(str(path), path.read_text(encoding="utf-8")))
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
