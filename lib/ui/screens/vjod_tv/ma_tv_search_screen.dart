// Finding a channel by typing: its name, its number, or what it airs now or
// next ("psg" finds the channel showing the match). Case, accents, spaces and
// punctuation don't matter ("tf 1", "TF1", "tf-1").
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/services/vjod/channel_search.dart';
import '../../../data/services/vjod/ma_tv.dart';
import 'ma_tv_widgets.dart';

/// Returns the channels found and the one picked, or null when left.
class MaTvSearchScreen extends StatefulWidget {
  const MaTvSearchScreen({super.key});

  @override
  State<MaTvSearchScreen> createState() => _MaTvSearchScreenState();
}

class _MaTvSearchScreenState extends State<MaTvSearchScreen> {
  final _client = MaTvClient();
  final _field = TextEditingController();
  List<MaTvChannel>? _all;
  bool _failed = false;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final all = await _client.allChannels();
    if (!mounted) return;
    setState(() {
      _all = all ?? const [];
      _failed = all == null;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  List<MaTvChannel> get _found {
    final all = _all ?? const <MaTvChannel>[];
    if (normalizeChannelQuery(_query).isEmpty) return const [];
    return [
      for (final c in all)
        if (channelMatchesQuery(
          _query,
          name: c.name,
          number: '${c.number}',
          programTitles: [?c.now?.title, ?c.next?.title],
        ))
          c,
    ].take(80).toList();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chercher une chaîne',
                style: TextStyle(color: MaTvColors.ink, fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _field,
                autofocus: true,
                style: const TextStyle(color: MaTvColors.ink, fontSize: 20),
                cursorColor: MaTvColors.accent,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Nom, numéro ou programme (ex. « TF1 », « 12 », « PSG »)',
                  hintStyle: const TextStyle(color: MaTvColors.mute),
                  prefixIcon: const Icon(Icons.search_rounded, color: MaTvColors.mute),
                  filled: true,
                  fillColor: MaTvColors.row,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 200), () {
                    if (mounted) setState(() => _query = text);
                  });
                },
                onSubmitted: (text) {
                  setState(() => _query = text);
                  final list = _found;
                  if (list.isNotEmpty) Navigator.of(context).pop((channels: list, index: 0));
                },
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _all == null
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _failed
                    ? const Center(
                        child: Text('Ma TV ne répond pas, réessaie dans un instant.',
                            style: TextStyle(color: MaTvColors.mute, fontSize: 16)),
                      )
                    : found.isEmpty
                    ? Center(
                        child: Text(
                          _query.trim().isEmpty ? 'Tape quelques lettres.' : 'Aucune chaîne trouvée.',
                          style: const TextStyle(color: MaTvColors.mute, fontSize: 16),
                        ),
                      )
                    : ListView.separated(
                        itemCount: found.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) => _ResultRow(
                          channel: found[i],
                          now: now,
                          onTap: () => Navigator.of(context).pop((channels: found, index: i)),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A result, reachable with the remote (DOWN from the field), lit when
/// focused, OK plays it.
class _ResultRow extends StatefulWidget {
  final MaTvChannel channel;
  final DateTime now;
  final VoidCallback onTap;

  const _ResultRow({required this.channel, required this.now, required this.onTap});

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onTap,
    onFocusChange: (f) => setState(() => _focused = f),
    focusColor: Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    child: MaTvChannelRow(channel: widget.channel, now: widget.now, focused: _focused, selected: _focused),
  );
}
