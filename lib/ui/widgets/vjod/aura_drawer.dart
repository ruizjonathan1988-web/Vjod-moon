// Aura dans VJOD (4.37) : le bouton Pop, son tiroir, « Proposer à… » et le
// réglage. Tout se joue à la télécommande : chaque ligne prend le focus.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/aura/aura.dart';
import '../../../data/services/vjod/aura/aura_cloud.dart';
import '../../../data/services/vjod/aura/aura_service.dart';
import '../../navigation/destinations.dart';
import 'vjod_widgets.dart';

const _popYellow = Color(0xFFF7D154);
const _popInk = Color(0xFF141414);

/// Le bouton Pop de la barre du haut.
class AuraPopButton extends StatelessWidget {
  final double scale;
  final FocusNode? focusNode;

  const AuraPopButton({super.key, this.scale = 1, this.focusNode});

  @override
  Widget build(BuildContext context) => VjodRoundButton(
        size: 44 * scale,
        background: _popYellow,
        focusNode: focusNode,
        scale: scale,
        semanticLabel: 'Aura, le jeu de cinéma',
        onTap: () => showAuraDrawer(context),
        child: Icon(Icons.auto_awesome_rounded, color: _popInk, size: 24 * scale),
      );
}

/// Ouvre le tiroir d'Aura. La fiche choisie s'ouvre une fois le tiroir fermé.
Future<void> showAuraDrawer(BuildContext context) async {
  final router = GoRouter.of(context);
  final destination = await Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const AuraDrawerScreen()),
  );
  if (destination == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => router.push(destination));
}

/// La fiche d'un titre : sur le serveur, sinon celle « Regarder / Demander ».
String? auraFicheRoute({String? jellyfinId, int? tmdbId, required String title, bool series = false}) {
  if (jellyfinId != null && jellyfinId.isNotEmpty) return Destinations.item(jellyfinId);
  if (tmdbId == null) return null;
  return Uri(path: '/seerr/media/$tmdbId', queryParameters: {
    'mediaType': series ? 'tv' : 'movie',
    if (title.isNotEmpty) 'title': title,
  }).toString();
}

class AuraDrawerScreen extends StatefulWidget {
  const AuraDrawerScreen({super.key});

  @override
  State<AuraDrawerScreen> createState() => _AuraDrawerScreenState();
}

