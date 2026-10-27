import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/provider_catalog_access.dart';
import '../../../data/services/vjod/xtream_catalog.dart';
import '../../navigation/destinations.dart';

/// A series read straight from the IPTV provider: its seasons and episodes,
/// fetched when the screen opens, each episode playing from the provider
/// without the media server knowing about it.
class ProviderSeriesScreen extends StatefulWidget {
  final String seriesId;
  final String name;
  final String poster;

  const ProviderSeriesScreen({
    super.key,
    required this.seriesId,
    required this.name,
    this.poster = '',
  });

  @override
  State<ProviderSeriesScreen> createState() => _ProviderSeriesScreenState();
}

class _ProviderSeriesScreenState extends State<ProviderSeriesScreen> {
  XtreamCatalog? _catalog;
  XtreamSeriesInfo? _info;
  Object? _error;
  int? _season;

  @override
  void initState() {
    super.initState();
    _catalog = currentProviderCatalog();
    _load();
  }

  Future<void> _load() async {
    final catalog = _catalog;
    if (catalog == null) {
      setState(() => _error = 'Aucun compte Xtream enregistré sur ce profil.');
      return;
    }
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final info = await catalog.seriesInfo(widget.seriesId);
      if (!mounted) return;
      setState(() {
        _info = info;
        final seasons = info.seasonNumbers;
        _season = seasons.isEmpty ? null : seasons.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _play(XtreamEpisode episode) {
    final catalog = _catalog;
    if (catalog == null) return;
    context.push(Destinations.trailer(url: catalog.episodeUrl(episode)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _body(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Le fournisseur ne répond pas pour cette série.\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
            FilledButton(
              autofocus: true,
              onPressed: _load,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    final info = _info;
    if (info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final seasons = info.seasonNumbers;
    if (seasons.isEmpty) {
      return const Center(
        child: Text('Le fournisseur ne liste aucun épisode pour cette série.'),
      );
    }
    final episodes = info.seasons[_season] ?? const <XtreamEpisode>[];
    final poster = info.cover.isNotEmpty ? info.cover : widget.poster;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (poster.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    poster,
                    width: 110,
                    height: 165,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 110, height: 165),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chez le fournisseur IPTV',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    info.plot,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, s) in seasons.indexed)
              ChoiceChip(
                autofocus: i == 0,
                label: Text('Saison $s'),
                selected: s == _season,
                onSelected: (_) => setState(() => _season = s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final episode in episodes)
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(
                episode.number > 0
                    ? '${episode.number}. ${episode.title}'
                    : episode.title,
              ),
              subtitle: episode.plot.isEmpty
                  ? null
                  : Text(
                      episode.plot,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => _play(episode),
            ),
          ),
      ],
    );
  }
}
