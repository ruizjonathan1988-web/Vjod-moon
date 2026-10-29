// The pieces of VJOD's own TV screens (Ma TV): category column, channel rows,
// details pane, the banner shown on each tune, the options (long OK or MENU) and the
// channel list opened with LEFT over the picture. They only draw what they
// are given, so the screen captures can show them without a seedbox.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../data/services/vjod/ma_tv.dart';

class MaTvColors {
  static const ink = Color(0xFFEDEBE6);
  static const mute = Color(0x99EDEBE6);
  static const faint = Color(0x4DEDEBE6);
  static const panel = Color(0xF20B0B0D);
  static const panelSoft = Color(0xD90B0B0D);
  static const row = Color(0x0FEDEBE6);
  static const rowOn = Color(0x29EDEBE6);
  static const accent = Color(0xFFE5A23A);
  static const live = Color(0xFFE5484D);
  static const good = Color(0xFF5BD18B);
}

/// Full-screen TV pages open at once, without the slide animation.
Route<T> maTvRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  pageBuilder: (context, _, _) => builder(context),
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

String maTvTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String maTvRange(MaTvProgram p) => '${maTvTime(p.start)} – ${maTvTime(p.end)}';

/// "dans 12 min", "reste 34 min".
String maTvLeft(MaTvProgram p, DateTime now) {
  final m = p.end.difference(now).inMinutes;
  return m <= 0 ? 'se termine' : 'reste $m min';
}

const _days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

/// "aujourd'hui", "hier", "mardi 27".
String maTvDay(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return "aujourd'hui";
  if (diff == 1) return 'hier';
  if (diff == -1) return 'demain';
  return '${_days[t.weekday - 1]} ${t.day}';
}

