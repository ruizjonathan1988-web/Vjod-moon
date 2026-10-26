import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Makes `window.vjodTvKey('down')` press that key in the app.
void exposeWebTvRemote(String Function(String name) press) {
  globalContext.setProperty(
    'vjodTvKey'.toJS,
    ((JSString name) => press(name.toDart).toJS).toJS,
  );
}
