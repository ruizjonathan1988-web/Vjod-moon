import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/viewmodels/seerr_media_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../track_selector_dialog.dart';
import 'seerr_request_action.dart';
import 'seerr_tv_controls.dart';

/// Lists the open requests on a title so a request manager can approve or
/// decline each one.
///
/// A sheet rather than a pair of buttons in the action row, because approve
/// and decline belong to a request rather than to the title, and a title can
/// carry several.
void showSeerrManageRequestsSheet({
  required BuildContext context,
  required SeerrMediaDetailViewModel vm,
}) {
  showStyledPlayerDialog<void>(
    context,
    title: AppLocalizations.of(context).manageRequests,
    builder: (_) => _SeerrManageRequestsSheet(vm: vm),
  );
}

class _SeerrManageRequestsSheet extends StatefulWidget {
  final SeerrMediaDetailViewModel vm;

  const _SeerrManageRequestsSheet({required this.vm});

  @override
  State<_SeerrManageRequestsSheet> createState() =>
      _SeerrManageRequestsSheetState();
}

class _SeerrManageRequestsSheetState extends State<_SeerrManageRequestsSheet> {
  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // Once nothing is left to manage, the sheet has nothing to show.
    if (widget.vm.state.allActiveRequests.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  Future<void> _openInService(BuildContext context, SeerrRequest request) async {
    final l10n = AppLocalizations.of(context);
    final url = await widget.vm.serviceUrlForRequest(request);
    if (!context.mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.seerrServiceLinkUnavailable)),
      );
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.vm.state;
    // Pending requests first (to approve or decline), then the approved ones
    // still being fetched, so a request stuck for a while can be kicked off
    // again towards Radarr/Sonarr.
    final requests = state.allActiveRequests;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final request in requests) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              seerrRequestedByLabel(request, l10n),
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (request.status == SeerrRequest.statusPending)
            Row(
              children: [
                Expanded(
                  child: SeerrDialogButton(
                    label: l10n.approve,
                    icon: Icons.check_circle_outline,
                    primary: true,
                    primaryColor: Colors.green[700],
                    onPressed: state.isRequesting
                        ? null
                        : () => widget.vm.approveRequest(request.id),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SeerrDialogButton(
                    label: l10n.declineAction,
                    icon: Icons.cancel_outlined,
                    foreground: Colors.red[300],
                    onPressed: state.isRequesting
                        ? null
                        : () => widget.vm.declineRequest(request.id),
                  ),
                ),
              ],
            ),
          if (request.status == SeerrRequest.statusPending)
            const SizedBox(height: 10),
          // Re-sends the request so Radarr/Sonarr searches again.
          SeerrDialogButton(
            label: l10n.seerrRetrySearch,
            icon: Icons.search_rounded,
            onPressed:
                state.isRequesting ? null : () => widget.vm.retryRequest(request.id),
          ),
          const SizedBox(height: 10),
          // Opens the title straight in Radarr or Sonarr, like Seerr does.
          SeerrDialogButton(
            label: request.type == 'movie'
                ? l10n.seerrOpenInRadarr
                : l10n.seerrOpenInSonarr,
            icon: Icons.open_in_new_rounded,
            onPressed: () => _openInService(context, request),
          ),
        ],
      ],
    );
  }
}
