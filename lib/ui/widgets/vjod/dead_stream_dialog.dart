import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../util/focus/key_event_utils.dart';
import '../overlay_sheet.dart';

/// What the viewer chose when a provider's stream stopped answering.
enum DeadStreamChoice { request, close }

/// Says a title streamed from the IPTV provider no longer plays, and offers
/// to ask for it through Seerr so the server gets a file of its own.
Future<DeadStreamChoice> showDeadStreamDialog(
  BuildContext context,
  AggregatedItem item,
) async {
  final requestFocus = FocusNode(debugLabel: 'DeadStreamRequest');
  try {
    final result = await OverlaySheetController.show<DeadStreamChoice>(
      context,
      initialFocusNode: requestFocus,
      barrierDismissible: false,
      builder: (sheetContext) => _DeadStreamContent(
        title: item.type == 'Episode'
            ? (item.seriesName ?? item.name)
            : item.name,
        isEpisode: item.type == 'Episode',
        requestFocus: requestFocus,
        onChoose: (choice) => OverlaySheetController.closeAdaptive(
          sheetContext,
          result: choice,
        ),
      ),
    );
    return result ?? DeadStreamChoice.close;
  } finally {
    requestFocus.dispose();
  }
}

/// Asks Seerr for the title behind [item]: the film itself, or for an
/// episode the season it belongs to. Returns what to tell the viewer.
Future<({bool ok, String message})> requestDeadStreamTitle(
  AggregatedItem item,
) async {
  try {
    final repo = await GetIt.instance.getAsync<SeerrRepository>();
    await repo.ensureInitialized();
    if (!repo.isAvailable) {
      return (ok: false, message: 'Seerr n’est pas disponible pour le moment.');
    }
    if (item.type == 'Movie') {
      final tmdb = int.tryParse(item.tmdbId ?? '');
      if (tmdb == null) {
        return (ok: false, message: 'Titre introuvable sur Seerr.');
      }
      await repo.createRequest(mediaId: tmdb, mediaType: 'movie');
      return (ok: true, message: 'Demande envoyée.');
    }
    // An episode or a series: the request goes in for the series, limited to
    // the season that stopped playing when there is one.
    var seriesTmdb = item.type == 'Series' ? item.tmdbId : null;
    final seriesId = item.seriesId;
    if (seriesTmdb == null && seriesId != null) {
      final series = await GetIt.instance<MediaServerClient>().itemsApi
          .getItem(seriesId, fields: 'ProviderIds');
      final ids = series['ProviderIds'];
      final tmdb = ids is Map ? (ids['Tmdb'] ?? ids['tmdb']) : null;
      seriesTmdb = tmdb?.toString();
    }
    final tmdb = int.tryParse(seriesTmdb ?? '');
    if (tmdb == null) {
      return (ok: false, message: 'Série introuvable sur Seerr.');
    }
    final season = item.type == 'Episode' ? item.parentIndexNumber : null;
    await repo.createRequest(
      mediaId: tmdb,
      mediaType: 'tv',
      seasons: season != null && season > 0 ? [season] : null,
      allSeasons: season == null || season <= 0,
    );
    return (
      ok: true,
      message: season != null && season > 0
          ? 'Saison $season demandée.'
          : 'Série demandée.',
    );
  } catch (_) {
    return (ok: false, message: 'La demande n’a pas pu partir. Réessayez depuis la fiche.');
  }
}

class _DeadStreamContent extends StatelessWidget {
  final String title;
  final bool isEpisode;
  final FocusNode requestFocus;
  final ValueChanged<DeadStreamChoice> onChoose;

  const _DeadStreamContent({
    required this.title,
    required this.isEpisode,
    required this.requestFocus,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    final glass = AppColorScheme.isGlass;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: glass ? const Color(0xD90E1117) : AppColorScheme.surface,
          borderRadius: AppRadius.circular(glass ? 20 : 16),
          border: glass
              ? const Border.fromBorderSide(
                  BorderSide(color: Color(0x33FFFFFF), width: 1),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.portable_wifi_off_rounded,
              size: 40,
              color: Color(0xFF9CC2FF),
            ),
            const SizedBox(height: 20),
            Text(
              'Ce flux ne répond plus',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColorScheme.onSurface,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Le fournisseur ne diffuse plus « $title » ou ne répond pas '
              'pour l’instant. Demandez-le pour l’avoir en fichier sur le '
              'serveur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppColorScheme.onSurface.withValues(alpha: 0.7),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _DialogButton(
                  label: isEpisode ? 'Demander la saison' : 'Demander ce titre',
                  icon: Icons.add_rounded,
                  focusNode: requestFocus,
                  autofocus: true,
                  primary: true,
                  onPressed: () => onChoose(DeadStreamChoice.request),
                ),
                _DialogButton(
                  label: 'Fermer',
                  onPressed: () => onChoose(DeadStreamChoice.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool primary;
  final VoidCallback onPressed;

  const _DialogButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.primary = false,
  });

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final filled = _focused || widget.primary;
    final background = _focused
        ? AppColorScheme.onSurface
        : widget.primary
        ? AppColorScheme.accent
        : AppColorScheme.onSurface.withValues(alpha: 0.1);
    final foreground = _focused
        ? AppColors.black
        : filled
        ? Colors.white
        : AppColorScheme.onSurface;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) => handleOneShotSelect(event, widget.onPressed),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: foreground),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
