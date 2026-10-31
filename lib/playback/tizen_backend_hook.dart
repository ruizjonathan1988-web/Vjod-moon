// Samsung TVs (Tizen) play video through the TV's own player, reached with
// the video_player plugin. That plugin is only added to the Samsung build:
// this file is the stand-in every other build compiles, and the Samsung
// workflow (samsung-essai.yml) puts tizen/dart/tizen_backend_hook.dart in
// its place. So Android, the web and the rest never carry video_player.
import 'package:flutter/widgets.dart';
import 'package:playback_core/playback_core.dart';

import '../preference/user_preferences.dart';

/// The Samsung player, or null outside the Samsung build.
PlayerBackend? createTizenBackend(UserPreferences prefs) => null;

/// The picture of [backend] when it is the Samsung player, else null.
Widget? tizenVideoView(PlayerBackend? backend) => null;
