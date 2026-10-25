#!/usr/bin/env python3
"""Package the existing logo as app icons using macOS sips (no dependencies)."""

import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


APP = Path(__file__).resolve().parents[1]
SOURCE = APP / "assets/images/branding/logo.png"


def run_sips(*args):
    return subprocess.run(
        ["sips", *map(str, args)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def icon_targets():
    icons = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    entries = json.loads((icons / "Contents.json").read_text())["images"]
    targets = {}
    for entry in entries:
        side = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].removesuffix("x"))
        targets[icons / entry["filename"]] = (round(side * scale), 0.9)

    resources = APP / "android/app/src/main/res"
    for density, side in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        targets[resources / f"mipmap-{density}/ic_launcher.png"] = (side, 0.9)

    for side in (192, 512):
        targets[APP / f"web/icons/Icon-{side}.png"] = (side, 0.9)
        targets[APP / f"web/icons/Icon-maskable-{side}.png"] = (side, 0.78)
    targets[APP / "web/favicon.png"] = (32, 0.9)
    return targets


def validate(path, side):
    header = path.read_bytes()[:26]
    if (header[:8] != b"\x89PNG\r\n\x1a\n" or
            struct.unpack(">II", header[16:24]) != (side, side)):
        raise ValueError(f"Invalid icon dimensions: {path.name}")
    if "hasAlpha: no" not in run_sips("-g", "hasAlpha", path):
        raise ValueError(f"App icon must be opaque: {path.name}")


def main():
    if shutil.which("sips") is None:
        raise SystemExit("This generator requires macOS's built-in sips tool.")
    if not SOURCE.is_file():
        raise SystemExit(f"Missing logo: {SOURCE}")
    build = APP / "build"
    build.mkdir(exist_ok=True)
    targets = icon_targets()
    with tempfile.TemporaryDirectory(prefix="app-icons-", dir=build) as temp:
        staging = Path(temp)
        rendered = {}
        # Validate every generated image before replacing platform assets.
        for side, fraction in set(targets.values()):
            output = staging / f"{side}-{fraction}.png"
            run_sips("-Z", round(side * fraction), SOURCE, "--out", output)
            run_sips("-p", side, side, "--padColor", "FFFFFF",
                     output, "--out", output)
            validate(output, side)
            rendered[(side, fraction)] = output
        for target, settings in targets.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(rendered[settings], target)
    print(f"Updated {len(targets)} iOS, Android and web icons from {SOURCE.name}.")


if __name__ == "__main__":
    main()
