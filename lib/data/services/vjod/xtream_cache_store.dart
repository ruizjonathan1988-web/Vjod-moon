/// Where the IPTV provider's catalogue is kept between launches: a file in
/// the app's support folder, or nowhere in a browser, which has no files and
/// no provider search anyway.
library;

export 'xtream_cache_store_io.dart'
    if (dart.library.js_interop) 'xtream_cache_store_web.dart';
