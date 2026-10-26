import 'web_tv_detect_stub.dart'
    if (dart.library.js_interop) 'web_tv_detect_web.dart' as impl;

/// Whether the web app runs in a TV's own browser (Samsung, LG, Sony,
/// Hisense, Fire TV...), so it can use the remote-friendly TV layout. A
/// computer's browser is never treated as a TV.
///
/// `?tv=1` in the address forces the TV layout on a TV whose browser hides
/// what it is, and `?tv=0` turns it off; the choice is remembered.
bool isWebTvBrowser() => impl.isWebTvBrowser();

/// The diagnostic panel of the web app on a TV, on with `?tvdebug=1`.
bool webTvDebugEnabled() => impl.webTvDebugEnabled();
