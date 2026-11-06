// VJOD 4.27: « Le mois à la maison » (Playback Reporting).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../data/services/vjod/watch_month.dart';

class WatchMonthScreen extends StatefulWidget {
  const WatchMonthScreen({super.key});

  @override
  State<WatchMonthScreen> createState() => _WatchMonthScreenState();
}

class _WatchMonthScreenState extends State<WatchMonthScreen> {
  WatchMonth? _month;
  String _error = '';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) {
      setState(() {
        _busy = false;
        _error = 'Pas de serveur Jellyfin sur cet appareil.';
      });
      return;
    }
    final c = getIt<MediaServerClient>();
    final (m, e) = await WatchMonth.load(baseUrl: c.baseUrl, token: c.accessToken ?? '');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _month = m;
      _error = e;
    });
  }

  Widget _bars(BuildContext context, String title, List<(String, double)> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.first.$2 <= 0 ? 1.0 : rows.first.$2;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (name, h) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 12),
                      Text(WatchMonth.hours(h)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: h / max,
                      minHeight: 6,
                      backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _month;
    return Scaffold(
      appBar: AppBar(title: const Text('Le mois à la maison')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : m == null || m.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(m == null ? _error : 'Rien de regardé ces 30 derniers jours.', textAlign: TextAlign.center),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Text(WatchMonth.hours(m.totalHours),
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
                    const Text('regardées à la maison ces 30 derniers jours'),
                    const SizedBox(height: 28),
                    _bars(context, 'Qui a regardé', m.people),
                    _bars(context, 'Séries les plus suivies', m.series),
                    _bars(context, 'Films', m.films),
                  ],
                ),
              ),
            ),
    );
  }
}
