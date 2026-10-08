#!/usr/bin/env python3
"""Regenerate the app icon set from design/app-icon.svg.

Xcode compiles the icon from the asset catalog on every build, CI included, so the
rendered PNGs are checked in. Run this after editing the SVG and commit both.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "design/app-icon.svg"
ICON_SET = ROOT / "ChoscorUsage/Assets.xcassets/AppIcon.appiconset"
RENDERER = Path(__file__).resolve().with_name("render_svg.swift")
SIZES = (16, 32, 128, 256, 512)


def filename(size, scale):
    return f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"


def contents():
    """Return the asset catalog Contents.json for every macOS icon size."""
    return {
        "images": [
            {
                "filename": filename(size, scale),
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{size}x{size}",
            }
            for size in SIZES
            for scale in (1, 2)
        ],
        "info": {"author": "xcode", "version": 1},
    }


def render(source, icon_set):
    """Render every size with AppKit and write the matching Contents.json."""
    icon_set = Path(icon_set)
    icon_set.mkdir(parents=True, exist_ok=True)
    targets = [
        f"{icon_set / filename(size, scale)}:{size * scale}"
        for size in SIZES
        for scale in (1, 2)
    ]
    subprocess.run(["swift", str(RENDERER), str(source), *targets], check=True)
    (icon_set / "Contents.json").write_text(json.dumps(contents(), indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=ICON_SET)
    args = parser.parse_args()
    try:
        render(args.source, args.output)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Icon generation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
