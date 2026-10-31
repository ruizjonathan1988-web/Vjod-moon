"""Prepares the checkout for the Samsung (Tizen) build only, in CI:
puts the real Samsung player in place of its stand-in and adds the plugins'
Samsung implementations to pubspec.yaml. Never committed: the other builds
keep the stand-in and their usual dependencies."""
import re
import shutil

shutil.copy('tizen/dart/tizen_backend_hook.dart', 'lib/playback/tizen_backend_hook.dart')

extra = [
    'video_player: ^2.9.2',
    'video_player_tizen: any',
    'path_provider_tizen: any',
    'shared_preferences_tizen: any',
    'connectivity_plus_tizen: any',
    'device_info_plus_tizen: any',
    'package_info_plus_tizen: any',
    'url_launcher_tizen: any',
    'wakelock_plus_tizen: any',
    'flutter_secure_storage_tizen: any',
]
src = open('pubspec.yaml', encoding='utf-8').read()
m = re.search(r'^dependencies:\n', src, re.M)
if not m:
    raise SystemExit('no dependencies section')
block = ''.join(f'  {line}\n' for line in extra)
src = src[:m.end()] + block + src[m.end():]
open('pubspec.yaml', 'w', encoding='utf-8').write(src)
print('Samsung: player and plugins ready')