class MaTvLogo extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const MaTvLogo({super.key, required this.url, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.characters.first.toUpperCase()).join();
    final fallback = Center(
      child: Text(
        initials,
        style: TextStyle(color: MaTvColors.mute, fontSize: size * 0.34, fontWeight: FontWeight.w700),
      ),
    );
    return Container(
      width: size * 1.45,
      height: size,
      decoration: BoxDecoration(color: const Color(0x14EDEBE6), borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.all(4),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.contain,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class MaTvProgress extends StatelessWidget {
  final double value;
  final double height;

  const MaTvProgress({super.key, required this.value, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x26EDEBE6)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const ColoredBox(color: MaTvColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// The category column: favourites, recents, then Ma TV's themes and countries.
class MaTvCategoryList extends StatelessWidget {
  final List<MaTvCategory> categories;
  final int selected;
  final bool focused;
  final ScrollController? controller;
  final ValueChanged<int>? onTap;

  const MaTvCategoryList({
    super.key,
    required this.categories,
    required this.selected,
    required this.focused,
    this.controller,
    this.onTap,
  });

  static const rowHeight = 52.0;

  static IconData iconFor(MaTvCategory c) => switch (c.kind) {
    'fav' => Icons.star_rounded,
    'recent' => Icons.history_rounded,
    'replay' => Icons.replay_rounded,
    'all' => Icons.apps_rounded,
    'country' => Icons.public_rounded,
    _ => switch (c.label) {
      'Sport' => Icons.sports_soccer_rounded,
      'Info' => Icons.newspaper_rounded,
      'Cinéma' => Icons.movie_rounded,
      'Séries' => Icons.theaters_rounded,
      'Jeunesse' => Icons.child_care_rounded,
      'Docs' => Icons.explore_rounded,
      'Musique' => Icons.music_note_rounded,
      'Divertissement' => Icons.celebration_rounded,
      _ => Icons.live_tv_rounded,
    },
  };

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: categories.length,
      itemExtent: rowHeight,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) {
        final c = categories[i];
        final on = i == selected;
        return GestureDetector(
          onTap: onTap == null ? null : () => onTap!(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? (focused ? MaTvColors.ink : MaTvColors.rowOn) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(iconFor(c), size: 20, color: on && focused ? Colors.black : MaTvColors.mute),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: on && focused ? Colors.black : MaTvColors.ink,
                      fontSize: 15.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (c.count > 0)
                  Text(
                    '${c.count}',
                    style: TextStyle(color: on && focused ? Colors.black54 : MaTvColors.faint, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One channel: number, logo, name, what's on with its progress, what's next.
class MaTvChannelRow extends StatelessWidget {
  final MaTvChannel channel;
  final DateTime now;
  final bool selected;
  final bool focused;
  final bool favorite;
  final bool playing;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MaTvChannelRow({
    super.key,
    required this.channel,
    required this.now,
    this.selected = false,
    this.focused = false,
    this.favorite = false,
    this.playing = false,
    this.compact = false,
    this.onTap,
    this.onLongPress,
  });

  static const height = 84.0;
  static const compactHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final cur = channel.programAt(now);
    final next = channel.programAfter(now);
    final hot = selected && focused;
    final small = MediaQuery.sizeOf(context).width < 700;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        margin: const EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 8),
        decoration: BoxDecoration(
          color: hot ? MaTvColors.rowOn : (selected ? const Color(0x1AEDEBE6) : MaTvColors.row),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hot ? MaTvColors.ink : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            SizedBox(
              width: small ? 34 : 46,
              child: Text(
                '${channel.number}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: playing ? MaTvColors.accent : MaTvColors.mute,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            MaTvLogo(url: channel.logo, name: channel.name, size: compact ? 34 : 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: MaTvColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (favorite) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded, size: 15, color: MaTvColors.accent),
                      ],
                      if (channel.replayDays > 0) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.replay_rounded, size: 14, color: MaTvColors.mute),
                      ],
                      if (playing) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.graphic_eq_rounded, size: 15, color: MaTvColors.accent),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cur == null ? 'Pas de programme annoncé' : '${maTvTime(cur.start)}  ${cur.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cur == null ? MaTvColors.faint : MaTvColors.mute, fontSize: 13.5),
                  ),
                  if (cur != null) ...[
                    const SizedBox(height: 3),
                    SizedBox(
                      height: compact ? 3 : 15,
                      child: Row(
                      children: [
                        SizedBox(width: 90, child: MaTvProgress(value: cur.progressAt(now))),
                        if (next != null && !compact) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'puis ${maTvTime(next.start)} ${next.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: MaTvColors.faint, fontSize: 12, height: 1.2),
                            ),
                          ),
                        ],
                      ],
                    ),
                    ),
                  ],
                ],
              ),
            ),
            if (channel.quality.isNotEmpty && !compact && !small)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(channel.quality, style: const TextStyle(color: MaTvColors.faint, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

class MaTvChannelList extends StatelessWidget {
  final List<MaTvChannel> channels;
  final int selected;
  final bool focused;
  final DateTime now;
  final Set<String> favorites;
  final String? playingId;
  final bool compact;
  final ScrollController? controller;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onLongPress;
  final String emptyText;

  const MaTvChannelList({
    super.key,
    required this.channels,
    required this.selected,
    required this.focused,
    required this.now,
    this.favorites = const {},
    this.playingId,
    this.compact = false,
    this.controller,
    this.onTap,
    this.onLongPress,
    this.emptyText = 'Aucune chaîne ici.',
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return Center(child: Text(emptyText, style: const TextStyle(color: MaTvColors.mute, fontSize: 15)));
    }
    return ListView.builder(
      controller: controller,
      itemCount: channels.length,
      itemExtent: (compact ? MaTvChannelRow.compactHeight : MaTvChannelRow.height) + 6,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) {
        final c = channels[i];
        return MaTvChannelRow(
          channel: c,
          now: now,
          selected: i == selected,
          focused: focused,
          favorite: favorites.contains(c.id),
          playing: c.id == playingId,
          compact: compact,
          onTap: onTap == null ? null : () => onTap!(i),
          onLongPress: onLongPress == null ? null : () => onLongPress!(i),
        );
      },
    );
  }
}

/// Right-hand pane of the browser: the channel under the cursor, what's on
/// with its summary, and the next programmes.
class MaTvDetailsPane extends StatelessWidget {
  final MaTvChannel? channel;
  final List<MaTvProgram> programs;
  final DateTime now;

  const MaTvDetailsPane({super.key, required this.channel, required this.programs, required this.now});

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    if (ch == null) return const SizedBox.shrink();
    final upcoming = programs.where((p) => p.end.isAfter(now)).toList();
    final cur = upcoming.isNotEmpty && upcoming.first.isOnAt(now) ? upcoming.first : ch.programAt(now);
    final later = upcoming.where((p) => p != cur && p.start.isAfter(now)).take(4).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0x0DEDEBE6), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MaTvLogo(url: ch.logo, name: ch.name, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${ch.number}  ${ch.name}',
                  maxLines: 2,
                  style: const TextStyle(color: MaTvColors.ink, fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cur != null && cur.image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  cur.image,
                  fit: BoxFit.cover,
                  cacheWidth: 640,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x0DEDEBE6)),
                ),
              ),
            ),
          if (cur != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: MaTvColors.live, borderRadius: BorderRadius.circular(4)),
                  child: const Text('EN DIRECT', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                Text('${maTvRange(cur)} · ${maTvLeft(cur, now)}', style: const TextStyle(color: MaTvColors.mute, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              cur.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MaTvColors.ink, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (cur.subtitle.isNotEmpty)
              Text(cur.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MaTvColors.mute, fontSize: 14)),
            const SizedBox(height: 6),
            MaTvProgress(value: cur.progressAt(now), height: 4),
            if (cur.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                cur.description,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MaTvColors.mute, fontSize: 13.5, height: 1.35),
              ),
            ],
          ] else
            const Text('Pas de programme annoncé pour cette chaîne.', style: TextStyle(color: MaTvColors.faint, fontSize: 14)),
          if (later.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('ENSUITE', style: TextStyle(color: MaTvColors.faint, fontSize: 11.5, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final p in later)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(maTvTime(p.start), style: const TextStyle(color: MaTvColors.mute, fontSize: 13.5)),
                    ),
                    Expanded(
                      child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MaTvColors.ink, fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The banner shown on each tune and on demand, over the bottom of the picture.
class MaTvBanner extends StatelessWidget {
  final MaTvChannel channel;
  final DateTime now;
  final String? sourceLine;
  final String? status;
  final String categoryLabel;
  final bool favorite;
  final String? replayLabel;

  const MaTvBanner({
    super.key,
    required this.channel,
    required this.now,
    this.sourceLine,
    this.status,
    this.categoryLabel = '',
    this.favorite = false,
    this.replayLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cur = channel.programAt(now);
    final next = channel.programAfter(now);
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF2000000), Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${channel.number}',
            style: const TextStyle(color: MaTvColors.ink, fontSize: 40, fontWeight: FontWeight.w800, height: 1),
          ),
          const SizedBox(width: 18),
          MaTvLogo(url: channel.logo, name: channel.name, size: 58),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: MaTvColors.ink, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (favorite) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded, size: 20, color: MaTvColors.accent),
                    ],
                    if (categoryLabel.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(categoryLabel, style: const TextStyle(color: MaTvColors.faint, fontSize: 14)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                if (replayLabel != null)
                  Text(replayLabel!, style: const TextStyle(color: MaTvColors.accent, fontSize: 16, fontWeight: FontWeight.w700))
                else if (cur != null) ...[
                  Text(
                    cur.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MaTvColors.ink, fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(maTvTime(cur.start), style: const TextStyle(color: MaTvColors.mute, fontSize: 13)),
                      const SizedBox(width: 8),
                      Expanded(child: MaTvProgress(value: cur.progressAt(now), height: 4)),
                      const SizedBox(width: 8),
                      Text(maTvTime(cur.end), style: const TextStyle(color: MaTvColors.mute, fontSize: 13)),
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ensuite  ${maTvTime(next.start)}  ${next.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MaTvColors.mute, fontSize: 14),
                    ),
                  ],
                ] else
                  const Text('Pas de programme annoncé', style: TextStyle(color: MaTvColors.faint, fontSize: 15)),
                if (sourceLine != null || status != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    [status, sourceLine].whereType<String>().where((s) => s.isNotEmpty).join('  ·  '),
                    style: TextStyle(color: status != null ? MaTvColors.accent : MaTvColors.faint, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(maTvTime(now), style: const TextStyle(color: MaTvColors.ink, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const _KeyHints(),
            ],
          ),
        ],
      ),
    );
  }
}

