import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/services/app_update_service.dart';
import '../../l10n/app_localizations.dart';
import '../../util/platform_detection.dart';
import '../../util/vjod_text.dart';
import '../navigation/app_router.dart' show appRouter;
import '../screensaver/screensaver_controller.dart';
import 'app_update_dialog.dart';
import 'status_banner_pill.dart';

/// Floating glass pill announcing a newer GitHub release. Mirrors the offline
/// banner: slides in, auto-dismisses on a countdown, and stays non-focusable
/// on TV so it never steals d-pad focus from the content underneath.
class AppUpdateBanner extends StatefulWidget {
  /// Overrides the update lookup in tests. Defaults to the registered
  /// [AppUpdateService]'s cooldown-respecting check.
  final Future<DesktopUpdateInfo?> Function()? checkForUpdate;

  const AppUpdateBanner({super.key, this.checkForUpdate});

  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _autoDismissDuration = Duration(seconds: 7);

  // Built in initState, not as field initializers: a banner that never becomes
  // visible would otherwise run them from dispose, and creating a ticker on a
  // deactivated element throws.
  late final AnimationController _entrance;
  late final CurvedAnimation _entranceCurve;

  DesktopUpdateInfo? _update;
  bool _dismissed = false;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _entranceCurve = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
    });
  }

  // An app on a TV mostly comes back from the background rather than
  // starting again: each return looks for an update too (an hour apart at
  // most, the service keeps the pace).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  bool _checking = false;
  bool _installing = false;
  DesktopUpdateInfo? _waiting;
  Timer? _waitTimer;

  /// Above the routes, where dialogs can open (this banner sits over the
  /// navigator, where they can't: on TV the offer never showed).
  BuildContext get _dialogContext =>
      appRouter.routerDelegate.navigatorKey.currentContext ?? context;

  static bool get _playing {
    final getIt = GetIt.instance;
    return getIt.isRegistered<ScreensaverController>() &&
        getIt<ScreensaverController>().playbackActive;
  }

  /// This fork's builds install themselves at once, but never over a film or
  /// a channel being watched: the update waits for the player to close.
  Future<void> _installNow(DesktopUpdateInfo update) async {
    if (_installing) return;
    if (_playing) {
      _waiting = update;
      _waitTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        final w = _waiting;
        if (w == null || _playing || !mounted) return;
        _waiting = null;
        _waitTimer?.cancel();
        _waitTimer = null;
        unawaited(_installNow(w));
      });
      return;
    }
    _installing = true;
    try {
      await installAppUpdateNow(_dialogContext, update);
    } finally {
      _installing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waitTimer?.cancel();
    _autoDismissTimer?.cancel();
    _entranceCurve.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _installing) return;
    _checking = true;
    try {
      final check =
          widget.checkForUpdate ??
          GetIt.instance<AppUpdateService>().checkForUpdateIfDue;
      final update = await check();
      if (!mounted || update == null) return;
      // This fork's APK updates itself on opening, without asking first.
      if (update.builtAt != null && installsAppUpdateInApp(update)) {
        await _installNow(update);
        return;
      }
      // On TV the banner can't be reached with the remote, so the update
      // offer opens straight away as a dialog the d-pad can use, with the
      // in-app install inside it.
      if (PlatformDetection.useLeanbackUi) {
        await showAppUpdateDialog(_dialogContext, update);
        if (mounted) setState(() => _dismissed = true);
        return;
      }
      _dismissed = false;
      setState(() => _update = update);
      _entrance.forward();
      _autoDismissTimer = Timer(_autoDismissDuration, _dismiss);
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  Future<void> _dismiss() async {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    await _entrance.reverse();
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    if (update == null || _dismissed) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final isTv = PlatformDetection.useLeanbackUi;
    final tint = AppColorScheme.statusAvailable;

    final pill = StatusBannerPill(
      icon: Icons.system_update_alt_rounded,
      tint: tint,
      title: update.builtAt != null
          ? vjodText(
              context,
              fr: 'Nouvelle version de VJOD · ${vjodBuildDate(context, update.builtAt!)}',
              en: 'New VJOD version · ${vjodBuildDate(context, update.builtAt!)}',
              ru: 'Новая версия VJOD · ${vjodBuildDate(context, update.builtAt!)}',
              zh: 'VJOD 新版本 · ${vjodBuildDate(context, update.builtAt!)}',
            )
          : l10n.updateAvailableVersion(update.version),
      trailing: [
        if (isTv)
          BannerCountdownBar(duration: _autoDismissDuration, color: tint)
        else ...[
          BannerActionCapsule(
            label: l10n.download,
            tint: tint,
            onTap: () {
              // Downloads and installs inside the app, rather than sending
              // the viewer to the browser.
              unawaited(showAppUpdateDialog(_dialogContext, update));
              unawaited(_dismiss());
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: _dismiss,
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColorScheme.onSurface.withValues(alpha: 0.45),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ],
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -0.4),
        end: Offset.zero,
      ).animate(_entranceCurve),
      child: FadeTransition(
        opacity: _entranceCurve,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: pill,
            ),
          ),
        ),
      ),
    );
  }
}
