// Aura dans VJOD : ce qui relie les règles (aura.dart) et le serveur d'Aura
// (aura_cloud.dart) au profil en cours, à Jellyfin et à l'appareil.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../auth/repositories/session_repository.dart';
import '../../../../auth/repositories/user_repository.dart';
import '../../../../preference/user_preferences.dart';
import '../simple_mode.dart' show simpleModeClient, simpleModePrefsId;
import 'aura.dart';
import 'aura_cloud.dart';

/// Le réglage du profil en cours (tel que lu la dernière fois sur le serveur).
AuraMode vjodAuraMode() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<UserPreferences>()) return AuraMode.off;
  try {
    return AuraMode.from(getIt<UserPreferences>().get(UserPreferences.vjodAuraMode));
  } catch (_) {
    return AuraMode.off;
  }
}

bool vjodAuraOn() => vjodAuraMode() != AuraMode.off;

/// Écrit le réglage du profil en cours dans Jellyfin, et sur l'appareil.
Future<void> writeAuraMode(AuraMode mode) async {
  final getIt = GetIt.instance;
  final userId = getIt<SessionRepository>().activeUserId;
  await getIt<UserPreferences>().set(UserPreferences.vjodAuraMode, mode.id);
  AuraHub.instance.changed();
  if (userId == null || userId.isEmpty) return;
  final api = getIt<MediaServerClient>().displayPreferencesApi;
  DisplayPreferences current;
  try {
    current = await api.getDisplayPreferences(simpleModePrefsId, client: simpleModeClient, userId: userId);
  } catch (_) {
    current = const DisplayPreferences(id: simpleModePrefsId);
  }
  await api.saveDisplayPreferences(
    simpleModePrefsId,
    withAuraMode(current, mode, defaultId: simpleModePrefsId),
    client: simpleModeClient,
    userId: userId,
  );
  if (mode != AuraMode.off) unawaited(AuraHub.instance.register());
}

String? _modeSyncedFor;

/// Reprend le réglage du profil depuis Jellyfin, une fois par profil et par
/// lancement. Rien de lu : on garde ce que l'appareil savait.
Future<void> syncAuraModeFromServer() async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SessionRepository>() ||
      !getIt.isRegistered<UserPreferences>() ||
      !getIt.isRegistered<MediaServerClient>()) {
    return;
  }
  final userId = getIt<SessionRepository>().activeUserId;
  if (userId == null || userId.isEmpty || _modeSyncedFor == userId) return;
  _modeSyncedFor = userId;
  try {
    final prefs = await getIt<MediaServerClient>()
        .displayPreferencesApi
        .getDisplayPreferences(simpleModePrefsId, client: simpleModeClient, userId: userId);
    final mode = auraModeFromPrefs(prefs.customPrefs);
    final local = getIt<UserPreferences>();
    if (local.get(UserPreferences.vjodAuraMode) != mode.id) {
      await local.set(UserPreferences.vjodAuraMode, mode.id);
      AuraHub.instance.changed();
    }
    if (mode != AuraMode.off) unawaited(AuraHub.instance.register());
  } catch (e) {
    _modeSyncedFor = null;
    debugPrint('[Aura] lecture du réglage impossible : $e');
  }
}

/// Ce que le tiroir montre.
class AuraDrawerData {
  final AuraState? state;
  final List<AuraProposal> received;
  final List<({String who, String name, int aura})> ranking;
  final String me;
  final String? error;

  const AuraDrawerData({this.state, this.received = const [], this.ranking = const [], this.me = '', this.error});
}

/// Le profil en cours vu par Aura : sa maison, sa personne, son compte.
class AuraHub extends ChangeNotifier {
  AuraHub._();
  static final instance = AuraHub._();

  AuraCloud? _cloud;
  String? _cloudFor;
  String? _house;
  String? _registeredFor;

  void changed() => notifyListeners();

  MediaServerClient get _jf => GetIt.instance<MediaServerClient>();

  String get _userId => GetIt.instance<SessionRepository>().activeUserId ?? '';

