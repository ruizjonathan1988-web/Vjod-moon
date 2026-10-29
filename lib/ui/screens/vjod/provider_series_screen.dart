import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/iptv_progress.dart';
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

  /// The series' TMDB id, for resuming and learning from what is watched.
  final String tmdb;

  /// The quality picked on the title's page (`4K`…), empty for the default.
  final String quality;

  /// The file picked on the title's page (Ma TV's source number), if any.
  final int? source;

  const ProviderSeriesScreen({
    super.key,
    required this.seriesId,
    required this.name,
    this.poster = '',
    this.tmdb = '',
    this.quality = '',
    this.source,
  });

  @override
  State<ProviderSeriesScreen> createState() => _ProviderSeriesScreenState();
}

class _ProviderSeriesScreenState extends State<ProviderSeriesScreen> {
  XtreamCatalog? _catalog;
  XtreamSeriesInfo? _info;
  Object? _error;
  int? _season;

  /// The last episode watched (Ma TV keeps it for this profile), and the one
  /// to play next: the same one when it was left halfway, else the following.
  IptvProgress? _progress;
  XtreamEpisode? _next;

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
      final (info, progress) = await (
        catalog.seriesInfo(
          widget.seriesId,
          quality: widget.quality,
          source: widget.source,
        ),
        IptvProgressStore.get('series', widget.seriesId),
      ).wait;
      if (!mounted) return;
      final next = progress == null ? null : _nextEpisode(info, progress);
      setState(() {
        _info = info;
        _progress = progress;
        _next = next;
        final seasons = info.seasonNumbers;
        _season = next?.season ?? (seasons.isEmpty ? null : seasons.first);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// The episode to go on with: the last one when left halfway, else the
  /// one after it (none after the last episode of the series).
  static XtreamEpisode? _nextEpisode(XtreamSeriesInfo info, IptvProgress p) {
    final all = [
      for (final s in info.seasonNumbers) ...?info.seasons[s],
    ];
    final i = all.indexWhere((e) => e.id == p.ep);
    if (i < 0) return null;
    if (!p.done) return all[i];
    return i + 1 < all.length ? all[i + 1] : null;
  }

  void _play(XtreamEpisode episode) {
    final catalog = _catalog;
    if (catalog == null) return;
    context
        .push(
          Destinations.providerPlayer(
            url: catalog.episodeUrl(episode),
            title: '${widget.name} · S${episode.season} É${episode.number}',
            watch: IptvWatch(
              kind: 'series',
              id: widget.seriesId,
              name: widget.name,
              tmdb: widget.tmdb,
              poster: widget.poster,
              ep: episode.id,
              ext: episode.extension,
              season: episode.season,
              episode: episode.number,
              epName: episode.title,
            ),
          ),
        )
        .then((_) => _refreshProgress());
  }

  /// Back from an episode: what to go on with has moved.
  Future<void> _refreshProgress() async {
    final info = _info;
    if (info == null) return;
    final p = await IptvProgressStore.get('series', widget.seriesId);
    if (!mounted || p == null) return;
    setState(() {
      _progress = p;
      _next = _nextEpisode(info, p);
    });
  }

  Widget _resumeButton(XtreamEpisode next) {
    final p = _progress;
    final same = p != null && p.ep == next.id && !p.done;
    final label = same
        ? 'Reprendre S${next.season} É${next.number} (${p.position.inMinutes} min)'
        : 'Épisode suivant : S${next.season} É${next.number}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          autofocus: true,
          onPressed: () => _play(next),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(label),
        ),
      ),
    );
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
                'Aucun fournisseur n\'a d\'épisodes pour cette série en ce moment. '
                'Réessaie plus tard, ou demande-la avec « Demander ».',
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Recherche des épisodes chez les fournisseurs…'),
          ],
        ),
      );
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
        if (_next case final next?) _resumeButton(next),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, s) in seasons.indexed)
              ChoiceChip(
                autofocus: i == 0 && _next == null,
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
