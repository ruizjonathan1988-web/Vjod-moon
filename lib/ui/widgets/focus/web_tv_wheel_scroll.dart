import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../util/platform_detection.dart';

/// On a TV's web browser, scrolls [controller] with the wheel turns the page
/// sends when the box's cursor is pushed against an edge, for lists that
/// only follow the remote's highlight and so let wheel turns go by.
///
/// It only takes a turn nothing below it took, so a list that scrolls on
/// its own still scrolls once. Elsewhere it is just [child].
class WebTvWheelScroll extends StatelessWidget {
  final ScrollController controller;
  final Axis axis;
  final Widget child;

  const WebTvWheelScroll({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
  });

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is! PointerScrollEvent || !controller.hasClients) return;
      final delta = axis == Axis.vertical
          ? event.scrollDelta.dy
          : (event.scrollDelta.dx != 0
                ? event.scrollDelta.dx
                : event.scrollDelta.dy);
      if (delta == 0) return;
      final position = controller.position;
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target == position.pixels) return;
      controller.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!(PlatformDetection.isWeb && PlatformDetection.isTV)) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _onSignal,
      child: child,
    );
  }
}
