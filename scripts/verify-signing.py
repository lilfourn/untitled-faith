#!/usr/bin/env python3
"""Check the installed/build artifact, not a potentially stale .xcent source file."""
import argparse
import json
import plistlib
import subprocess
import struct
import sys
from pathlib import Path

parser = argparse.ArgumentParser(description="Verify Apple sign-in and default Keychain identity on an app bundle.")
parser.add_argument("app", type=Path)
args = parser.parse_args()


def simulated_entitlements(binary: Path) -> dict:
    """Simulator entitlements live in Mach-O __TEXT, not the code-signature plist."""
    data = binary.read_bytes()
    base = 0
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        is_fat64 = data[:4] == b"\xca\xfe\xba\xbf"
        count = struct.unpack_from(">I", data, 4)[0]
        for index in range(count):
            position = 8 + index * (32 if is_fat64 else 20)
            cpu = struct.unpack_from(">I", data, position)[0]
            offset = struct.unpack_from(">Q" if is_fat64 else ">I", data, position + 8)[0]
            if index == 0 or cpu == 0x0100000C:
                base = offset
            if cpu == 0x0100000C:
                break
    if data[base:base + 4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Unsupported simulator executable format")
    commands = struct.unpack_from("<I", data, base + 16)[0]
    position = base + 32
    for _ in range(commands):
        command, length = struct.unpack_from("<II", data, position)
        if command == 0x19:  # LC_SEGMENT_64
            sections = struct.unpack_from("<I", data, position + 64)[0]
            for index in range(sections):
                section = position + 72 + index * 80
                name = data[section:section + 16].rstrip(b"\0")
                if name == b"__entitlements":
                    size = struct.unpack_from("<Q", data, section + 40)[0]
                    offset = struct.unpack_from("<I", data, section + 48)[0]
                    return plistlib.loads(data[base + offset:base + offset + size].rstrip(b"\0"))
        if length < 8:
            break
        position += length
    raise ValueError("Simulator entitlement section is missing")


try:
    info = plistlib.loads((args.app / "Info.plist").read_bytes())
    subprocess.run(["codesign", "--verify", "--strict", str(args.app)], capture_output=True, check=True)
    result = subprocess.run(
        ["codesign", "--display", "--entitlements", "-", "--xml", str(args.app)],
        capture_output=True, check=True,
    )
    entitlements = plistlib.loads(result.stdout)
    if info.get("DTPlatformName") == "iphonesimulator":
        entitlements = simulated_entitlements(args.app / info["CFBundleExecutable"])
    identifier = entitlements.get("application-identifier", "")
    team = entitlements.get("com.apple.developer.team-identifier", "")
    bundle = info["CFBundleIdentifier"]
    if not team and info.get("DTPlatformName") == "iphonesimulator":
        # Xcode embeds the team in the simulated app identifier, without a separate team entitlement.
        team = identifier.split(".", 1)[0]
    if entitlements.get("com.apple.developer.applesignin") != ["Default"]:
        raise ValueError("Sign in with Apple entitlement is missing")
    if not team or identifier != f"{team}.{bundle}":
        raise ValueError("App identity required by Apple authorization and Keychain is missing or mismatched")
    print(json.dumps({"bundleID": bundle, "teamID": team, "appleSignIn": True, "keychainIdentity": True}))
except (OSError, KeyError, ValueError, struct.error, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
    print(f"Signing check failed: {error}. Rebuild with signing enabled; do not install this artifact.", file=sys.stderr)
    sys.exit(1)
