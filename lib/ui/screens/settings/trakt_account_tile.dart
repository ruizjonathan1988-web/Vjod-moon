import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/seerr/for_you_service.dart';
import '../../../data/services/trakt/trakt_account.dart';
import '../../../data/services/trakt/trakt_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/settings/preference_tiles.dart';

/// The Trakt account in the settings: which one is linked, a tap to link
/// one or to let it go.
class TraktAccountTile extends StatelessWidget {
  const TraktAccountTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = GetIt.instance<TraktAccount>();
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final subtitle = account.isConnected
            ? l10n.traktConnectedAs(
                account.username.isEmpty ? 'Trakt' : account.username,
              )
            : l10n.traktNotConnected;
        return TvFocusHighlight(
          builder: (context, focused) => ListTile(
            leading: Icon(
              Icons.insights_rounded,
              color: focused ? AppColors.black.withValues(alpha: 0.54) : null,
            ),
            title: Text(
              account.isConnected ? l10n.traktDisconnect : l10n.traktConnect,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: focused
                    ? AppColors.black.withValues(alpha: 0.87)
                    : AppColorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: focused
                    ? AppColors.black.withValues(alpha: 0.54)
                    : AppColorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            onTap: () => account.isConnected
                ? _confirmDisconnect(context, account)
                : _connect(context),
          ),
        );
      },
    );
  }

  Future<void> _connect(BuildContext context) async {
    final linked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TraktConnectDialog(),
    );
    // The For You rows start over with what Trakt knows.
    if (linked ?? false) ForYouService.instance.clearCache();
  }

  Future<void> _confirmDisconnect(
    BuildContext context,
    TraktAccount account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.traktDisconnect),
        content: Text(l10n.traktDisconnectBody),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.traktDisconnect),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await account.disconnect();
      ForYouService.instance.clearCache();
    }
  }
}

/// Shows the code to type on Trakt and waits for the approval; closes with
/// true once the account is linked.
class _TraktConnectDialog extends StatefulWidget {
  const _TraktConnectDialog();

  @override
  State<_TraktConnectDialog> createState() => _TraktConnectDialogState();
}

class _TraktConnectDialogState extends State<_TraktConnectDialog> {
  final _account = GetIt.instance<TraktAccount>();
  TraktDeviceCode? _code;
  TraktAuthFailure? _failure;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _start() async {
    // A retry starts from a blank dialog; the first run already is one.
    if (_code != null || _failure != null) {
      setState(() {
        _code = null;
        _failure = null;
      });
    }
    try {
      final code = await _account.startConnecting();
      if (_closed) return;
      setState(() => _code = code);
      final linked = await _account.finishConnecting(
        code,
        isCancelled: () => _closed,
      );
      if (linked && mounted) Navigator.of(context).pop(true);
    } on TraktAuthException catch (e) {
      if (mounted) setState(() => _failure = e.reason);
    } catch (e) {
      debugPrint('[Trakt] Linking failed: $e');
      if (mounted) setState(() => _failure = TraktAuthFailure.refused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final code = _code;
    final failure = _failure;
    return AlertDialog(
      title: Text(l10n.traktConnect),
      content: SizedBox(
        width: 360,
        child: failure != null
            ? Text(switch (failure) {
                TraktAuthFailure.expired => l10n.traktCodeExpired,
                TraktAuthFailure.denied => l10n.traktDenied,
                TraktAuthFailure.refused => l10n.traktFailed,
              })
            : code == null
            ? const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              )
            : _CodeView(code: code),
      ),
      actions: [
        if (failure != null)
          TextButton(onPressed: _start, child: Text(l10n.retry)),
        if (code != null && failure == null && !PlatformDetection.isTV)
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(code.verificationUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(l10n.traktOpenPage),
          ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _CodeView extends StatelessWidget {
  const _CodeView({required this.code});

  final TraktDeviceCode code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final address = code.verificationUrl.replaceFirst(
      RegExp(r'^https?://'),
      '',
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.traktConnectSteps(address), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SelectableText(
          code.userCode,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        // On a TV the phone is the easy way to the page.
        if (PlatformDetection.isTV) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColorScheme.onSurface,
              borderRadius: AppRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: QrImageView(
              data: code.verificationUrl,
              version: QrVersions.auto,
              size: 120,
              backgroundColor: AppColorScheme.onSurface,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColorScheme.background,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColorScheme.background,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(l10n.traktWaiting)),
          ],
        ),
      ],
    );
  }
}
