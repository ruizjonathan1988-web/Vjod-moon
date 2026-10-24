class MediaBarSlideItem {
  final String itemId;
  final String serverId;
  final String title;
  final String? overview;
  final String? backdropUrl;

  /// The wide banner art, which usually has the title painted into it.
  final String? bannerUrl;
  final String? logoUrl;
  final String? posterUrl;
  final String? officialRating;
  final int? year;
  final List<String> genres;
  final Duration? runtime;
  final double? communityRating;
  final int? criticRating;
  final String? tmdbId;
  final String? imdbId;
  final String itemType;
  final List<Map<String, dynamic>> remoteTrailers;

  /// Why the slide is there, shown above its details, such as the evening
  /// it was picked for.
  final String? kicker;

  /// What the slide is to Tonight: [roleResume], [rolePick] or
  /// [roleRequest]. Null outside Tonight.
  final String? role;

  /// The line a Tonight card shows under itself, when it isn't worked out
  /// on screen, such as how much of an episode is left.
  final String? caption;

  /// How far the viewer got, for what is there to resume.
  final double? progress;

  static const roleResume = 'resume';
  static const rolePick = 'pick';
  static const roleRequest = 'request';

  const MediaBarSlideItem({
    required this.itemId,
    required this.serverId,
    required this.title,
    this.overview,
    this.backdropUrl,
    this.bannerUrl,
    this.logoUrl,
    this.posterUrl,
    this.officialRating,
    this.year,
    this.genres = const [],
    this.runtime,
    this.communityRating,
    this.criticRating,
    this.tmdbId,
    this.imdbId,
    this.itemType = 'Movie',
    this.remoteTrailers = const [],
    this.kicker,
    this.role,
    this.caption,
    this.progress,
  });

  MediaBarSlideItem withKicker(String? kicker) => withTonight(
    kicker: kicker,
    role: role,
    caption: caption,
    progress: progress,
  );

  MediaBarSlideItem withTonight({
    String? kicker,
    String? role,
    String? caption,
    double? progress,
  }) => MediaBarSlideItem(
    itemId: itemId,
    serverId: serverId,
    title: title,
    overview: overview,
    backdropUrl: backdropUrl,
    bannerUrl: bannerUrl,
    logoUrl: logoUrl,
    posterUrl: posterUrl,
    officialRating: officialRating,
    year: year,
    genres: genres,
    runtime: runtime,
    communityRating: communityRating,
    criticRating: criticRating,
    tmdbId: tmdbId,
    imdbId: imdbId,
    itemType: itemType,
    remoteTrailers: remoteTrailers,
    kicker: kicker,
    role: role,
    caption: caption,
    progress: progress,
  );
}
