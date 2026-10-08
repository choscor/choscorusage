"""Tests for the app icon set generated from design/app-icon.svg."""

import json
from pathlib import Path
import struct
import unittest

import render_icon

ICON_SET = render_icon.ROOT / "ChoscorUsage/Assets.xcassets/AppIcon.appiconset"


def png_size(path):
    header = Path(path).read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", header[16:24])


class ContentsTest(unittest.TestCase):
    def test_lists_every_macos_size_at_1x_and_2x(self):
        images = render_icon.contents()["images"]
        self.assertEqual(
            {(image["size"], image["scale"]) for image in images},
            {
                (f"{size}x{size}", scale)
                for size in (16, 32, 128, 256, 512)
                for scale in ("1x", "2x")
            },
        )
        self.assertTrue(all(image["idiom"] == "mac" for image in images))
        self.assertEqual(len({image["filename"] for image in images}), 10)


class CheckedInIconSetTest(unittest.TestCase):
    def test_matches_the_generated_contents_and_each_png_has_its_pixel_size(self):
        contents = json.loads((ICON_SET / "Contents.json").read_text())
        self.assertEqual(contents, render_icon.contents())
        for image in contents["images"]:
            points = int(image["size"].split("x")[0])
            pixels = points * int(image["scale"][0])
            with self.subTest(image=image["filename"]):
                self.assertEqual(
                    png_size(ICON_SET / image["filename"]), (pixels, pixels)
                )

    def test_the_app_target_uses_the_icon_set(self):
        project = (
            render_icon.ROOT / "ChoscorUsage.xcodeproj/project.pbxproj"
        ).read_text()
        self.assertEqual(
            project.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"), 2
        )


if __name__ == "__main__":
    unittest.main()
