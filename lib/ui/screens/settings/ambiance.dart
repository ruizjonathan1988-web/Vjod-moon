import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/services/plugin_sync_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../theme/app_theme_controller.dart';

/// One choice that sets the look of the whole app at once: colours, the
/// banner at the top of home and the video previews. The settings it touches
/// stay where they are for anyone who wants to fine-tune them afterwards.
enum Ambiance {
  vjod,
  ecrin,
  classic;

  VisualThemeId get theme => switch (this) {
    Ambiance.vjod => VisualThemeId.vjod,
    Ambiance.ecrin => VisualThemeId.ecrin,
    Ambiance.classic => VisualThemeId.moonfin,
  };

  String get mediaBarMode => switch (this) {
    Ambiance.vjod || Ambiance.ecrin => UserPreferences.mediaBarModeVjod,
    Ambiance.classic => UserPreferences.mediaBarModeMoonfin,
  };

  String get mediaBarSource => switch (this) {
    Ambiance.vjod || Ambiance.ecrin => UserPreferences.mediaBarSourceTonight,
    Ambiance.classic => UserPreferences.mediaBarSourceRandom,
  };

  /// Écrin is the quiet one: no video starting by itself.
  bool get previews => this != Ambiance.ecrin;

  /// Which ambiance the current settings amount to, if any.
  static Ambiance? current(UserPreferences prefs) {
    final theme = prefs.get(UserPreferences.visualTheme);
    final mode = UserPreferences.normalizeMediaBarMode(
      prefs.get(UserPreferences.mediaBarMode),
    );
    for (final a in Ambiance.values) {
      if (a.theme == theme && a.mediaBarMode == mode) {
        if (a == Ambiance.vjod &&
            !prefs.get(UserPreferences.mediaBarTrailerPreview)) {
          continue;
        }
        return a;
      }
    }
    return null;
  }

  Future<void> apply(UserPreferences prefs, AppThemeController theme) async {
    await theme.applyThemeSelection(prefs, this.theme);
    await prefs.set(UserPreferences.mediaBarMode, mediaBarMode);
    await prefs.set(UserPreferences.mediaBarSourceType, mediaBarSource);
    await prefs.set(UserPreferences.mediaBarTrailerPreview, previews);
    // Sound only once asked for: a preview that starts talking on its own
    // while someone is choosing is the opposite of calm.
    await prefs.set(UserPreferences.mediaBarTrailerAudio, false);
    await prefs.set(UserPreferences.previewAudioEnabled, false);
    await prefs.set(UserPreferences.episodePreviewEnabled, previews);
    // The mock-up's film page names the picture, sound and languages.
    await prefs.set(
      UserPreferences.detailShowTechnicalDetails,
      this != Ambiance.classic,
    );
    // The mock-up's clock is French: 21:15, not 9:15 PM.
    if (this != Ambiance.classic) {
      await prefs.set(UserPreferences.use24HourClock, true);
      // The mock-up's player: time played on the left, time left on the
      // right, nothing above the bar.
      await prefs.set(UserPreferences.playbackTimeAboveLeft, PlaybackTimeSlot.none);
      await prefs.set(UserPreferences.playbackTimeAboveCenter, PlaybackTimeSlot.none);
      await prefs.set(UserPreferences.playbackTimeAboveRight, PlaybackTimeSlot.none);
      await prefs.set(UserPreferences.playbackTimeBelowLeft, PlaybackTimeSlot.elapsed);
      await prefs.set(UserPreferences.playbackTimeBelowCenter, PlaybackTimeSlot.none);
      await prefs.set(UserPreferences.playbackTimeBelowRight, PlaybackTimeSlot.timeRemaining);
    }
    final sync = GetIt.instance<PluginSyncService>();
    if (sync.pluginAvailable) {
      sync.pushSettings(GetIt.instance<MediaServerClient>());
    }
  }
}

/// The three ambiances side by side, the active one ringed.
class AmbianceSection extends StatelessWidget {
  final UserPreferences prefs;
  final bool autofocus;

  const AmbianceSection({super.key, required this.prefs, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = Ambiance.current(prefs);
    final controller = AppThemeScope.of(context);
    String title(Ambiance a) => switch (a) {
      Ambiance.vjod => l10n.ambianceVjod,
      Ambiance.ecrin => l10n.ambianceEcrin,
      Ambiance.classic => l10n.ambianceClassic,
    };
    String subtitle(Ambiance a) => switch (a) {
      Ambiance.vjod => l10n.ambianceVjodSubtitle,
      Ambiance.ecrin => l10n.ambianceEcrinSubtitle,
      Ambiance.classic => l10n.ambianceClassicSubtitle,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.ambianceIntro,
            style: TextStyle(
              color: AppColorScheme.onSurface.withValues(alpha: 0.65),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          for (final (i, a) in Ambiance.values.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AmbianceCard(
                title: title(a),
                subtitle: subtitle(a),
                selected: a == current,
                autofocus: autofocus && i == 0,
                onTap: () => a.apply(prefs, controller),
              ),
            ),
        ],
      ),
    );
  }
}

class _AmbianceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _AmbianceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_AmbianceCard> createState() => _AmbianceCardState();
}

class _AmbianceCardState extends State<_AmbianceCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ink = AppColorScheme.onSurface;
    return Material(
      color: AppColorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(12),
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? ink
                  : widget.selected
                  ? AppColorScheme.accent
                  : Colors.transparent,
              width: _focused ? 3 : 2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.65),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.selected)
                Icon(Icons.check_circle, color: AppColorScheme.accent),
            ],
          ),
        ),
      ),
    );
  }
}
