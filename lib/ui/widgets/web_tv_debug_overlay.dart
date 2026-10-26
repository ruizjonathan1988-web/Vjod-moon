import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/platform_detection.dart';

/// A small panel in the corner of the web app, shown only with `?tvdebug=1`
/// in the address: what has the focus, the last key the app received and
/// the last wheel turn, so a TV browser that won't move can be read from a
/// photo of the screen.
class WebTvDebugOverlay extends StatefulWidget {
  const WebTvDebugOverlay({super.key});

  static bool get enabled =>
      PlatformDetection.isWeb && Uri.base.queryParameters['tvdebug'] == '1';

  @override
  State<WebTvDebugOverlay> createState() => _WebTvDebugOverlayState();
}

class _WebTvDebugOverlayState extends State<WebTvDebugOverlay> {
  String _key = '-';
  String _wheel = '-';
  String _focus = '-';
  int _keys = 0;
  int _wheels = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final node = FocusManager.instance.primaryFocus;
      final label = node == null
          ? 'aucun'
          : '${node.debugLabel ?? '?'} · ${node.context?.widget.runtimeType}';
      if (label != _focus && mounted) setState(() => _focus = label);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && mounted) {
      setState(() {
        _keys++;
        _key = event.logicalKey.keyLabel;
      });
    }
    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerScrollEvent && mounted) {
      setState(() {
        _wheels++;
        _wheel =
            '${event.scrollDelta.dx.round()},${event.scrollDelta.dy.round()}'
            ' @${event.position.dx.round()},${event.position.dy.round()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      top: 12,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(10),
          color: const Color(0xE6000000),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFF7FD6A8),
              fontSize: 15,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TV ${PlatformDetection.isTV}'),
                Text('Touches $_keys · $_key'),
                Text('Molette $_wheels · $_wheel'),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text('Focus $_focus'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