/// What a long OK (or MENU) opens over the picture: the programme on, its summary, the next
/// ones, and a row of actions (watch from the start, favourite, sources).
class MaTvMiniGuide extends StatelessWidget {
  final MaTvChannel channel;
  final List<MaTvProgram> programs;
  final DateTime now;
  final List<({IconData icon, String label})> actions;
  final int selectedAction;
  final ValueChanged<int>? onAction;

  /// One key per action, to find which button sits above or below another.
  final List<GlobalKey>? actionKeys;

  const MaTvMiniGuide({
    super.key,
    required this.channel,
    required this.programs,
    required this.now,
    required this.actions,
    required this.selectedAction,
    this.onAction,
    this.actionKeys,
  });

  @override
  Widget build(BuildContext context) {
    final cur = programs.where((p) => p.isOnAt(now)).firstOrNull ?? channel.programAt(now);
    final later = programs.where((p) => p.start.isAfter(now)).take(3).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      decoration: BoxDecoration(
        color: MaTvColors.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: const Color(0x22EDEBE6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cur != null && cur.image.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 260,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    cur.image,
                    fit: BoxFit.cover,
                    cacheWidth: 520,
                    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0x0DEDEBE6)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 22),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${channel.number}  ${channel.name}', style: const TextStyle(color: MaTvColors.mute, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  cur?.title ?? 'Pas de programme annoncé',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaTvColors.ink, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                if (cur != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [maTvRange(cur), maTvLeft(cur, now), if (cur.category.isNotEmpty) cur.category, if (cur.subtitle.isNotEmpty) cur.subtitle]
                        .join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MaTvColors.mute, fontSize: 13.5),
                  ),
                  const SizedBox(height: 8),
                  MaTvProgress(value: cur.progressAt(now), height: 4),
                  if (cur.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      cur.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MaTvColors.mute, fontSize: 14, height: 1.35),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      GestureDetector(
                        key: actionKeys != null && i < actionKeys!.length ? actionKeys![i] : null,
                        onTap: onAction == null ? null : () => onAction!(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: i == selectedAction ? MaTvColors.ink : const Color(0x1AEDEBE6),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(actions[i].icon, size: 18, color: i == selectedAction ? Colors.black : MaTvColors.ink),
                              const SizedBox(width: 8),
                              Text(
                                actions[i].label,
                                style: TextStyle(
                                  color: i == selectedAction ? Colors.black : MaTvColors.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (later.isNotEmpty) ...[
            const SizedBox(width: 26),
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('ENSUITE', style: TextStyle(color: MaTvColors.faint, fontSize: 11.5, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final p in later)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(maTvTime(p.start), style: const TextStyle(color: MaTvColors.mute, fontSize: 14)),
                          ),
                          Expanded(
                            child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MaTvColors.ink, fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The past programmes of a channel, for its replay: newest first, grouped
/// by day.
class MaTvReplayList extends StatelessWidget {
  final MaTvChannel channel;
  final List<MaTvProgram> programs;
  final DateTime now;
  final int selected;
  final ScrollController? controller;
  final ValueChanged<int>? onTap;

  const MaTvReplayList({
    super.key,
    required this.channel,
    required this.programs,
    required this.now,
    required this.selected,
    this.controller,
    this.onTap,
  });

  static const rowHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    if (programs.isEmpty) {
      return const Center(
        child: Text('Aucun programme passé dans le guide pour cette chaîne.', style: TextStyle(color: MaTvColors.mute, fontSize: 15)),
      );
    }
    return ListView.builder(
      controller: controller,
      itemCount: programs.length,
      itemExtent: rowHeight + 6,
      padding: EdgeInsets.zero,
      itemBuilder: (context, i) {
        final p = programs[i];
        final on = i == selected;
        return GestureDetector(
          onTap: onTap == null ? null : () => onTap!(i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: on ? MaTvColors.rowOn : MaTvColors.row,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? MaTvColors.ink : Colors.transparent, width: 2),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    '${maTvDay(p.start, now)}\n${maTvRange(p)}',
                    style: const TextStyle(color: MaTvColors.mute, fontSize: 13, height: 1.3),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MaTvColors.ink, fontSize: 15.5, fontWeight: FontWeight.w600)),
                      if (p.subtitle.isNotEmpty || p.category.isNotEmpty)
                        Text(
                          [p.subtitle, p.category].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: MaTvColors.faint, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
                Text('${p.minutes} min', style: const TextStyle(color: MaTvColors.faint, fontSize: 12.5)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KeyHints extends StatelessWidget {
  const _KeyHints();

  @override
  Widget build(BuildContext context) {
    Widget hint(IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: MaTvColors.faint),
          const SizedBox(width: 3),
          Text(label, style: const TextStyle(color: MaTvColors.faint, fontSize: 12)),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        hint(Icons.unfold_more_rounded, 'chaînes'),
        hint(Icons.radio_button_checked_rounded, 'liste'),
        hint(Icons.replay_30_rounded, '−30 s'),
        hint(Icons.forward_30_rounded, '+30 s'),
        hint(Icons.menu_rounded, 'options'),
      ],
    );
  }
}
