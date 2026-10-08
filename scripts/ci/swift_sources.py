"""First-party Swift source scope shared by the repository's Swift policy gates."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "Packages/ChoscorUsageKit"
SWIFT_ROOTS = ("ChoscorUsage", f"{PACKAGE}/Sources", f"{PACKAGE}/Tests")


def swift_files(root=ROOT):
    """Return first-party Swift sources relative to ``root`` in a deterministic order."""
    files = []
    for scope in SWIFT_ROOTS:
        directory = Path(root) / scope
        if directory.is_dir():
            files.extend(
                path.relative_to(root)
                for path in directory.rglob("*.swift")
                if ".build" not in path.parts
            )
    return sorted(files)
