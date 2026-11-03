part of '../settings_side_panel.dart';

class _AboutCategoryScreen extends StatelessWidget {
  const _AboutCategoryScreen();

  /// VJOD's own version: when this build was made, and from which commit.
  /// A build made by hand falls back to the Moonfin version it is based on.
  static String vjodVersion(BuildContext context) {
    final built = VjodBuild.builtAt;
    if (built == null) {
      return AppBeta.label(GetIt.instance<DeviceInfo>().appVersion);
    }
    final date = vjodBuildDate(context, built);
    return VjodBuild.commit.isEmpty ? date : '$date · ${VjodBuild.commit}';
  }

  @override
  Widget build(BuildContext context) {
    final appVersion = vjodVersion(context);
    final moonfinVersion = AppBeta.label(GetIt.instance<DeviceInfo>().appVersion);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.aboutTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Text(
              'VJOD ${VjodBuild.version}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              vjodText(
                context,
                fr: 'Version ${VjodBuild.version} du $appVersion',
                en: 'Version ${VjodBuild.version} of $appVersion',
                ru: 'Версия ${VjodBuild.version} от $appVersion',
                zh: '版本 ${VjodBuild.version} · $appVersion',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          // What this version brought, from vjod_changes.dart.
          if (vjodReleases.firstOrNull case final release?
              when release.version == VjodBuild.version) ...[
            const SizedBox(height: 16),
            const Divider(),
            _SectionHeader(vjodText(
              context,
              fr: 'Nouveautés de la ${release.version}',
              en: 'New in ${release.version}',
              ru: 'Новое в ${release.version}',
              zh: '${release.version} 新功能',
            )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final change in release.changes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $change', style: Theme.of(context).textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          _SectionHeader(l10n.settingsAppInfo),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                autofocus: true,
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.version),
                subtitle: Text('VJOD ${VjodBuild.version} · $appVersion'),
                trailing: const SizedBox.shrink(),
                onTap: () {},
              ),
              const _StartupTimelineTile(),
              const _TimingsTile(),
              const _ReplayTraceTile(),
              if (AppDistribution.supportsInAppUpdates)
                const _CheckForUpdatesTile(),
              // The admin's own devices take each new version first.
              if (AppDistribution.supportsInAppUpdates &&
                  AppUpdateService.isPersoBuild &&
                  (GetIt.instance<UserRepository>().currentUser?.isAdministrator ?? false))
                const _TrialChannelTile(),
              const _ReportProblemTile(),
              _TvSettingsListTile(
                leading: const Icon(Icons.code),
                title: Text(l10n.sourceCode),
                subtitle: const Text('github.com/ruizjonathan1988-web/Vjod-moon'),
                onTap: () => showQrOrLaunch(
                  context,
                  url: 'https://github.com/ruizjonathan1988-web/Vjod-moon',
                  title: l10n.sourceCode,
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.troubleshoot),
                title: Text(vjodText(
                  context,
                  fr: 'Diagnostic et journaux',
                  en: 'Diagnostics & Logging',
                  ru: 'Диагностика и журналы',
                  zh: '诊断与日志',
                )),
                subtitle: Text(vjodText(
                  context,
                  fr: 'Enregistrer ce qui se passe (lecture, connexion, réseau) et l\'envoyer au serveur',
                  en: 'Capture media, login and network logs and send them to the server as a report',
                  ru: 'Записать журналы воспроизведения, входа и сети и отправить их на сервер',
                  zh: '记录播放、登录和网络日志并发送到服务器',
                )),
                onTap: () => context.pushSettingsScreen(
                  const DiagnosticsSettingsScreen(),
                ),
              ),
              if (PlatformDetection.useDesktopUi)
                _TvSettingsListTile(
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(l10n.keyboardShortcutsTitle),
                  subtitle: Text(l10n.keyboardShortcutsSubtitle),
                  onTap: () => context.pushSettingsScreen(
                    const _KeyboardShortcutsScreen(),
                  ),
                ),
              _TvSettingsListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(l10n.runSetupAgain),
                // Asking again on purpose says more than the stored answers do,
                // so a deliberate re-run offers every question back.
                onTap: () {
                  GetIt.instance<SetupWizardGate>().beginRerun();
                  context.navigateTopLevel(Destinations.setup);
                },
              ),
            ],
          ),
          _SectionHeader(l10n.settingsLegal),
          adaptiveListSection(
            children: [
              // VJOD is a fork of Moonfin, under the GPL v2: the credit and the
              // licence stay.
              _TvSettingsListTile(
                leading: const Icon(Icons.description),
                title: Text(vjodText(
                  context,
                  fr: 'Basé sur Moonfin $moonfinVersion',
                  en: 'Based on Moonfin $moonfinVersion',
                  ru: 'На основе Moonfin $moonfinVersion',
                  zh: '基于 Moonfin $moonfinVersion',
                )),
                subtitle: Text(vjodText(
                  context,
                  fr: 'Logiciel libre sous licence GPL v2 · voir la licence',
                  en: 'Free software under the GPL v2 · see the licence',
                  ru: 'Свободное ПО под лицензией GPL v2 · открыть лицензию',
                  zh: 'GPL v2 许可的自由软件 · 查看许可证',
                )),
                onTap: () => showQrOrLaunch(
                  context,
                  url:
                      'https://github.com/ruizjonathan1988-web/Vjod-moon/blob/perso/LICENSE',
                  title: l10n.settingsLicenses,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Signaler un problème" on WhatsApp: the message comes prefilled with the
/// VJOD version and the device, and goes to the number set on the seedbox
/// (Ma TV), never written into this public app. On a TV, a QR code to scan
/// with the phone. Hidden while no number is set.
class _ReportProblemTile extends StatefulWidget {
  const _ReportProblemTile();

  @override
  State<_ReportProblemTile> createState() => _ReportProblemTileState();
}

class _ReportProblemTileState extends State<_ReportProblemTile> {
  @override
  void initState() {
    super.initState();
    unawaited(loadSupportNumber());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: vjodSupportNumber,
      builder: (context, number, _) {
        if (number == null) return const SizedBox.shrink();
        return _TvSettingsListTile(
          leading: const Icon(Icons.chat_rounded),
          title: Text(vjodText(
            context,
            fr: 'Signaler un problème',
            en: 'Report a problem',
            ru: 'Сообщить о проблеме',
            zh: '报告问题',
          )),
          subtitle: Text(vjodText(
            context,
            fr: 'Par WhatsApp, avec la version, l\'appareil et le dernier souci déjà indiqués',
            en: 'On WhatsApp, with the version, device and last problem already filled in',
            ru: 'В WhatsApp, версия, устройство и последняя проблема уже указаны',
            zh: '通过 WhatsApp，已附上版本、设备和最近的问题',
          )),
          onTap: () => unawaited(openReportProblem(context)),
        );
      },
    );
  }
}

/// « Versions d'essai » on this device: each new build arrives here first,
/// the household's devices get it once validated on the Ma TV page.
class _TrialChannelTile extends StatefulWidget {
  const _TrialChannelTile();

  @override
  State<_TrialChannelTile> createState() => _TrialChannelTileState();
}

class _TrialChannelTileState extends State<_TrialChannelTile> {
  AppUpdateService get _updates => GetIt.instance<AppUpdateService>();

  @override
  Widget build(BuildContext context) {
    final on = _updates.betaChannel;
    return _TvSettingsListTile(
      leading: const Icon(Icons.science_outlined),
      title: Text(vjodText(
        context,
        fr: 'Versions d\'essai sur cet appareil',
        en: 'Trial versions on this device',
        ru: 'Тестовые версии на этом устройстве',
        zh: '在此设备上接收测试版',
      )),
      subtitle: Text(vjodText(
        context,
        fr: on
            ? 'Chaque nouvelle version arrive ici d\'abord ; les autres appareils la reçoivent quand tu la valides sur la page Ma TV'
            : 'Les autres appareils : seulement les versions validées',
        en: on
            ? 'Each new version comes here first; the other devices get it once you validate it on the Ma TV page'
            : 'Validated versions only',
        ru: on ? 'Новые версии сначала приходят сюда' : 'Только проверенные версии',
        zh: on ? '新版本先到这里' : '仅接收已验证的版本',
      )),
      trailing: Switch(value: on, onChanged: (v) => unawaited(_set(v))),
      onTap: () => unawaited(_set(!on)),
    );
  }

  Future<void> _set(bool v) async {
    await _updates.setBetaChannel(v);
    if (mounted) setState(() {});
    if (v && mounted) await checkAndShowUpdateResult(context);
  }
}

class _CheckForUpdatesTile extends StatefulWidget {
  const _CheckForUpdatesTile();

  @override
  State<_CheckForUpdatesTile> createState() => _CheckForUpdatesTileState();
}

class _CheckForUpdatesTileState extends State<_CheckForUpdatesTile> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await checkAndShowUpdateResult(context);
    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _TvSettingsListTile(
      leading: _checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      title: Text(l10n.settingsCheckForUpdates),
      subtitle: Text(vjodText(
        context,
        fr: 'Rechercher la dernière version de VJOD',
        en: 'Look for the latest VJOD version',
        ru: 'Найти последнюю версию VJOD',
        zh: '查找最新版本的 VJOD',
      )),
      onTap: _checking ? null : _check,
    );
  }
}

/// VJOD 4.20: how fast each service answers on this device.
class _TimingsTile extends StatelessWidget {
  const _TimingsTile();

  @override
  Widget build(BuildContext context) {
    final lines = VjodTimings.lines();
    return _TvSettingsListTile(
      leading: const Icon(Icons.speed_rounded),
      title: const Text('Temps de réponse'),
      subtitle: Text(lines.isEmpty ? 'Pas encore mesuré : utilise VJOD un moment.' : lines.join('\n')),
      trailing: const SizedBox.shrink(),
      onTap: () {},
    );
  }
}

/// VJOD 4.22: what the Home's Replay row did on this device, and whether it
/// is on the Home right now.
class _ReplayTraceTile extends StatelessWidget {
  const _ReplayTraceTile();

  @override
  Widget build(BuildContext context) {
    final getIt = GetIt.instance;
    String now = 'Accueil pas encore ouvert';
    if (getIt.isRegistered<HomeViewModel>()) {
      final rows = getIt<HomeViewModel>().rows;
      final i = rows.indexWhere((r) => r.id == HomeViewModel.replayRowId);
      final vm = getIt<HomeViewModel>();
      now = i < 0
          ? (vm.replayBuilt
                ? 'Prête mais cachée par un filtre de l\u2019Accueil'
                : 'Absente de l\u2019Accueil en ce moment (${rows.length} rangées)')
          : 'Sur l\u2019Accueil : rangée ${i + 1} sur ${rows.length}, ${rows[i].items.length} tuiles';
    }
    final lines = ReplayTrace.lines();
    return _TvSettingsListTile(
      leading: const Icon(Icons.replay_rounded),
      title: const Text('Rangée Replay'),
      subtitle: Text([now, if (lines.isEmpty) 'Pas encore demandée depuis le lancement.' else ...lines].join('\n')),
      trailing: const SizedBox.shrink(),
      onTap: () {},
    );
  }
}

/// How long the last launch took, step by step (see StartupTimeline).
class _StartupTimelineTile extends StatelessWidget {
  const _StartupTimelineTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(String, int)>>(
      future: StartupTimeline.last(),
      builder: (context, snap) {
        final steps = snap.data ?? const <(String, int)>[];
        return _TvSettingsListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(steps.isEmpty
              ? 'Démarrage précédent'
              : 'Démarrage précédent : ${StartupTimeline.seconds(steps.last.$2)}'),
          subtitle: Text(steps.isEmpty
              ? 'Pas encore mesuré : relance VJOD pour le voir.'
              : [
                  for (final s in steps)
                    '${StartupTimeline.seconds(s.$2)}  ${s.$1}',
                ].join('\n')),
          trailing: const SizedBox.shrink(),
          onTap: () {},
        );
      },
    );
  }
}
