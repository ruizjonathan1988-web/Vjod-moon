// « Caster » in the IPTV films and episodes player, on a phone: pick a
// Chromecast, and the film plays there (see iptv_cast.dart for what is sent).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/cast/cast_target.dart';
import '../../../data/services/cast/native_cast_channel.dart';
import '../../../data/services/vjod/iptv_cast.dart';
import '../../../util/platform_detection.dart';

/// Phones only (the Google Cast sender exists on Android and iOS phones);
/// the TV and the web never show the button.
bool get iptvCastAvailable =>
    PlatformDetection.isMobile && GetIt.instance.isRegistered<NativeCastChannel>();

/// Opens the device list and casts [playUrl] from [position]. [onStarted]
/// runs once the Chromecast has it (the player pauses there).
Future<void> showIptvCastSheet(
  BuildContext context, {
  required String playUrl,
  required String title,
  required Duration position,
  VoidCallback? onStarted,
}) async {
  final cast = GetIt.instance<NativeCastChannel>();
  final target = await showModalBottomSheet<CastTarget>(
    context: context,
    builder: (_) => _DevicePicker(cast: cast),
  );
  if (target == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(content: Text('Préparation pour ${target.title}…')));
  final source = await resolveIptvCast(playUrl);
  if (!source.ok) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(source.problem ?? iptvCastMaTvFailed)));
    return;
  }
  try {
    await cast.startGoogleCastSession(
      targetId: target.id,
      streamUrl: source.url,
      contentType: source.contentType,
      title: title,
      startPositionTicks: position.inMicroseconds * 10,
    );
  } catch (_) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text('La Chromecast « ${target.title} » ne répond pas.')));
    return;
  }
  messenger?.hideCurrentSnackBar();
  onStarted?.call();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => _CastControls(cast: cast, device: target.title, title: title),
  );
}

class _DevicePicker extends StatefulWidget {
  const _DevicePicker({required this.cast});
  final NativeCastChannel cast;

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  final _found = <String, CastTarget>{};
  StreamSubscription<Map<String, dynamic>>? _events;
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _events = widget.cast.googleCastEventStream().listen((e) {
      if (e['state'] != 'deviceFound') return;
      final id = e['id']?.toString() ?? '';
      if (id.isEmpty || !mounted) return;
      setState(() => _found[id] = CastTarget(
        id: id,
        kind: CastTargetKind.googleCast,
        title: e['title']?.toString() ?? 'Chromecast',
        subtitle: e['subtitle']?.toString() ?? '',
      ));
    });
    unawaited(widget.cast.startGoogleCastDiscovery().catchError((_) {}));
    unawaited(widget.cast.discoverGoogleCastTargets().then((list) {
      if (!mounted) return;
      setState(() {
        for (final t in list) {
          _found[t.id] = t;
        }
      });
    }).catchError((_) {}));
    Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _searching = false);
    });
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(widget.cast.stopGoogleCastDiscovery().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        const ListTile(
          leading: Icon(Icons.cast_rounded),
          title: Text('Caster sur'),
          subtitle: Text('Le téléphone et la Chromecast doivent être sur le même Wi-Fi.'),
        ),
        for (final t in _found.values)
          ListTile(
            leading: const Icon(Icons.tv_rounded),
            title: Text(t.title),
            subtitle: t.subtitle.isEmpty ? null : Text(t.subtitle),
            onTap: () => Navigator.of(context).pop(t),
          ),
        if (_found.isEmpty)
          ListTile(
            leading: _searching
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_off_rounded),
            title: Text(_searching ? 'Recherche des Chromecast…' : 'Aucune Chromecast trouvée'),
          ),
      ],
    ),
  );
}

class _CastControls extends StatefulWidget {
  const _CastControls({required this.cast, required this.device, required this.title});
  final NativeCastChannel cast;
  final String device;
  final String title;

  @override
  State<_CastControls> createState() => _CastControlsState();
}

class _CastControlsState extends State<_CastControls> {
  bool _paused = false;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.cast_connected_rounded),
          title: Text('Lecture sur ${widget.device}'),
          subtitle: Text(widget.title),
        ),
        ListTile(
          leading: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          title: Text(_paused ? 'Reprendre' : 'Pause'),
          onTap: () {
            unawaited((_paused ? widget.cast.playGoogleCast() : widget.cast.pauseGoogleCast())
                .catchError((_) {}));
            setState(() => _paused = !_paused);
          },
        ),
        ListTile(
          leading: const Icon(Icons.stop_rounded),
          title: const Text('Arrêter le cast'),
          onTap: () {
            unawaited(widget.cast.stopGoogleCastSession().catchError((_) {}));
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}
