"""Writes altstore.json, the AltStore « source » of VJOD for the iPad.

Added once in AltStore (Sources → +), it lists VJOD and its latest version:
AltStore then offers each new build as an update, with the changes.

Usage: python3 tool/vjod_altstore_source.py <ipa> <Info.plist> <release tag>
Prints the JSON. Reads the version and changes from lib/util/vjod_changes.dart
through vjod_release_notes.py.
"""
import datetime
import json
import os
import plistlib
import subprocess
import sys

REPO = 'ruizjonathan1988-web/Vjod-moon'


def source(ipa, info_plist, tag, notes):
    info = plistlib.load(open(info_plist, 'rb'))
    lines = notes.strip().splitlines()
    version, changes = lines[0], '\n'.join(lines[1:])
    # AltStore checks that the source declares every permission the app asks.
    privacy = {k: v for k, v in info.items() if k.endswith('UsageDescription')}
    return {
        'name': 'VJOD',
        'identifier': 'org.vjod.source',
        'subtitle': 'VJOD pour iPad',
        'website': f'https://github.com/{REPO}',
        'apps': [{
            'name': 'VJOD',
            'bundleIdentifier': info['CFBundleIdentifier'],
            'developerName': 'VJOD',
            'subtitle': 'Films, séries et TV',
            'localizedDescription': 'VJOD : vos films, séries et la TV en direct.',
            'iconURL': f'https://raw.githubusercontent.com/{REPO}/perso/web/icons/Icon-512.png',
            'tintColor': 'E50914',
            'versions': [{
                'version': info['CFBundleShortVersionString'],
                'buildVersion': info['CFBundleVersion'],
                'date': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                'localizedDescription': f'VJOD {version}\n{changes}',
                'downloadURL': f'https://github.com/{REPO}/releases/download/{tag}/vjod-ipad.ipa',
                'size': os.path.getsize(ipa),
                'minOSVersion': info.get('MinimumOSVersion', '18.0'),
            }],
            'appPermissions': {'entitlements': [], 'privacy': privacy},
        }],
        'news': [],
    }


if __name__ == '__main__':
    ipa, plist, tag = sys.argv[1:4]
    here = os.path.dirname(os.path.abspath(__file__))
    notes = subprocess.run([sys.executable, os.path.join(here, 'vjod_release_notes.py')],
                           capture_output=True, text=True, check=True).stdout
    print(json.dumps(source(ipa, plist, tag, notes), indent=2, ensure_ascii=False))
