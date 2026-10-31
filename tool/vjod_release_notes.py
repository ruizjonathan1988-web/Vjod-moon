"""Prints VJOD's current version (first line) and its changes (« - » lines),
read from lib/util/vjod_changes.dart, for the GitHub release (perso-apk.yml)."""
import re
import sys

src = open('lib/util/vjod_changes.dart', encoding='utf-8').read()
m = re.search(r"VjodRelease\('([0-9.]+)',\s*\[(.*?)\]\),", src, re.S)
if not m:
    sys.exit('no VjodRelease found')
version, body = m.group(1), m.group(2)
changes = [
    s.replace("\\'", "'").replace('\\u2019', '’')
    for s in re.findall(r"'((?:[^'\\]|\\.)*)'", body)
]
print(version)
for c in changes:
    print('- ' + c)
