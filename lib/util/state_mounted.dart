import 'package:flutter/widgets.dart';

/// Guards `setState` against the « setState() called after dispose() » crash.
///
/// After an `await`, the user may have left the screen, so the [State] is no
/// longer mounted and calling `setState` throws. Use this in any async method
/// in place of a bare `setState`: it updates the screen only if it is still
/// there, and quietly does nothing otherwise. VJOD 5.18.
extension SetStateIfMounted<T extends StatefulWidget> on State<T> {
  void setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    // ignore: invalid_use_of_protected_member
    setState(fn);
  }
}
