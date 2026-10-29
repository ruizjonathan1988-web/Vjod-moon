import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_error.dart';
import '../../../data/services/vjod/xtream_catalog.dart' show languageName;
import '../../../l10n/app_localizations.dart';
import '../floating_notification.dart';
import '../focusable_dialog_row.dart';
import '../track_selector_dialog.dart';
import '../vjod/provider_play.dart';

/// What the viewer picked on the For You sheet.
enum _ForYouChoice {
  playIptv,
  request,
  requestAllSeasons,
  requestRussian,
  details,
  notInterested,
  editTaste,
}

/// Offers to request a For You pick straight away, with the full page one
/// row down for anyone who wants to read about it first.
///
/// The request goes first and holds focus, so on a remote a pick is two OK
/// presses from downloading: one to open the sheet, one to confirm. Series
/// start with season 1 on its own, since asking for every season of a long
/// show is a lot to download on a hunch.
///
/// [onRequested] runs once Seerr accepted the request, so the row can drop
/// the card. [openDetails] opens the regular Seerr page.
Future<void> showSeerrForYouSheet({
  required BuildContext context,
  required AggregatedItem item,
  required String? because,
  required VoidCallback openDetails,
  VoidCallback? onRequested,
  Future<void> Function()? onNotInterested,
  VoidCallback? onEditTaste,
}) async {
  final l10n = AppLocalizations.of(context);
  final isTv = (item.rawData['SeerrMediaType'] as String?) == 'tv';
  final title = item.name;
  // The provider has it (the "IPTV" tag on the poster): watching it now comes
  // first, before asking for a download.
  final iptv = providerCopyNow(series: isTv, tmdbId: item.id);
  final iptvLang = iptv == null || iptv.tag.isEmpty ? '' : languageName(iptv.tag);

  final choice = await showStyledPlayerDialog<_ForYouChoice>(
    context,
    title: title,
    subtitle: because == null || because.isEmpty
        ? null
        : l10n.seerrForYouBecause(because),
    builder: (dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (iptv != null)
          FocusableDialogRow(
            icon: Icons.play_arrow_rounded,
            label: iptvLang.isEmpty
                ? 'Regarder maintenant (IPTV)'
                : 'Regarder maintenant (IPTV · $iptvLang)',
            autofocus: true,
            onTap: () => Navigator.pop(dialogContext, _ForYouChoice.playIptv),
          ),
        FocusableDialogRow(
          icon: Icons.download_rounded,
          label: isTv
              ? l10n.seerrForYouRequestFirstSeason
              : l10n.seerrForYouRequestMovie,
          autofocus: iptv == null,
          onTap: () => Navigator.pop(dialogContext, _ForYouChoice.request),
        ),
        if (isTv)
          FocusableDialogRow(
            icon: Icons.playlist_add_rounded,
            label: l10n.seerrForYouRequestAllSeasons,
            onTap: () =>
                Navigator.pop(dialogContext, _ForYouChoice.requestAllSeasons),
          ),
        FocusableDialogRow(
          icon: Icons.translate_rounded,
          label: l10n.request4k,
          onTap: () =>
              Navigator.pop(dialogContext, _ForYouChoice.requestRussian),
        ),
        FocusableDialogRow(
          icon: Icons.info_outline_rounded,
          label: l10n.seerrForYouOpenDetails,
          onTap: () => Navigator.pop(dialogContext, _ForYouChoice.details),
        ),
        if (onNotInterested != null)
          FocusableDialogRow(
            icon: Icons.thumb_down_alt_outlined,
            label: l10n.notInterested,
            onTap: () =>
                Navigator.pop(dialogContext, _ForYouChoice.notInterested),
          ),
        if (onEditTaste != null)
          FocusableDialogRow(
            icon: Icons.tune_rounded,
            label: l10n.tasteEdit,
            onTap: () => Navigator.pop(dialogContext, _ForYouChoice.editTaste),
          ),
      ],
    ),
  );

  if (choice == null || !context.mounted) return;
  if (choice == _ForYouChoice.playIptv) {
    if (!playProviderCopy(context, series: isTv, tmdbId: item.id)) openDetails();
    return;
  }
  if (choice == _ForYouChoice.details) {
    openDetails();
    return;
  }
  if (choice == _ForYouChoice.editTaste) {
    onEditTaste?.call();
    return;
  }
  if (choice == _ForYouChoice.notInterested) {
    // Notify first: the context may belong to the card about to go.
    FloatingNotification.show(
      context,
      l10n.notInterestedDone,
      l10n.notInterestedDoneBody(title),
      null,
      icon: Icons.thumb_down_alt_outlined,
    );
    await onNotInterested?.call();
    return;
  }

  final tmdbId = int.tryParse(item.id);
  if (tmdbId == null) {
    openDetails();
    return;
  }

  try {
    final repo = await GetIt.instance.getAsync<SeerrRepository>();
    await repo.createRequest(
      mediaId: tmdbId,
      mediaType: isTv ? 'tv' : 'movie',
      seasons: isTv && choice != _ForYouChoice.requestAllSeasons
          ? const [1]
          : null,
      allSeasons: isTv && choice == _ForYouChoice.requestAllSeasons,
      is4k: choice == _ForYouChoice.requestRussian,
    );
    // Notify before dropping the card: the context may belong to it.
    if (context.mounted) {
      FloatingNotification.show(
        context,
        l10n.seerrForYouRequestSent,
        l10n.seerrForYouRequestSentBody(title),
        null,
        icon: Icons.check_circle_outline_rounded,
      );
    }
    onRequested?.call();
  } on SeerrRequestException catch (e) {
    if (context.mounted) _showFailure(context, l10n, title, e);
    if (e.kind == SeerrRequestErrorKind.duplicate) {
      // Someone got there first. Either way it's coming, so the card can go.
      onRequested?.call();
    }
  } catch (e) {
    debugPrint('[ForYou] Request for $title failed: $e');
    if (!context.mounted) return;
    FloatingNotification.show(
      context,
      l10n.seerrForYouRequestFailed,
      title,
      null,
      icon: Icons.error_outline_rounded,
    );
  }
}

void _showFailure(
  BuildContext context,
  AppLocalizations l10n,
  String title,
  SeerrRequestException e,
) {
  FloatingNotification.show(
    context,
    e.kind == SeerrRequestErrorKind.duplicate
        ? l10n.seerrRequestedStatus
        : l10n.seerrForYouRequestFailed,
    switch (e.kind) {
      SeerrRequestErrorKind.duplicate =>
        l10n.seerrForYouAlreadyRequested(title),
      SeerrRequestErrorKind.quotaExceeded => l10n.requestErrorQuota,
      SeerrRequestErrorKind.blocklisted => l10n.requestErrorBlocklisted,
      SeerrRequestErrorKind.permission => l10n.requestErrorPermission,
      _ => e.serverMessage ?? title,
    },
    null,
    icon: Icons.error_outline_rounded,
  );
}