class _AuraDrawerScreenState extends State<AuraDrawerScreen> {
  AuraDrawerData? _data;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final d = await AuraHub.instance.drawer();
    if (mounted) setState(() => _data = d);
  }

  Future<void> _play(int index, AuraCard card) async {
    try {
      await AuraHub.instance.playCard(DateTime.now(), index);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de prévenir Aura. La fiche s’ouvre quand même.')),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(auraFicheRoute(
      jellyfinId: card.onServer ? card.filmId : null,
      tmdbId: card.tmdbId,
      title: card.title,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: vjodPage,
      appBar: AppBar(
        backgroundColor: vjodPage,
        foregroundColor: vjodInk,
        title: const Text('Aura, le jeu de cinéma'),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: _sections(d),
                ),
              ),
            ),
    );
  }

  List<Widget> _sections(AuraDrawerData d) {
    final state = d.state;
    final cards = state?.cardsFor(DateTime.now()) ?? const <AuraCard>[];
    var first = true;
    bool takeFocus() {
      final f = first;
      first = false;
      return f;
    }

    return [
      const _Header('La course du mois'),
      if (state == null)
        const _Line('Ouvre une fois l’appli Aura sur ce profil : elle prépare la course et tes cartes du soir pour VJOD.')
      else ...[
        _Line('Toi : case ${state.position} sur ${AuraState.boardSize} · Pop : case ${state.pop}', strong: true),
        _Line(state.raceLine),
        if (state.playingTitle != null) _Line('Séance en cours : ${state.playingTitle}. Aura la valide quand le film est vu.'),
      ],
      if (state != null) ...[
        const _Header('Ce soir avec Pop'),
        if (cards.isEmpty)
          const _Line('Pas de cartes pour ce soir : ouvre Aura, elle en tire pour la semaine.')
        else
          for (final (i, c) in cards.indexed)
            AuraTile(
              autofocus: takeFocus(),
              icon: Icons.style_rounded,
              title: c.challenge.isEmpty ? 'Carte ${c.type}' : c.challenge,
              subtitle: '${c.title}${c.year != null ? ' (${c.year})' : ''} · ${c.squares} case${c.squares > 1 ? 's' : ''}'
                  '${c.level != null ? ' · niveau ${c.level}' : ''}',
              onTap: () => _play(i, c),
            ),
      ],
      const _Header('On te propose'),
      if (d.error != null)
        _Line('Le serveur d’Aura ne répond pas pour l’instant (${d.error}).')
      else if (d.received.isEmpty)
        const _Line('Rien pour l’instant. Sur la fiche d’un film, « Proposer à… » l’envoie à quelqu’un de la maison.')
      else
        for (final p in d.received)
          if (p.sealed(DateTime.now()))
            // Cacheté depuis Aura : qui l'envoie et quand, jamais le titre.
            AuraTile(
              autofocus: takeFocus(),
              icon: Icons.lock_rounded,
              title: 'Un film cacheté de ${p.fromName}',
              subtitle: '${p.opensLabel(DateTime.now())[0].toUpperCase()}${p.opensLabel(DateTime.now()).substring(1)}${p.note != null ? ' · « ${p.note} »' : ''}',
              onTap: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text('Pas avant le jour prévu : ${p.opensLabel(DateTime.now())}.')),
              ),
            )
          else
          AuraTile(
            autofocus: takeFocus(),
            icon: Icons.card_giftcard_rounded,
            title: '${p.title}${p.year != null ? ' (${p.year})' : ''}',
            subtitle: 'De ${p.fromName}${p.note != null ? ' · « ${p.note} »' : ''}',
            onTap: () => Navigator.of(context).pop(auraFicheRoute(
              jellyfinId: p.jellyfinId,
              tmdbId: p.tmdbId,
              title: p.title,
              series: p.series,
            )),
          ),
      if (d.error == null) ...[
        const _Header('L’aura de la maison'),
        if (d.ranking.isEmpty)
          const _Line('Personne n’a encore d’aura. Propose un film : +1 quand il est vu, +2 quand il est aimé, +3 quand plusieurs l’aiment.')
        else
          for (final (i, r) in d.ranking.indexed)
            _Line('${i + 1}. ${r.name}${r.who == d.me ? ' (toi)' : ''} : ${r.aura} d’aura', strong: r.who == d.me),
      ],
    ];
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(color: vjodInk, fontFamily: vjodDisplayFont, fontSize: 22, letterSpacing: .5),
        ),
      );
}

class _Line extends StatelessWidget {
  final String text;
  final bool strong;
  const _Line(this.text, {this.strong = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(color: vjodInk, fontSize: 17, fontWeight: strong ? FontWeight.w800 : FontWeight.w500, height: 1.3),
        ),
      );
}

