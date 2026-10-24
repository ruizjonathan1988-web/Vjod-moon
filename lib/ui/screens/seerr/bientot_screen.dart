import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/offline_aware_image.dart';
import '../../widgets/vjod/vjod_widgets.dart';

const _tmdbPoster = 'https://image.tmdb.org/t/p/w342';

class _Coming {
  final SeerrDiscoverItem item;
  final bool isTv;
  final DateTime date;
  const _Coming(this.item, this.isTv, this.date);

  String get title => item.title ?? item.name ?? '';
}

/// Bientôt, as in the mock-up: what comes out in the months ahead, month by
/// month, each with its date and a press to ask for it before it's out.
class BientotScreen extends StatefulWidget {
  const BientotScreen({super.key});

  @override
  State<BientotScreen> createState() => _BientotScreenState();
}

class _BientotScreenState extends State<BientotScreen> {
  List<_Coming>? _all;
  bool _failed = false;
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) throw StateError('Seerr unavailable');
      final pages = await Future.wait([
        for (var p = 1; p <= 3; p++) ...[
          repo.getUpcomingMovies(page: p),
          repo.getUpcomingTv(page: p),
        ],
      ]);
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final seen = <String>{};
      final all = <_Coming>[];
      for (final (i, page) in pages.indexed) {
        final isTv = i.isOdd;
        for (final item in page.results) {
          if (item.adult) continue;
          final raw = isTv ? item.firstAirDate : item.releaseDate;
          final date = raw == null ? null : DateTime.tryParse(raw);
          if (date == null || date.isBefore(start)) continue;
          if (!seen.add('${isTv ? 'tv' : 'movie'}:${item.id}')) continue;
          all.add(_Coming(item, isTv, date));
        }
      }
      all.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() => _all = all);
    } catch (e) {
      debugPrint('[Bientot] Failed to load upcoming titles: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _open(_Coming c) {
    context.push(
      Destinations.seerrMedia(
        '${c.item.id}',
        mediaType: c.isTv ? 'tv' : 'movie',
        title: c.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.bientot,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final prefs = GetIt.instance<UserPreferences>();
    final isMobile = PlatformDetection.useMobileUi;
    final width = MediaQuery.sizeOf(context).width;
    final s = isMobile ? 0.8 : (width / 1280).clamp(0.6, 1.2);
    final navbarIsTop =
        prefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;
    final navbarHeight = navbarIsTop
        ? (PlatformDetection.isTV ? 95.0 : (isMobile ? 60.0 : 80.0))
        : 0.0;
    final left = isMobile ? 16.0 : 64 * s;
    final top = MediaQuery.paddingOf(context).top + navbarHeight + 12;

    final all = _all;
    final shown = all == null
        ? const <_Coming>[]
        : [
            for (final c in all)
              if (_filter == 0 || (_filter == 2) == c.isTv) c,
          ];
    final months = <String, List<_Coming>>{};
    for (final c in shown) {
      final key = DateFormat.yMMMM(locale).format(c.date);
      (months[key] ??= []).add(c);
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(left, top, left, 16 * s),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20 * s,
        runSpacing: 10,
        children: [
          Text(
            l10n.vjodTabSoon.toUpperCase(),
            style: vjodDisplay(48 * s),
          ),
          VjodSegmented(
            scale: s,
            options: [l10n.all, l10n.vjodTabMovies, l10n.vjodTabSeries],
            selected: _filter,
            onSelect: (i) => setState(() => _filter = i),
          ),
          Text(
            l10n.vjodSoonHint,
            style: TextStyle(
              color: vjodInk.withValues(alpha: 0.55),
              fontSize: 17 * s,
            ),
          ),
        ],
      ),
    );

    Widget content;
    if (all == null) {
      content = _failed
          ? Center(child: Text(l10n.enRouteFailed))
          : const Center(child: CircularProgressIndicator());
    } else {
      final cardW = 165 * s * (isMobile ? 1.0 : 1);
      content = ListView(
        padding: EdgeInsets.fromLTRB(left, 0, left, 40),
        children: [
          for (final (m, entry) in months.entries.indexed) ...[
            Padding(
              padding: EdgeInsets.only(top: m == 0 ? 0 : 24 * s, bottom: 10 * s),
              child: Text(
                entry.key.isEmpty
                    ? entry.key
                    : entry.key[0].toUpperCase() + entry.key.substring(1),
                style: TextStyle(
                  color: vjodInk,
                  fontSize: 22 * s,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Wrap(
              spacing: 15 * s,
              runSpacing: 18 * s,
              children: [
                for (final (i, c) in entry.value.indexed)
                  _ComingCard(
                    coming: c,
                    width: cardW,
                    scale: s,
                    autofocus: m == 0 && i == 0 && PlatformDetection.isTV,
                    dateLabel: DateFormat.MMMd(locale)
                        .format(c.date)
                        .toUpperCase(),
                    onTap: () => _open(c),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, Expanded(child: content)],
    );
  }
}

class _ComingCard extends StatelessWidget {
  final _Coming coming;
  final double width;
  final double scale;
  final bool autofocus;
  final String dateLabel;
  final VoidCallback onTap;

  const _ComingCard({
    required this.coming,
    required this.width,
    required this.scale,
    required this.autofocus,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = scale;
    final status = coming.item.mediaInfo?.status;
    final (label, color) = switch (status) {
      SeerrMediaStatus.available ||
      SeerrMediaStatus.partiallyAvailable => (
        l10n.seerrTagReady,
        AppColorScheme.statusAvailable,
      ),
      SeerrMediaStatus.pending ||
      SeerrMediaStatus.processing => (
        l10n.seerrTagRequested,
        AppColorScheme.statusRequested,
      ),
      _ => (l10n.vjodRequestIt, AppColorScheme.accent),
    };
    final poster = coming.item.posterPath;
    return VjodFocusable(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: width * 1.5,
              decoration: BoxDecoration(
                color: AppColorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                boxShadow: vjodFocusRing(s, on: focused),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster != null)
                    OfflineAwareImage(
                      imageUrl: '$_tmdbPoster$poster',
                      fit: BoxFit.cover,
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * s,
                        vertical: 4 * s,
                      ),
                      color: const Color(0xD90B0B0D),
                      child: Text(
                        dateLabel,
                        style: vjodDisplay(17 * s),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 6 * s),
            Row(
              children: [
                Container(
                  width: 7 * s,
                  height: 7 * s,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6 * s),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color == AppColorScheme.accent
                          ? vjodInk
                          : color,
                      fontSize: 15 * s,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              coming.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: vjodInk.withValues(alpha: 0.7),
                fontSize: 14 * s,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
