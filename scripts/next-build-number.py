#!/usr/bin/env python3
"""Reserve a local build number. Caller must hold scripts/dev's iOS lock."""
import argparse
import plistlib
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("root", type=Path)
parser.add_argument("state", type=Path)
parser.add_argument("number", nargs="?")
args = parser.parse_args()


def build_number(value: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]{0,3}", value):
        parser.error(f"Expected an integer build number from 1 to 9999, got {value!r}")
    return int(value)


counter = args.state / "last-build-number"
latest = build_number(counter.read_text().strip()) if counter.exists() else 0
for archive in (args.root / "DerivedData/Archives").glob("*.xcarchive"):
    info_path = archive / "Products/Applications/Untitled Faith.app/Info.plist"
    if not info_path.exists():
        continue  # Incomplete archive; any reserved number remains in the counter.
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleIdentifier") == "com.lukefournier.UntitledFaith":
        latest = max(latest, build_number(info["CFBundleVersion"]))

number = build_number(args.number) if args.number else latest + 1
if number <= latest or number > 9999:
    parser.error(f"Build must be greater than {latest} and at most 9999")
args.state.mkdir(parents=True, exist_ok=True)
temporary = counter.with_suffix(".tmp")
temporary.write_text(f"{number}\n")
temporary.replace(counter)
print(number)
