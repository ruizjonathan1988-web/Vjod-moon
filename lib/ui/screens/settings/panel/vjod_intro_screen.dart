part of '../settings_side_panel.dart';

/// Réglages → Apparence → Ouverture de VJOD: which opening plays at launch
/// (or none). Choosing one plays it at once, with its sound.
class _VjodIntroScreen extends StatefulWidget {
  const _VjodIntroScreen();

  @override
  State<_VjodIntroScreen> createState() => _VjodIntroScreenState();
}

class _VjodIntroScreenState extends State<_VjodIntroScreen> {
  VjodIntroStyle? _current = VjodIntroStyle.fallback;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(VjodIntroStyle.current().then((s) {
      if (mounted) setState(() {
        _current = s;
        _loaded = true;
      });
    }));
  }

  Future<void> _choose(VjodIntroStyle? style) async {
    await VjodIntroStyle.choose(style);
    if (!mounted) return;
    setState(() => _current = style);
    if (style != null) await _preview(style);
  }

  Future<void> _preview(VjodIntroStyle style) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => Scaffold(
          backgroundColor: const Color(0xFF040404),
          body: VjodIntro(
            style: style,
            onDone: () {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            },
          ),
        ),
      ),
    );
  }

  Widget _tile(VjodIntroStyle? style, {bool autofocus = false}) {
    final selected = _loaded && _current == style;
    return _TvSettingsListTile(
      autofocus: autofocus,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
      title: Text(style == null
          ? 'Aucune'
          : style == VjodIntroStyle.fallback
          ? '${style.label} (par défaut)'
          : style.label),
      subtitle: Text(style?.description ?? 'VJOD s\'ouvre directement, sans animation ni son.'),
      trailing: style == null
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Voir',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => unawaited(_preview(style)),
            ),
      onTap: () => unawaited(_choose(style)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSettingsAppBar(context, const Text('Ouverture de VJOD')),
      body: ListView(
        children: [
          const _SectionHeader('Animation et son au lancement de VJOD'),
          adaptiveListSection(
            children: [
              for (final (i, s) in VjodIntroStyle.values.indexed) _tile(s, autofocus: i == 0),
              _tile(null),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Text(
              'Choisir une ouverture la joue tout de suite. Au lancement, n\'importe quelle touche ou un toucher la passe.',
            ),
          ),
        ],
      ),
    );
  }
}
