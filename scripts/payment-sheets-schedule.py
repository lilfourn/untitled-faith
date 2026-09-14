#!/usr/bin/env python3
"""Install only the weekly Untitled Faith accounting job after a verified sync."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / '.dev' / 'google-accounting'
LABEL = 'com.lukefournier.untitled-faith-accounting'
PLIST = Path.home() / 'Library' / 'LaunchAgents' / f'{LABEL}.plist'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', help='Install Monday 9 AM local-time updates')
    parser.add_argument('--status', action='store_true')
    args = parser.parse_args()
    target = f'gui/{os.getuid()}/{LABEL}'
    if args.status:
        result = subprocess.run(['launchctl', 'print', target], capture_output=True, text=True)
        print(result.stdout if result.returncode == 0 else 'Weekly accounting job is not installed.')
        return
    if not args.install:
        parser.print_help()
        return
    config = json.loads((STATE / 'sheet.json').read_text())
    receipt = json.loads((STATE / 'last-sync.json').read_text())
    if receipt.get('spreadsheetID') != config.get('spreadsheetID') or not receipt.get('syncedAt'):
        raise RuntimeError('A verified Google Sheets sync is required before scheduling.')
    node = shutil.which('node')
    if not node or not shutil.which('gws') or not shutil.which('stripe'):
        raise RuntimeError('Node, Google Workspace CLI, and Stripe CLI must be installed.')
    content = {
        'Label': LABEL,
        'ProgramArguments': [node, str(ROOT / 'backend/scripts/payment-sheets-sync.mjs'), '--scheduled'],
        'WorkingDirectory': str(ROOT),
        'EnvironmentVariables': {'PATH': os.environ['PATH'], 'HOME': str(Path.home())},
        'StartCalendarInterval': {'Weekday': 1, 'Hour': 9, 'Minute': 0},
        'RunAtLoad': True,
        'ProcessType': 'Background',
        'StandardOutPath': str(STATE / 'weekly.log'),
        'StandardErrorPath': str(STATE / 'weekly-errors.log'),
    }
    for name in ['weekly.log', 'weekly-errors.log']:
        (STATE / name).touch(mode=0o600, exist_ok=True)
        (STATE / name).chmod(0o600)
    encoded = plistlib.dumps(content, sort_keys=False)
    if PLIST.exists() and PLIST.read_bytes() != encoded:
        raise RuntimeError('An existing accounting schedule differs. Review it before replacing it.')
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    PLIST.write_bytes(encoded)
    PLIST.chmod(0o600)
    subprocess.run(['plutil', '-lint', str(PLIST)], check=True)
    exists = subprocess.run(['launchctl', 'print', target], capture_output=True).returncode == 0
    if not exists:
        subprocess.run(['launchctl', 'bootstrap', f'gui/{os.getuid()}', str(PLIST)], check=True)
    print('Weekly accounting updates installed: Mondays at 9 AM local time, with wake/login catch-up.')


if __name__ == '__main__':
    main()
