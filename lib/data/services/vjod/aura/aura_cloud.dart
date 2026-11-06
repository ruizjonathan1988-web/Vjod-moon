// Le serveur d'Aura (Supabase), appelé directement en HTTP : un compte
// anonyme par appareil et par profil, relié à sa « personne » (serveur +
// utilisateur Jellyfin) pour que l'aura se cumule sur tous ses appareils.
// Chacun ne voit que ce qui le concerne : les règles d'accès du serveur
// (migration 0008 du dépôt Aura) s'en chargent.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'aura.dart';

/// L'adresse et la clé publique du serveur d'Aura (la clé « anon » est faite
/// pour être dans les applis : ce sont les règles d'accès qui protègent).
abstract final class AuraServer {
  static const url = 'https://trjocwmslkxtluuhsvgx.supabase.co';
  static const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRyam9jd21zbGt4dGx1dWhzdmd4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5MTE2MzksImV4cCI6MjEwOTQ4NzYzOX0.dIR1DCJAY9C1tQn_--oPw3m9eebTNMT6M7E6K7OmQOc';
}

/// La session anonyme gardée sur l'appareil.
class AuraSession {
  final String userId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  const AuraSession({required this.userId, required this.accessToken, required this.refreshToken, required this.expiresAt});

  bool expiredAt(DateTime now) => now.isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  Map<String, dynamic> toJson() => {
        'u': userId,
        'a': accessToken,
        'r': refreshToken,
        'e': expiresAt.toUtc().toIso8601String(),
      };

