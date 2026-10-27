import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/vjod/provider_catalog_access.dart';
import '../../../data/services/vjod/tv_playlists.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/seerr_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../../util/tv_app_launcher.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/vjod/vjod_widgets.dart';

/// The TV tab: it brings the viewer to an external IPTV player (TiviMate and
/// the like) and keeps the legal M3U/Xtream links they found, ready to copy
/// into that player once. VJOD does not play live TV itself here.
class VjodTvLaunchScreen extends StatefulWidget {
  /// A playlist link shared from another app, to offer saving on arrival.
  final String? addUrl;

  const VjodTvLaunchScreen({super.key, this.addUrl});

  @override
  State<VjodTvLaunchScreen> createState() => _VjodTvLaunchScreenState();
}

class _VjodTvLaunchScreenState extends State<VjodTvLaunchScreen> {
  SeerrPreferences get _prefs => GetIt.instance<SeerrPreferences>();

  List<TvPlaylist> _playlists = const [];
  TvApp _app = TvApp.tivimate;
  bool _installed = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _playlists = TvPlaylists.decode(_prefs.vjodTvPlaylistsJson);
    _app = TvApp.byId(_prefs.vjodTvApp.isEmpty ? null : _prefs.vjodTvApp);
    _languages = _prefs.vjodProviderLanguages;
    _refreshInstalled();
    _loadLanguageCounts();
    final shared = widget.addUrl;
    if (shared != null && shared.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptShared(shared));
    }
  }

  @override
  void didUpdateWidget(VjodTvLaunchScreen old) {
    super.didUpdateWidget(old);
    final shared = widget.addUrl;
    if (shared != null && shared.isNotEmpty && shared != old.addUrl) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptShared(shared));
    }
  }

  Future<void> _promptShared(String url) async {
    final result = await showDialog<TvPlaylist>(
      context: context,
      builder: (_) => _PlaylistDialog(seedUrl: url),
    );
    if (result == null) return;
    setState(() => _playlists = [..._playlists, result]);
    await _savePlaylists();
  }

  Future<void> _refreshInstalled() async {
    final installed = await TvAppLauncher.isInstalled(_app);
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _checking = false;
    });
  }

  Future<void> _pickApp(TvApp app) async {
    setState(() {
      _app = app;
      _checking = true;
    });
    await _prefs.setVjodTvApp(app.id);
    await _refreshInstalled();
  }

  Future<void> _open() async {
    final ok = await TvAppLauncher.launch(_app);
    if (!ok && mounted) {
      await TvAppLauncher.openStore(_app);
    }
  }

  Future<void> _savePlaylists() async {
    await _prefs.setVjodTvPlaylistsJson(TvPlaylists.encode(_playlists));
    _loadLanguageCounts();
  }

  /// The languages this profile watches the provider's films and series in,
  /// most wanted first.
  List<String> _languages = const [];

  /// Every language tag the provider has, with how many titles; null while
  /// its catalogue is being read or when there is no Xtream source.
  List<MapEntry<String, int>>? _languageCounts;
  bool _languagesLoading = false;

  Future<void> _loadLanguageCounts() async {
    final catalog = currentProviderCatalog();
    // No setState before the first await: this also runs from initState,
    // whose first build reads these fields as they are.
    await Future<void>.value();
    if (!mounted) return;
    if (catalog == null) {
      setState(() => _languageCounts = null);
      return;
    }
    setState(() => _languagesLoading = true);
    try {
      final counts = await catalog.languageCounts();
      if (mounted) setState(() => _languageCounts = counts);
    } catch (_) {
      // Left on the usual languages; the provider may answer next time.
    } finally {
      if (mounted) setState(() => _languagesLoading = false);
    }
  }

  Future<void> _toggleLanguage(String tag) async {
    final next = [..._languages];
    if (!next.remove(tag)) next.add(tag);
    setState(() => _languages = next);
    await _prefs.setVjodProviderLanguages(next);
  }

  Widget _languagesSection(double s) {
    final counts = {for (final e in _languageCounts ?? const []) e.key: e.value};
    final tags = <String>[
      ..._languages,
      for (final e in _languageCounts ?? const <MapEntry<String, int>>[])
        if (!_languages.contains(e.key)) e.key,
      if (_languageCounts == null)
        for (final t in const ['FR', 'EN', 'RU', 'CN'])
          if (!_languages.contains(t)) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Langues des films et séries', style: vjodDisplay(26 * s)),
        SizedBox(height: 6 * s),
        Text(
          _languages.isEmpty
              ? "Choisis les langues de ce profil : les versions du fournisseur "
                    "dans ces langues passent en premier dans la recherche et "
                    "se lancent d'un clic sur les fiches. Rien de coché : "
                    "toutes les langues, au choix à chaque fois."
              : "Ce profil regarde d'abord en ${_languages.join(', puis ')}. "
                    "Les autres langues restent proposées par un appui long "
                    "sur « Regarder · IPTV ».",
          style: TextStyle(
            color: vjodInk.withValues(alpha: 0.55),
            fontSize: 15 * s,
          ),
        ),
        SizedBox(height: 12 * s),
        if (_languagesLoading && _languageCounts == null)
          Padding(
            padding: EdgeInsets.only(bottom: 10 * s),
            child: Text(
              'Lecture du catalogue du fournisseur…',
              style: TextStyle(
                color: vjodInk.withValues(alpha: 0.5),
                fontSize: 14 * s,
              ),
            ),
          ),
        Wrap(
          spacing: 10 * s,
          runSpacing: 10 * s,
          children: [
            for (final tag in tags)
              VjodFocusable(
                onTap: () => _toggleLanguage(tag),
                builder: (context, focused) {
                  final rank = _languages.indexOf(tag);
                  final on = rank >= 0;
                  final count = counts[tag];
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16 * s,
                      vertical: 8 * s,
                    ),
                    decoration: BoxDecoration(
                      color: on ? vjodInk : vjodButton,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: vjodFocusRing(s * 0.6, on: focused),
                    ),
                    child: Text(
                      [
                        if (on) '${rank + 1}.',
                        tag,
                        if (count != null) '($count)',
                      ].join(' '),
                      style: TextStyle(
                        color: on ? vjodPage : vjodInk,
                        fontSize: 16 * s,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _addOrEdit([TvPlaylist? existing]) async {
    final result = await showDialog<TvPlaylist>(
      context: context,
      builder: (_) => _PlaylistDialog(existing: existing),
    );
    if (result == null) return;
    setState(() {
      final i = _playlists.indexWhere((p) => p.id == result.id);
      if (i >= 0) {
        _playlists = [..._playlists]..[i] = result;
      } else {
        _playlists = [..._playlists, result];
      }
    });
    await _savePlaylists();
  }

  Future<void> _remove(TvPlaylist p) async {
    setState(() => _playlists = [
          for (final e in _playlists)
            if (e.id != p.id) e,
        ]);
    await _savePlaylists();
  }

  Future<void> _copy(TvPlaylist p) async {
    final link = p.m3uUrl;
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.vjodTvCopied), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.tv,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMobile = PlatformDetection.useMobileUi;
    final width = MediaQuery.sizeOf(context).width;
    final s = isMobile ? 0.82 : (width / 1280).clamp(0.6, 1.2);
    final top = MediaQuery.paddingOf(context).top +
        (PlatformDetection.isTV ? 95.0 : (isMobile ? 60.0 : 80.0)) +
        16;
    final left = isMobile ? 16.0 : 64 * s;

    return ListView(
      padding: EdgeInsets.fromLTRB(left, top, left, 48),
      children: [
        Text(l10n.vjodTvTitle.toUpperCase(), style: vjodDisplay(48 * s)),
        SizedBox(height: 8 * s),
        Text(
          l10n.vjodTvSubtitle,
          style: TextStyle(
            color: vjodInk.withValues(alpha: 0.6),
            fontSize: 18 * s,
          ),
        ),
        SizedBox(height: 22 * s),
        _watchButton(l10n, s),
        SizedBox(height: 14 * s),
        _appRow(l10n, s),
        SizedBox(height: 34 * s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(l10n.vjodTvMyLists, style: vjodDisplay(26 * s)),
            ),
            _smallButton(
              icon: Icons.add_rounded,
              label: l10n.vjodTvAddList,
              scale: s,
              onTap: () => _addOrEdit(),
            ),
          ],
        ),
        SizedBox(height: 6 * s),
        Text(
          l10n.vjodTvListsHint,
          style: TextStyle(
            color: vjodInk.withValues(alpha: 0.55),
            fontSize: 15 * s,
          ),
        ),
        SizedBox(height: 16 * s),
        if (_playlists.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24 * s),
            child: Text(
              l10n.vjodTvNoList,
              style: TextStyle(
                color: vjodInk.withValues(alpha: 0.5),
                fontSize: 17 * s,
              ),
            ),
          )
        else
          for (final p in _playlists) ...[
            _playlistTile(p, s),
            SizedBox(height: 10 * s),
          ],
        if (_playlists.any((p) => p.kind == TvPlaylistKind.xtream)) ...[
          SizedBox(height: 34 * s),
          _languagesSection(s),
        ],
      ],
    );
  }

  Widget _watchButton(AppLocalizations l10n, double s) {
    final label = _checking
        ? l10n.vjodTvWatch
        : (_installed
            ? l10n.vjodTvWatchOn(_app.label)
            : l10n.vjodTvInstall(_app.label));
    final icon = _installed || _checking
        ? Icons.play_arrow_rounded
        : Icons.download_rounded;
    return VjodFocusable(
      autofocus: true,
      onTap: _open,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 64 * s,
        padding: EdgeInsets.symmetric(horizontal: 28 * s),
        decoration: BoxDecoration(
          color: vjodInk,
          borderRadius: BorderRadius.circular(8 * s),
          boxShadow: vjodFocusRing(s, on: focused),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: vjodPage, size: 26 * s),
            SizedBox(width: 12 * s),
            Text(
              label,
              style: TextStyle(
                color: vjodPage,
                fontSize: 21 * s,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appRow(AppLocalizations l10n, double s) {
    return Wrap(
      spacing: 10 * s,
      runSpacing: 10 * s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.vjodTvPlayer,
          style: TextStyle(
            color: vjodInk.withValues(alpha: 0.6),
            fontSize: 16 * s,
          ),
        ),
        for (final app in TvApp.all)
          VjodFocusable(
            onTap: () => _pickApp(app),
            builder: (context, focused) {
              final on = app.id == _app.id;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding:
                    EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s),
                decoration: BoxDecoration(
                  color: on ? vjodInk : vjodButton,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: vjodFocusRing(s * 0.6, on: focused),
                ),
                child: Text(
                  app.label,
                  style: TextStyle(
                    color: on ? vjodPage : vjodInk,
                    fontSize: 16 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _playlistTile(TvPlaylist p, double s) {
    final link = p.m3uUrl;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.all(14 * s),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(8 * s),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: vjodInk,
                    fontSize: 19 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3 * s),
                Text(
                  link.isEmpty ? l10n.vjodTvListIncomplete : link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: vjodInk.withValues(alpha: 0.55),
                    fontSize: 14 * s,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10 * s),
          if (link.isNotEmpty)
            _smallButton(
              icon: Icons.copy_rounded,
              label: l10n.vjodTvCopy,
              scale: s,
              onTap: () => _copy(p),
            ),
          SizedBox(width: 8 * s),
          _smallButton(
            icon: Icons.edit_rounded,
            scale: s,
            onTap: () => _addOrEdit(p),
          ),
          SizedBox(width: 8 * s),
          _smallButton(
            icon: Icons.delete_outline_rounded,
            scale: s,
            onTap: () => _remove(p),
          ),
        ],
      ),
    );
  }

  Widget _smallButton({
    required IconData icon,
    String? label,
    required double scale,
    required VoidCallback onTap,
  }) {
    return VjodFocusable(
      onTap: onTap,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44 * scale,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 10 * scale : 14 * scale),
        decoration: BoxDecoration(
          color: vjodButton,
          borderRadius: BorderRadius.circular(6 * scale),
          boxShadow: vjodFocusRing(scale * 0.6, on: focused),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: vjodInk, size: 20 * scale),
            if (label != null) ...[
              SizedBox(width: 7 * scale),
              Text(
                label,
                style: TextStyle(
                  color: vjodInk,
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small form to add or change one source. Kept deliberately plain: the
/// phone is where links get pasted.
class _PlaylistDialog extends StatefulWidget {
  final TvPlaylist? existing;

  /// A URL to start from, e.g. a link shared from another app.
  final String? seedUrl;
  const _PlaylistDialog({this.existing, this.seedUrl});

  @override
  State<_PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<_PlaylistDialog> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _epg;
  late TvPlaylistKind _kind;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // A shared link is read into a draft (Xtream split into its fields) so the
    // form opens filled; the viewer still reviews and saves it.
    final seed = e ??
        (widget.seedUrl != null
            ? parseSharedUrl(widget.seedUrl, id: 'draft')
            : null);
    _name = TextEditingController(text: seed?.name ?? '');
    _url = TextEditingController(text: seed?.url ?? widget.seedUrl ?? '');
    _user = TextEditingController(text: seed?.username ?? '');
    _pass = TextEditingController(text: seed?.password ?? '');
    _epg = TextEditingController(text: seed?.epgUrl ?? '');
    _kind = seed?.kind ?? TvPlaylistKind.m3u;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _epg.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    Navigator.of(context).pop(
      TvPlaylist(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        url: url,
        kind: _kind,
        username: _kind == TvPlaylistKind.xtream ? _user.text.trim() : '',
        password: _kind == TvPlaylistKind.xtream ? _pass.text.trim() : '',
        epgUrl: _kind == TvPlaylistKind.m3u ? _epg.text.trim() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final xtream = _kind == TvPlaylistKind.xtream;
    return AlertDialog(
      backgroundColor: AppColorScheme.surface,
      title: Text(
        widget.existing == null ? l10n.vjodTvAddList : l10n.vjodTvEditList,
        style: TextStyle(color: vjodInk),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<TvPlaylistKind>(
              segments: [
                ButtonSegment(value: TvPlaylistKind.m3u, label: Text(l10n.vjodTvM3u)),
                ButtonSegment(
                    value: TvPlaylistKind.xtream, label: Text(l10n.vjodTvXtream)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 12),
            _field(_name, l10n.vjodTvFieldName),
            _field(_url, xtream ? l10n.vjodTvFieldPortal : l10n.vjodTvFieldUrl,
                keyboard: TextInputType.url),
            if (xtream) ...[
              _field(_user, l10n.vjodTvFieldUser),
              _field(_pass, l10n.vjodTvFieldPass),
            ] else
              _field(_epg, l10n.vjodTvFieldEpg, keyboard: TextInputType.url),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        style: TextStyle(color: vjodInk),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: vjodInk.withValues(alpha: 0.6)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: vjodInk.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: vjodRed),
          ),
        ),
      ),
    );
  }
}
