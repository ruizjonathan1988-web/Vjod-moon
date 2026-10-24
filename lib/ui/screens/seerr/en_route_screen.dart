import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/services/seerr/my_requests.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/offline_aware_image.dart';

const _tmdbPoster = 'https://image.tmdb.org/t/p/w342';

/// One title on its way, with what the list shows of it.
class _EnRouteEntry {
  final MyRequestEntry entry;
  final String title;
  final String? posterUrl;
  final String? year;
  final Duration? runtime;

  const _EnRouteEntry({
    required this.entry,
    required this.title,
    this.posterUrl,
    this.year,
    this.runtime,
  });

  bool get isTv => entry.request.type == 'tv';
  int? get tmdbId => entry.media.tmdbId;
}

/// En route: what the viewer asked for, from the request to the moment it
/// can be watched, with the download's progress in between. A plain list
/// rather than the Seerr hub, which is about managing everyone's requests.
class EnRouteScreen extends StatefulWidget {
  const EnRouteScreen({super.key});

  @override
  State<EnRouteScreen> createState() => _EnRouteScreenState();
}

class _EnRouteScreenState extends State<EnRouteScreen> {
  List<_EnRouteEntry>? _entries;
  bool _failed = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Downloads move every few seconds, so the bars keep up while open.
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) throw StateError('Seerr unavailable');
      final user = await repo.getCurrentUser();
      final response = await repo.getRequests(
        requestedBy: user.id,
        sort: 'modified',
        limit: 50,
      );
      final now = DateTime.now();
      var entries = myRequestEntries(response.results, now: now, limit: 30);

      // Seerr can lag behind the library: a title already in it is ready.
      final client = GetIt.instance<MediaServerClient>();
      final candidates = [
        for (final e in libraryCandidates(entries))
          if (e.media.tmdbId != null) e,
      ];
      if (candidates.isNotEmpty) {
        final inLibrary = await RowDataSource(client).loadLibraryTmdbKeys(
          client.baseUrl,
          [
            for (final e in candidates)
              (
                mediaType: e.request.type == 'tv' ? 'tv' : 'movie',
                tmdbId: e.media.tmdbId!,
              ),
          ],
        );
        entries = promoteInLibrary(entries, inLibrary, now: now);
      }

      final previous = {
        for (final e in _entries ?? const <_EnRouteEntry>[]) e.entry.key: e,
      };
      final enriched = await Future.wait([
        for (final e in entries) _enrich(repo, e, previous[e.key]),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = enriched;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[EnRoute] Failed to load requests: $e');
      if (mounted && _entries == null) setState(() => _failed = true);
    }
  }

  /// Title and poster come from the details, which a request doesn't carry.
  /// A title already drawn keeps them rather than fetching them again.
  Future<_EnRouteEntry> _enrich(
    SeerrRepository repo,
    MyRequestEntry e,
    _EnRouteEntry? known,
  ) async {
    if (known != null) {
      return _EnRouteEntry(
        entry: e,
        title: known.title,
        posterUrl: known.posterUrl,
        year: known.year,
        runtime: known.runtime,
      );
    }
    final fallback = e.media.title ?? e.media.name ?? '';
    final tmdbId = e.media.tmdbId;
    if (tmdbId == null) return _EnRouteEntry(entry: e, title: fallback);
    try {
      if (e.request.type == 'tv') {
        final d = await repo.getTvDetails(tmdbId);
        return _EnRouteEntry(
          entry: e,
          title: d.name ?? d.title ?? fallback,
          posterUrl: d.posterPath == null ? null : '$_tmdbPoster${d.posterPath}',
          year: d.firstAirDate == null || d.firstAirDate!.length < 4
              ? null
              : d.firstAirDate!.substring(0, 4),
        );
      }
      final d = await repo.getMovieDetails(tmdbId);
      return _EnRouteEntry(
        entry: e,
        title: d.title,
        posterUrl: d.posterPath == null ? null : '$_tmdbPoster${d.posterPath}',
        year: d.releaseDate == null || d.releaseDate!.length < 4
            ? null
            : d.releaseDate!.substring(0, 4),
        runtime: d.runtime == null ? null : Duration(minutes: d.runtime!),
      );
    } catch (_) {
      return _EnRouteEntry(entry: e, title: fallback);
    }
  }

  void _open(_EnRouteEntry e) {
    final tmdbId = e.tmdbId;
    if (tmdbId == null) return;
    // The Seerr page swaps itself for the library one once the title is in.
    context.push(
      Destinations.seerrMedia(
        '$tmdbId',
        mediaType: e.isTv ? 'tv' : 'movie',
        title: e.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.enRoute,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = GetIt.instance<UserPreferences>();
    final isTv = PlatformDetection.isTV;
    final isMobile = PlatformDetection.useMobileUi;
    final navbarIsTop =
        prefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;
    final navbarHeight = navbarIsTop
        ? (isTv ? 95.0 : (isMobile ? 60.0 : 80.0))
        : 0.0;
    final navbarIsLeft =
        prefs.get(UserPreferences.navbarPosition) == NavbarPosition.left;
    final left = isMobile ? 16.0 : (navbarIsLeft ? 120.0 : 64.0);
    final top = MediaQuery.paddingOf(context).top + navbarHeight + 16;
    final ink = AppColorScheme.onBackground;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(left, top, left, 20),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(
            l10n.enRouteTitle.toUpperCase(),
            style: TextStyle(
              color: ink,
              fontSize: isMobile ? 30 : 40,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          Text(
            l10n.enRouteSubtitle,
            style: TextStyle(
              color: ink.withValues(alpha: 0.6),
              fontSize: isMobile ? 14 : 17,
            ),
          ),
        ],
      ),
    );

    final entries = _entries;
    Widget content;
    if (entries == null) {
      content = _failed
          ? _Message(text: l10n.enRouteFailed)
          : const Center(child: CircularProgressIndicator());
    } else if (entries.isEmpty) {
      content = _Message(text: l10n.enRouteEmpty);
    } else {
      content = ListView.separated(
        padding: EdgeInsets.fromLTRB(left, 0, left, 32),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _EnRouteTile(
          entry: entries[i],
          autofocus: i == 0 && isTv,
          compact: isMobile,
          onOpen: () => _open(entries[i]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Expanded(child: content),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message({required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColorScheme.onBackground.withValues(alpha: 0.7),
          fontSize: 17,
        ),
      ),
    ),
  );
}

class _EnRouteTile extends StatefulWidget {
  final _EnRouteEntry entry;
  final bool autofocus;
  final bool compact;
  final VoidCallback onOpen;

  const _EnRouteTile({
    required this.entry,
    required this.autofocus,
    required this.compact,
    required this.onOpen,
  });

  @override
  State<_EnRouteTile> createState() => _EnRouteTileState();
}

class _EnRouteTileState extends State<_EnRouteTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = widget.entry;
    final state = e.entry.state;
    final progress = e.entry.progress;
    final ink = AppColorScheme.onBackground;
    final (label, color) = switch (state) {
      MyRequestState.ready => (l10n.seerrTagReady, AppColorScheme.statusAvailable),
      MyRequestState.downloading => (
        progress == null
            ? l10n.requestStateDownloadingShort
            : l10n.requestStateDownloading((progress * 100).round()),
        AppColorScheme.statusDownloading,
      ),
      MyRequestState.approved => (
        l10n.requestStateApproved,
        AppColorScheme.statusRequested,
      ),
      MyRequestState.pending => (
        l10n.requestStatePending,
        AppColorScheme.statusPending,
      ),
      MyRequestState.failed || MyRequestState.declined => (
        l10n.requestStateFailed,
        AppColorScheme.statusError,
      ),
    };
    // How far along the whole journey is: asked, approved, downloading, in.
    final journey = switch (state) {
      MyRequestState.ready => 1.0,
      MyRequestState.downloading => 0.35 + 0.6 * (progress ?? 0),
      MyRequestState.approved => 0.25,
      MyRequestState.pending => 0.1,
      MyRequestState.failed || MyRequestState.declined => 0.0,
    };
    final meta = [
      ?e.year,
      e.isTv ? l10n.series : l10n.movie,
      if (e.runtime case final r?)
        r.inHours > 0
            ? '${r.inHours} h ${(r.inMinutes % 60).toString().padLeft(2, '0')}'
            : '${r.inMinutes} min',
    ].join(' · ');
    final posterW = widget.compact ? 64.0 : 92.0;
    final ready = state == MyRequestState.ready;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? ink : Colors.transparent,
              width: 3,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: posterW,
                  height: posterW * 1.5,
                  child: e.posterUrl == null
                      ? ColoredBox(color: AppColorScheme.surfaceVariant)
                      : OfflineAwareImage(
                          imageUrl: e.posterUrl!,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: widget.compact ? 16 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.6),
                          fontSize: widget.compact ? 13 : 15,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: journey,
                        minHeight: 6,
                        backgroundColor: ink.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: widget.compact ? 13 : 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (ready && !widget.compact) ...[
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: AppColorScheme.background,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.enRouteWatch,
                        style: TextStyle(
                          color: AppColorScheme.background,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