  static AuraSession? fromJson(Object? j) {
    if (j is! Map || j['u'] is! String || j['a'] is! String || j['r'] is! String) return null;
    return AuraSession(
      userId: j['u'] as String,
      accessToken: j['a'] as String,
      refreshToken: j['r'] as String,
      expiresAt: DateTime.tryParse('${j['e']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// La réponse de Supabase à une connexion ou un rafraîchissement.
  static AuraSession? fromAuth(Object? j, DateTime now) {
    if (j is! Map) return null;
    final user = j['user'];
    final access = j['access_token'];
    final refresh = j['refresh_token'];
    if (user is! Map || user['id'] is! String || access is! String || refresh is! String) return null;
    final seconds = (j['expires_in'] as num?)?.toInt() ?? 3600;
    return AuraSession(
      userId: user['id'] as String,
      accessToken: access,
      refreshToken: refresh,
      expiresAt: now.add(Duration(seconds: seconds)),
    );
  }
}

/// Un profil de la maison qui joue à Aura.
class AuraHousemate {
  final String person;
  final String name;
  const AuraHousemate({required this.person, required this.name});
}

class AuraCloudException implements Exception {
  final String message;
  const AuraCloudException(this.message);
  @override
  String toString() => message;
}

/// Les appels au serveur d'Aura. [load] et [save] gardent la session sur
/// l'appareil.
class AuraCloud {
  AuraCloud({
    required this.load,
    required this.save,
    http.Client? client,
    DateTime Function()? clock,
    this.url = AuraServer.url,
    this.anonKey = AuraServer.anonKey,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final Future<String?> Function() load;
  final Future<void> Function(String value) save;
  final String url;
  final String anonKey;
  final http.Client _client;
  final DateTime Function() _clock;

  AuraSession? _session;

  Map<String, String> _headers([String? token]) => {
        'apikey': anonKey,
        'Authorization': 'Bearer ${token ?? anonKey}',
        'Content-Type': 'application/json',
      };

  /// Une session valable : celle gardée, rafraîchie au besoin, sinon un
  /// nouveau compte anonyme.
  Future<AuraSession> session() async {
    final now = _clock();
    var s = _session;
    if (s == null) {
      final raw = await load();
      if (raw != null && raw.isNotEmpty) {
        try {
          s = AuraSession.fromJson(jsonDecode(raw));
        } catch (_) {}
      }
    }
    if (s != null && !s.expiredAt(now)) return _session = s;
    if (s != null) {
      final r = await _client.post(
        Uri.parse('$url/auth/v1/token?grant_type=refresh_token'),
        headers: _headers(),
        body: jsonEncode({'refresh_token': s.refreshToken}),
      );
      final fresh = r.statusCode == 200 ? AuraSession.fromAuth(jsonDecode(r.body), now) : null;
      if (fresh != null) return _keep(fresh);
    }
    final r = await _client.post(Uri.parse('$url/auth/v1/signup'), headers: _headers(), body: jsonEncode({'data': {}}));
    final fresh = r.statusCode == 200 ? AuraSession.fromAuth(jsonDecode(r.body), now) : null;
    if (fresh == null) {
      throw AuraCloudException(r.statusCode == 422 || r.statusCode == 400
          ? 'Le serveur d’Aura refuse les comptes anonymes.'
          : 'Le serveur d’Aura ne répond pas.');
    }
    return _keep(fresh);
  }

  Future<AuraSession> _keep(AuraSession s) async {
    _session = s;
    await save(jsonEncode(s.toJson()));
    return s;
  }

  Uri _rest(String path, [Map<String, String>? query]) => Uri.parse('$url/rest/v1/$path').replace(queryParameters: query);

  void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    if (r.statusCode == 409) throw const AuraCloudException('Déjà proposé.');
    throw AuraCloudException('Le serveur d’Aura a répondu ${r.statusCode}.');
  }

  /// Crée ou met à jour le joueur de cet appareil, relié à sa maison et à sa
  /// personne.
  Future<void> register({required String pseudo, required String house, required String person}) async {
    final s = await session();
    final r = await _client.post(
      _rest('joueurs', {'on_conflict': 'id'}),
      headers: {..._headers(s.accessToken), 'Prefer': 'resolution=merge-duplicates,return=minimal'},
      body: jsonEncode({'id': s.userId, 'pseudo': auraPseudo(pseudo), 'maison': house, 'personne': person}),
    );
    _check(r);
  }

  /// Les profils de la maison qui jouent, un par personne, sans soi.
  Future<List<AuraHousemate>> housemates({required String house, required String me}) async {
    final s = await session();
    final r = await _client.get(
      _rest('joueurs', {'select': 'pseudo,personne', 'maison': 'eq.$house', 'personne': 'not.is.null'}),
      headers: _headers(s.accessToken),
    );
    _check(r);
    final seen = <String>{me};
    final out = <AuraHousemate>[];
    for (final j in (jsonDecode(r.body) as List? ?? const [])) {
      if (j is! Map || j['personne'] is! String) continue;
      final person = j['personne'] as String;
      if (!seen.add(person)) continue;
      out.add(AuraHousemate(person: person, name: '${j['pseudo'] ?? '?'}'));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Toutes les propositions visibles : les siennes, celles reçues, celles
  /// de la maison (pour le classement).
  Future<List<AuraProposal>> proposals() async {
    final s = await session();
    final r = await _client.get(
      _rest('propositions', {'select': '*', 'order': 'cree_le.desc', 'limit': '300'}),
      headers: _headers(s.accessToken),
    );
    _check(r);
    return [
      for (final j in (jsonDecode(r.body) as List? ?? const []))
        if (AuraProposal.fromJson(j) case final p?) p,
    ];
  }

  Future<void> propose(Map<String, dynamic> body) async {
    final s = await session();
    final r = await _client.post(
      _rest('propositions'),
      headers: {..._headers(s.accessToken), 'Prefer': 'return=minimal'},
      body: jsonEncode(body),
    );
    _check(r);
  }

  /// Dit qu'une proposition reçue a été vue ou aimée.
  Future<void> mark(String id, Map<String, dynamic> patch) async {
    final s = await session();
    final r = await _client.patch(
      _rest('propositions', {'id': 'eq.$id'}),
      headers: {..._headers(s.accessToken), 'Prefer': 'return=minimal'},
      body: jsonEncode(patch),
    );
    _check(r);
  }
}
