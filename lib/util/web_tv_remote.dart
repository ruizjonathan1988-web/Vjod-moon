import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'web_tv_remote_stub.dart'
    if (dart.library.js_interop) 'web_tv_remote_web.dart'
    as impl;

/// Lets the page's script press the remote's arrows, OK and Back inside the
/// app, for TV browsers that turn the remote into a mouse cursor. The keys
/// go straight to the focus, the way the TV app's remote does, so every
/// screen moves exactly as it does there.
void installWebTvRemote() => impl.exposeWebTvRemote(
  (name) => '${pressRemoteKey(name) ? 1 : 0}:${describeFocus()}',
);

/// What has the focus, for the page's diagnostic panel: the node's label,
/// its widget, and the widgets just above it.
String describeFocus() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'rien';
  final context = node.context;
  final parts = <String>[node.debugLabel ?? '?'];
  if (context != null) {
    parts.add(context.widget.runtimeType.toString());
    var depth = 0;
    context.visitAncestorElements((element) {
      final name = element.widget.runtimeType.toString();
      if (!name.startsWith('_') && name.length < 40) parts.add(name);
      return ++depth < 12;
    });
  }
  return parts.take(7).join(' < ');
}

/// Presses [name] (`up`, `down`, `left`, `right`, `ok`, `back`) on the
/// focused item. True when something in the app acted on it.
bool pressRemoteKey(String name) {
  final keys = switch (name) {
    'up' => (LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp),
    'down' => (LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
    'left' => (LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
    'right' => (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
    'ok' => (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter),
    'back' => (LogicalKeyboardKey.goBack, PhysicalKeyboardKey.escape),
    _ => null,
  };
  if (keys == null) return false;
  final (logical, physical) = keys;
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || focus.context == null) {
    // Nothing has the focus yet: give it to the first thing that can take
    // it, as the remote's first press does on a TV.
    final first = FocusManager.instance.rootScope.traversalDescendants
        .where((n) => n.canRequestFocus && n.context != null)
        .firstOrNull;
    first?.requestFocus();
    return first != null;
  }
  final at = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch);
  final handled = _dispatch(
    focus,
    KeyDownEvent(physicalKey: physical, logicalKey: logical, timeStamp: at),
  );
  _dispatch(
    FocusManager.instance.primaryFocus ?? focus,
    KeyUpEvent(physicalKey: physical, logicalKey: logical, timeStamp: at),
  );
  return handled;
}

/// Hands [event] to [node] and then to each node above it until one takes
/// it, as the focus system does with a key from the remote. The shortcuts
/// that move the focus by arrow sit in that chain too.
bool _dispatch(FocusNode node, KeyEvent event) {
  for (FocusNode? n = node; n != null; n = n.parent) {
    final handler = n.onKeyEvent;
    if (handler == null) continue;
    switch (handler(n, event)) {
      case KeyEventResult.handled:
        return true;
      case KeyEventResult.skipRemainingHandlers:
        return false;
      case KeyEventResult.ignored:
        break;
    }
  }
  return false;
}
