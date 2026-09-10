#!/usr/bin/env python3
"""Advance the visible release version in project.yml under scripts/dev's iOS lock."""
import argparse
import plistlib
import re
from pathlib import Path


VERSION_SETTING = re.compile(r'^(\s*MARKETING_VERSION: )"([0-9.]+)"$', re.MULTILINE)
BUILD_SETTING = re.compile(r'^(\s*CURRENT_PROJECT_VERSION: )"[0-9]+"$', re.MULTILINE)


def version_parts(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", value):
        raise ValueError(f"Invalid release version: {value!r}")
    parts = tuple(map(int, value.split(".")))
    return parts if len(parts) == 3 else (*parts, 0)


def advance(root: Path, size: str, build: str) -> str:
    if size not in ("minor", "big"):
        raise ValueError("Release size must be minor or big")
    if not re.fullmatch(r"[1-9][0-9]{0,3}", build):
        raise ValueError("Build must be an integer from 1 to 9999")
    project = root / "project.yml"
    original = project.read_text()
    matches = list(VERSION_SETTING.finditer(original))
    if len(matches) != 1 or len(BUILD_SETTING.findall(original)) != 1:
        raise ValueError("Expected one quoted MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml")
    latest = version_parts(matches[0][2])
    for archive in (root / "DerivedData/Archives").glob("*.xcarchive"):
        info_path = archive / "Products/Applications/Untitled Faith.app/Info.plist"
        if not info_path.exists():
            continue
        with info_path.open("rb") as source:
            info = plistlib.load(source)
        if info.get("CFBundleIdentifier") == "com.lukefournier.UntitledFaith":
            latest = max(latest, version_parts(info["CFBundleShortVersionString"]))
    major, minor, patch = latest
    next_version = f"{major}.{minor + 1}.0" if size == "big" else f"{major}.{minor}.{patch + 1}"
    updated = VERSION_SETTING.sub(lambda match: f'{match[1]}"{next_version}"', original)
    updated = BUILD_SETTING.sub(lambda match: f'{match[1]}"{build}"', updated)
    # Refuse to overwrite edits made since the read, even within a shared checkout.
    if project.read_text() != original:
        raise RuntimeError("project.yml changed while reserving a version; retry")
    temporary = project.with_suffix(".yml.tmp")
    temporary.write_text(updated)
    temporary.replace(project)
    return next_version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("size", choices=("minor", "big"))
    parser.add_argument("build")
    args = parser.parse_args()
    try:
        print(advance(args.root, args.size, args.build))
    except (ValueError, RuntimeError, OSError) as error:
        parser.exit(1, f"{error}\n")
