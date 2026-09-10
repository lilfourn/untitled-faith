#!/usr/bin/env python3
"""Resolve an existing iOS simulator; never erase, clone, or shut down a device."""
import argparse
import json
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("selector", nargs="?", default="iPhone 17", help="Existing simulator name or UDID")
parser.add_argument("--state", action="store_true")
args = parser.parse_args()

result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True, check=True)
devices = []
for runtime, entries in json.loads(result.stdout)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(map(int, re.findall(r"\d+", runtime.split(".iOS-", 1)[1])))
    for device in entries:
        if device.get("isAvailable"):
            devices.append((version, device))
matches = [(version, device) for version, device in devices if args.selector in (device["name"], device["udid"])]
if not matches:
    print(f"No available iOS simulator matches {args.selector!r}. Use FAITH_SIMULATOR with an existing name or UDID.", file=sys.stderr)
    sys.exit(1)
matches.sort(key=lambda entry: (entry[1]["state"] == "Booted", entry[0]), reverse=True)
selected = matches[0][1]
print(selected["state"] if args.state else selected["udid"])