/// Une ligne qu'on choisit, au doigt ou à la télécommande.
class AuraTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool autofocus;
  final bool selected;

  const AuraTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.autofocus = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: VjodFocusable(
          autofocus: autofocus,
          onTap: onTap,
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? _popYellow : vjodButton,
              borderRadius: BorderRadius.circular(10),
              boxShadow: vjodFocusRing(1, on: focused),
            ),
            child: Row(children: [
              Icon(icon, color: selected ? _popInk : vjodInk, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(color: selected ? _popInk : vjodInk, fontSize: 17, fontWeight: FontWeight.w800)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(color: (selected ? _popInk : vjodInk).withValues(alpha: .75), fontSize: 14)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Les mots qu'on peut joindre, sans clavier (la télécommande n'en a pas).
const auraNotes = <String?>[
  null,
  'Tu vas adorer.',
  'Fais-moi confiance.',
  'Pour un soir de pluie.',
  'On en parle après ?',
];

/// « Proposer à… » : à qui, puis un mot si on veut.
Future<void> showAuraPropose(
  BuildContext context, {
  required String title,
  int? year,
  int? tmdbId,
  String? jellyfinId,
  bool series = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final done = await Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProposeScreen(title: title, year: year, tmdbId: tmdbId, jellyfinId: jellyfinId, series: series),
    ),
  );
  if (done != null) messenger?.showSnackBar(SnackBar(content: Text(done)));
}

class _ProposeScreen extends StatefulWidget {
  final String title;
  final int? year;
  final int? tmdbId;
  final String? jellyfinId;
  final bool series;

  const _ProposeScreen({required this.title, this.year, this.tmdbId, this.jellyfinId, this.series = false});

  @override
  State<_ProposeScreen> createState() => _ProposeScreenState();
}

class _ProposeScreenState extends State<_ProposeScreen> {
  List<AuraHousemate>? _people;
  String? _error;
  AuraHousemate? _to;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final p = await AuraHub.instance.housemates();
      if (mounted) setState(() => _people = p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _send(String? note) async {
    final to = _to;
    if (to == null || _sending) return;
    setState(() => _sending = true);
    try {
      await AuraHub.instance.propose(
        to: to,
        title: widget.title,
        year: widget.year,
        tmdbId: widget.tmdbId,
        jellyfinId: widget.jellyfinId,
        series: widget.series,
        note: note,
      );
      if (mounted) Navigator.of(context).pop('Proposé à ${to.name}. Ton aura grandit s’il le regarde.');
    } on AuraCloudException catch (e) {
      if (!mounted) return;
      if (e.message == 'Déjà proposé.') {
        Navigator.of(context).pop('Tu l’avais déjà proposé à ${to.name}.');
      } else {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final to = _to;
    return Scaffold(
      backgroundColor: vjodPage,
      appBar: AppBar(
        backgroundColor: vjodPage,
        foregroundColor: vjodInk,
        title: Text(to == null ? 'Proposer « ${widget.title} » à…' : 'Un mot pour ${to.name} ?'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (_error != null) _Line('Impossible pour l’instant : $_error'),
              if (people == null && _error == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (people != null && people.isEmpty)
                const _Line('Personne d’autre ne joue encore à Aura dans la maison. Chacun l’active dans ses réglages VJOD : '
                    'Réglages → L’essentiel → Aura, le jeu de cinéma.')
              else if (people != null && to == null)
                for (final (i, p) in people.indexed)
                  AuraTile(
                    autofocus: i == 0,
                    icon: Icons.person_rounded,
                    title: p.name,
                    onTap: () => setState(() => _to = p),
                  )
              else if (to != null)
                for (final (i, n) in auraNotes.indexed)
                  AuraTile(
                    autofocus: i == 0,
                    icon: n == null ? Icons.send_rounded : Icons.chat_bubble_outline_rounded,
                    title: n ?? 'Envoyer sans mot',
                    onTap: () => _send(n),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le réglage, profil par profil.
class AuraSettingsScreen extends StatefulWidget {
  const AuraSettingsScreen({super.key});

  @override
  State<AuraSettingsScreen> createState() => _AuraSettingsScreenState();
}

class _AuraSettingsScreenState extends State<AuraSettingsScreen> {
  late AuraMode _mode = vjodAuraMode();
  String? _error;

  Future<void> _set(AuraMode m) async {
    setState(() {
      _mode = m;
      _error = null;
    });
    try {
      await writeAuraMode(m);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gardé sur cet appareil ; le serveur Jellyfin n’a pas pu l’enregistrer pour tes autres appareils.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Aura, le jeu de cinéma')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const _Line('Aura est le jeu de société du cinéma de VJOD. Ici, tu proposes des films aux autres profils de la maison : '
                'ton aura grandit quand ils les regardent et les aiment. Avec l’appli Aura, tu retrouves aussi la course contre Pop et tes cartes du soir.'),
            const SizedBox(height: 12),
            AuraTile(
              autofocus: true,
              icon: Icons.block_rounded,
              title: 'Coupé',
              subtitle: 'VJOD comme avant.',
              selected: _mode == AuraMode.off,
              onTap: () => _set(AuraMode.off),
            ),
            AuraTile(
              icon: Icons.auto_awesome_rounded,
              title: 'Bouton Pop',
              subtitle: 'Un bouton jaune en haut ouvre la course, les cartes du soir, ce qu’on te propose et l’aura de la maison. '
                  '« Proposer à… » apparaît sur les fiches.',
              selected: _mode == AuraMode.button,
              onTap: () => _set(AuraMode.button),
            ),
            const SizedBox(height: 8),
            const _Line('Le réglage suit ton profil sur tous tes appareils.'),
            if (_error != null) _Line(_error!),
          ],
        ),
      );
}
