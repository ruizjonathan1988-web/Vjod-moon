// "IPTV" on a poster: a title the library doesn't have but the provider
// does (through Ma TV, several providers at once). The tag shows on the
// poster and a press plays it, a film at once, a series on its episodes,
// without going through its page.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/provider_catalog_access.dart';
import '../../../data/services/vjod/xtream_catalog.dart';
import '../../navigation/destinations.dart';

/// The provider's copy of a TMDB title, in the profile's language first, if
/// the catalogue in memory has it. Null while it loads or without one.
XtreamTitle? providerCopyNow({required bool series, required String? tmdbId}) {
  final id = tmdbId?.trim() ?? '';
  if (id.isEmpty || id == '0') return null;
  final catalog = currentProviderCatalog();
  if (catalog == null) return null;
  final copies = catalog.copiesNow(series ? XtreamKind.series : XtreamKind.movie, id);
  if (copies.isEmpty) return null;
  return orderByLanguages(copies, currentProviderLanguages()).first;
}

/// Plays the provider's copy of a TMDB title. False when it has none, so the
/// caller does what it would have done.
bool playProviderCopy(BuildContext context, {required bool series, required String? tmdbId}) {
  final copy = providerCopyNow(series: series, tmdbId: tmdbId);
  final catalog = currentProviderCatalog();
  if (copy == null || catalog == null) return false;
  if (copy.kind == XtreamKind.series) {
    context.push(Destinations.providerSeries(id: copy.id, name: copy.name, poster: copy.poster));
  } else {
    context.push(Destinations.trailer(url: catalog.movieUrl(copy)));
  }
  return true;
}

/// The tag itself, drawn like the Seerr ones: green dot, "IPTV" and the
/// language when it isn't the profile's first.
class ProviderIptvTag extends StatelessWidget {
  final XtreamTitle copy;
  final double scale;

  const ProviderIptvTag({super.key, required this.copy, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    final langs = currentProviderLanguages();
    final showTag = copy.tag.isNotEmpty && (langs.isEmpty || langs.first != copy.tag);
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
      decoration: BoxDecoration(color: const Color(0xD90B0B0D), borderRadius: BorderRadius.circular(3)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 12 * s, color: const Color(0xFF5BD18B)),
          SizedBox(width: 3 * s),
          Text(
            showTag ? 'IPTV · ${copy.tag}' : 'IPTV',
            style: TextStyle(color: Colors.white, fontSize: 11 * s, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Rebuilds [builder] once the provider's catalogue is in memory.
class ProviderCatalogListener extends StatelessWidget {
  final Widget Function(BuildContext context) builder;

  const ProviderCatalogListener({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: XtreamCatalog.loaded,
    builder: (context, _, _) => builder(context),
  );
}
