#!/usr/bin/env python3
"""Probe backend health and rejection behavior without credentials or paid inference."""
import argparse
import json
import plistlib
import subprocess
import sys
import urllib.parse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
args = parser.parse_args()


def request(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    command = ["curl", "--silent", "--show-error", "--max-time", "15", "--max-filesize", "8192",
               "--proto", "=https", "--write-out", "\n%{http_code}", base + path]
    if data is not None:
        command.extend(["--header", "Content-Type: application/json", "--data-binary", "@-"])
    result = subprocess.run(command, input=data, capture_output=True, check=True, timeout=20)
    body, status = result.stdout.rsplit(b"\n", 1)
    try:
        return int(status), json.loads(body)
    except ValueError:
        raise ValueError(f"Backend returned a non-JSON response (HTTP {int(status)})") from None


try:
    info = plistlib.loads((args.app / "Info.plist").read_bytes())
    base = info.get("APIBaseURL", "").rstrip("/")
    url = urllib.parse.urlsplit(base)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError("The built app needs a valid HTTPS APIBaseURL")
    status, body = request("/health")
    if status != 200 or body.get("status") != "ok":
        raise ValueError(f"Health check failed (HTTP {status})")
    print("Backend health: HTTP 200")
    status, body = request("/v1/auth/apple", {
        "identityToken": "invalid-developer-check-token",
        "authorizationCode": "invalid-developer-check-code",
        "nonce": "a" * 64,
    })
    if status != 401 or body.get("error", {}).get("code") != "invalid_apple_credential":
        raise ValueError(f"Invalid-credential rejection check failed (HTTP {status})")
    print("Invalid Apple credentials: correctly rejected with HTTP 401")
    print("No credentials or questions were sent. This does not exercise a successful user login.")
except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
    print(f"Authentication check failed: {error}", file=sys.stderr)
    sys.exit(1)