  String get _userName {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<UserRepository>()) return 'VJOD';
    return getIt<UserRepository>().currentUser?.name ?? 'VJOD';
  }

  /// L'identifiant Jellyfin du serveur : c'est la maison.
  Future<String> house() async {
    final h = _house;
    if (h != null) return h;
    final info = await _jf.systemApi.getPublicSystemInfo();
    final id = '${info['Id'] ?? ''}';
    if (id.isEmpty) throw const AuraCloudException('Le serveur Jellyfin ne dit pas qui il est.');
    return _house = id;
  }

  Future<String> me() async => auraPerson(await house(), _userId);

  AuraCloud get cloud {
    final user = _userId;
    if (_cloud == null || _cloudFor != user) {
      final key = 'vjod_aura_session_$user';
      _cloud = AuraCloud(
        load: () async => (await SharedPreferences.getInstance()).getString(key),
        save: (v) async => (await SharedPreferences.getInstance()).setString(key, v),
      );
      _cloudFor = user;
      _registeredFor = null;
    }
    return _cloud!;
  }

  /// Le joueur de cet appareil, relié à la maison et à la personne : une
  /// fois par profil et par lancement.
  Future<void> register() async {
    final user = _userId;
    if (user.isEmpty || _registeredFor == user) return;
    try {
      await cloud.register(pseudo: _userName, house: await house(), person: await me());
      _registeredFor = user;
    } catch (e) {
      debugPrint('[Aura] inscription impossible : $e');
    }
  }

  /// L'état publié par l'appli Aura, ou nul quand elle n'a rien publié.
  Future<AuraState?> state() async {
    try {
      final prefs = await _jf.displayPreferencesApi
          .getDisplayPreferences(AuraBridge.prefsId, client: AuraBridge.client, userId: _userId);
      return AuraState.fromPrefs(prefs.customPrefs);
    } catch (_) {
      return null;
    }
  }

  /// Joue une carte du soir : Aura en fait une séance à sa prochaine ouverture.
  Future<void> playCard(DateTime day, int index) async {
    final api = _jf.displayPreferencesApi;
    DisplayPreferences current;
    try {
      current = await api.getDisplayPreferences(AuraBridge.prefsId, client: AuraBridge.client, userId: _userId);
    } catch (_) {
      current = const DisplayPreferences(id: AuraBridge.prefsId);
    }
    final value = AuraBridge.played(day: AuraBridge.day(day), index: index, at: DateTime.now());
    await api.saveDisplayPreferences(
      AuraBridge.prefsId,
      AuraBridge.withPlayed(current, value),
      client: AuraBridge.client,
      userId: _userId,
    );
  }

  /// Tout le tiroir : la course, les cartes, ce qu'on m'a proposé, l'aura de
  /// la maison. Ce que Jellyfin dit avoir été vu ou aimé part au serveur.
  Future<AuraDrawerData> drawer() async {
    final state = await this.state();
    try {
      await register();
      final mine = await me();
      var all = await cloud.proposals();
      if (await _reportWatched(all, mine)) all = await cloud.proposals();
      return AuraDrawerData(
        state: state,
        me: mine,
        received: [for (final p in all) if (p.recipient == mine && !p.seen) p],
        ranking: AuraScore.ranking(all.where((p) => p.fromPerson != null && p.fromPerson!.startsWith('${_house ?? ''}:'))),
      );
    } catch (e) {
      return AuraDrawerData(state: state, error: '$e');
    }
  }

  /// Regarde dans Jellyfin si ce qu'on m'a proposé a été vu ou aimé.
  Future<bool> _reportWatched(List<AuraProposal> all, String mine) async {
    var any = false;
    for (final p in all) {
      if (p.recipient != mine || (p.seen && p.liked)) continue;
      final w = await _watch(p);
      final patch = w?.patchFor(p, DateTime.now());
      if (patch == null) continue;
      try {
        await cloud.mark(p.id, patch);
        any = true;
      } catch (e) {
        debugPrint('[Aura] envoi de « vu » impossible : $e');
      }
    }
    return any;
  }

  Future<AuraWatch?> _watch(AuraProposal p) async {
    try {
      final id = p.jellyfinId;
      if (id != null && id.isNotEmpty) {
        final item = await _jf.userLibraryApi.getItem(id);
        return AuraWatch.fromUserData(item['UserData'] as Map<String, dynamic>?);
      }
      final tmdb = p.tmdbId;
      if (tmdb == null) return null;
      final res = await _jf.itemsApi.getItems(
        recursive: true,
        includeItemTypes: [p.series ? 'Series' : 'Movie'],
        anyProviderIdEquals: 'tmdb.$tmdb',
        limit: 1,
      );
      final items = res['Items'] as List? ?? const [];
      if (items.isEmpty || items.first is! Map) return null;
      return AuraWatch.fromUserData((items.first as Map)['UserData'] as Map<String, dynamic>?);
    } catch (_) {
      return null;
    }
  }

  /// Les profils de la maison à qui proposer.
  Future<List<AuraHousemate>> housemates() async {
    await register();
    return cloud.housemates(house: await house(), me: await me());
  }

  /// Propose un titre à un profil de la maison.
  Future<void> propose({
    required AuraHousemate to,
    required String title,
    int? year,
    int? tmdbId,
    String? jellyfinId,
    bool series = false,
    String? note,
  }) async {
    await register();
    await cloud.propose(AuraProposal.newInHouse(
      fromPerson: await me(),
      fromName: _userName,
      toPerson: to.person,
      toName: to.name,
      house: await house(),
      title: title,
      year: year,
      tmdbId: tmdbId,
      jellyfinId: jellyfinId,
      series: series,
      note: note,
    ));
  }
}
