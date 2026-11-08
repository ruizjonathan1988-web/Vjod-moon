"""Prints VJOD's current version (first line) and its changes (« - » lines),
read from lib/util/vjod_changes.dart, for the GitHub release (perso-apk.yml).
With --since X (the version everyone has, perso-latest), the changes of every
version after X are listed too, newest first: validating 5.0 over 4.12 tells
the household everything that came since."""
import re
import sys


def key(v):
    return tuple(int(p) if p.isdigit() else 0 for p in v.split('.'))


src = open('lib/util/vjod_changes.dart', encoding='utf-8').read()
releases = [(m.group(1), m.group(2)) for m in re.finditer(r"VjodRelease\('([0-9.]+)',\s*\[(.*?)\]\),", src, re.S)]
if not releases:
    sys.exit('no VjodRelease found')
since = None
if '--since' in sys.argv:
    i = sys.argv.index('--since')
    since = sys.argv[i + 1] if i + 1 < len(sys.argv) else None
    if not since or not re.fullmatch(r'[0-9.]+', since):
        since = None


def changes(body):
    return [s.replace("\\'", "'").replace('\\u2019', '’') for s in re.findall(r"'((?:[^'\\]|\\.)*)'", body)]


version = releases[0][0]
print(version)
for v, body in releases:
    if v != version and (since is None or key(v) <= key(since)):
        continue
    for c in changes(body):
        print('- ' + (c if v == version else '%s · %s' % (v, c)))
