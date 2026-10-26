import 'dart:convert';

/// How a saved TV source feeds an external IPTV player.
enum TvPlaylistKind { m3u, xtream }

/// One legal IPTV source the viewer saved, to copy into TiviMate (or another
/// player) at its first run. VJOD only keeps and shows it; it never plays it.
class TvPlaylist {
  final String id;
  final String name;

  /// For [TvPlaylistKind.m3u], the full M3U URL. For [TvPlaylistKind.xtream],
  /// the portal base, e.g. `http://host:port`.
  final String url;
  final TvPlaylistKind kind;

  /// Xtream only. Empty otherwise.
  final String username;
  final String password;

  /// Optional XMLTV guide URL for an M3U source.
  final String epgUrl;

  const TvPlaylist({
    required this.id,
    required this.name,
    required this.url,
    this.kind = TvPlaylistKind.m3u,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
  });

  /// The ready-to-paste M3U link. For Xtream, builds the standard
  /// `get.php` URL from the portal and the credentials; for M3U, the URL as
  /// saved. Empty when an Xtream source is missing a piece.
  String get m3uUrl {
    if (kind == TvPlaylistKind.m3u) return url.trim();
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || username.isEmpty || password.isEmpty) return '';
    return '$base/get.php'
        '?username=${Uri.encodeComponent(username)}'
        '&password=${Uri.encodeComponent(password)}'
        '&type=m3u_plus&output=ts';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'kind': kind.name,
        if (username.isNotEmpty) 'username': username,
        if (password.isNotEmpty) 'password': password,
        if (epgUrl.isNotEmpty) 'epgUrl': epgUrl,
      };

  static TvPlaylist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString();
    final name = raw['name']?.toString();
    final url = raw['url']?.toString();
    if (id == null || id.isEmpty || name == null || url == null) return null;
    return TvPlaylist(
      id: id,
      name: name,
      url: url,
      kind: raw['kind'] == 'xtream'
          ? TvPlaylistKind.xtream
          : TvPlaylistKind.m3u,
      username: raw['username']?.toString() ?? '',
      password: raw['password']?.toString() ?? '',
      epgUrl: raw['epgUrl']?.toString() ?? '',
    );
  }
}

/// Reads and writes the viewer's saved TV sources as a JSON list. Bad or
/// partial entries are skipped rather than throwing, so a hand-edited or
/// half-written store still opens.
class TvPlaylists {
  static List<TvPlaylist> decode(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    try {
      final data = jsonDecode(json);
      if (data is! List) return const [];
      return [
        for (final entry in data)
          if (TvPlaylist.fromJson(entry) case final p?) p,
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<TvPlaylist> playlists) =>
      jsonEncode([for (final p in playlists) p.toJson()]);
}
