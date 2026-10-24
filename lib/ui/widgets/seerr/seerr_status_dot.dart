import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../l10n/app_localizations.dart';
import '../media_badge.dart';

export '../../../data/services/seerr/seerr_api_models.dart'
    show SeerrMediaStatus;

/// The colour a Seerr status carries wherever it is shown, so a card corner, a
/// season marker and a header pill never disagree about what a status means.
Color seerrStatusColor(int? status) => switch (status) {
      SeerrMediaStatus.available ||
      SeerrMediaStatus.partiallyAvailable =>
        AppColorScheme.statusAvailable,
      SeerrMediaStatus.processing => AppColorScheme.statusRequested,
      SeerrMediaStatus.pending => AppColorScheme.statusPending,
      SeerrMediaStatus.blocklisted || SeerrMediaStatus.deleted =>
        AppColorScheme.statusError,
      _ => AppColorScheme.onSurface.withValues(alpha: 0.54),
    };

/// The small circular Seerr status marker that sits on card corners.
///
/// Available is an outlined check, partially available is a filled dash, and
/// anything still on its way is an outlined clock in its own colour.
class SeerrStatusDot extends StatelessWidget {
  final int? status;
  final double size;

  const SeerrStatusDot({super.key, required this.status, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.6;

    if (status == SeerrMediaStatus.available) {
      return _circle(
        borderColor: AppColorScheme.statusAvailable,
        icon: Icon(
          Icons.check_rounded,
          size: iconSize,
          color: AppColorScheme.statusAvailable,
        ),
      );
    }

    if (status == SeerrMediaStatus.partiallyAvailable) {
      return _circle(
        fillColor: AppColorScheme.statusAvailable,
        icon: Icon(
          Icons.remove_rounded,
          size: size * 0.65,
          color: AppColorScheme.onBadge,
        ),
      );
    }

    final color = status == SeerrMediaStatus.processing
        ? AppColorScheme.statusRequested
        : AppColorScheme.statusPending;
    return _circle(
      borderColor: color,
      icon: Icon(Icons.schedule_rounded, size: iconSize, color: color),
    );
  }

  Widget _circle({
    required Widget icon,
    Color? fillColor,
    Color? borderColor,
  }) {
    final effectiveFillColor = fillColor ?? AppColorScheme.onBadge;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveFillColor,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          ThemeRegistry.active.borders.chipBorder.copyWith(
            color: borderColor ?? effectiveFillColor,
            width: 1.5,
          ),
        ),
        boxShadow: kMediaBadgeShadow,
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}

/// A status tag for a poster: an icon and a word, so the state reads at a
/// glance and without telling colours apart. Ready plays, requested waits,
/// on the way downloads, and a title not here yet offers to be requested.
class SeerrStatusTag extends StatelessWidget {
  /// Seerr's status, or null for a title Seerr knows nothing of.
  final int? status;

  /// Whether a title with no status can be asked for, which shows the
  /// request tag instead of nothing.
  final bool requestable;

  const SeerrStatusTag({super.key, this.status, this.requestable = false});

  /// Whether there is anything to show for [status] and [requestable].
  static bool shows(int? status, {bool requestable = false}) =>
      SeerrMediaStatus.hasDot(status) || requestable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (IconData? icon, String label, Color color) = switch (status) {
      SeerrMediaStatus.available => (
        Icons.play_arrow_rounded,
        l10n.seerrTagReady,
        AppColorScheme.statusAvailable,
      ),
      SeerrMediaStatus.partiallyAvailable => (
        Icons.play_arrow_rounded,
        l10n.seerrTagPartial,
        AppColorScheme.statusAvailable,
      ),
      SeerrMediaStatus.processing => (
        Icons.arrow_downward_rounded,
        l10n.seerrTagOnTheWay,
        AppColorScheme.statusDownloading,
      ),
      SeerrMediaStatus.pending => (
        Icons.schedule_rounded,
        l10n.seerrTagRequested,
        AppColorScheme.statusPending,
      ),
      _ => (null, l10n.seerrTagRequest, AppColorScheme.onSurface),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColorScheme.background.withValues(alpha: 0.85),
        borderRadius: AppRadius.circular(4),
        boxShadow: kMediaBadgeShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 7, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 13, color: color)
            else
              // To request: the one touch of the accent on a poster.
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: AppColorScheme.accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.add_rounded,
                  size: 11,
                  color: AppColorScheme.onAccent,
                ),
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
