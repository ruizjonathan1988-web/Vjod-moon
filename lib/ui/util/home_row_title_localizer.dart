import '../../data/models/home_row.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/preference_constants.dart';

/// The Seerr page builds its rows from the type alone, so it localizes the
/// title here rather than carrying one around.
String localizeSeerrRowTitle(SeerrRowType type, AppLocalizations l10n) =>
    switch (type) {
      SeerrRowType.shortcuts => l10n.seerrShortcutsRow,
      SeerrRowType.recentRequests => l10n.recentRequests,
      SeerrRowType.recentlyAdded => l10n.recentlyAdded,
      SeerrRowType.yourWatchlist => l10n.yourWatchlist,
      SeerrRowType.trending => l10n.trending,
      SeerrRowType.popularMovies => l10n.popularMovies,
      SeerrRowType.movieGenres => l10n.movieGenres,
      SeerrRowType.upcomingMovies => l10n.upcomingMovies,
      SeerrRowType.studios => l10n.studios,
      SeerrRowType.popularSeries => l10n.popularSeries,
      SeerrRowType.seriesGenres => l10n.seriesGenres,
      SeerrRowType.upcomingSeries => l10n.upcomingSeries,
      SeerrRowType.networks => l10n.networks,
    };

/// The seasonal row is titled after the holiday Moonbase picked, which it names
/// by id.
String seasonalHolidayTitle(String holiday, AppLocalizations l10n) =>
    switch (holiday) {
      'newYear' => l10n.holidayNewYear,
      'valentines' => l10n.holidayValentines,
      'easter' => l10n.holidayEaster,
      'pride' => l10n.holidayPride,
      'halloween' => l10n.holidayHalloween,
      'thanksgiving' => l10n.holidayThanksgiving,
      'christmas' => l10n.holidayChristmas,
      'lunarNewYear' => l10n.holidayLunarNewYear,
      'diwali' => l10n.holidayDiwali,
      _ => l10n.seasonalRow,
    };

String localizeHomeRowTitle({
  required HomeRow row,
  required AppLocalizations l10n,
  bool mergeContinueWatchingAndNextUp = false,
}) {
  switch (row.id) {
    case 'resume':
      return mergeContinueWatchingAndNextUp
          ? l10n.continueWatchingAndNextUp
          : l10n.continueWatching;
    case 'resumeAudio':
      return l10n.continueListening;
    case 'nextUp':
      return l10n.nextUp;
    case 'latestMedia':
      return l10n.latestMedia;
    case 'playlists':
      return l10n.playlists;
    case 'audioPlaylists':
      return l10n.audioPlaylists;
    case 'audioArtists':
      return l10n.artists;
    case 'audioAlbums':
      return l10n.albums;
    case 'collections':
      return l10n.collections;
    case 'genres':
      return l10n.genres;
    case 'libraryTiles':
    case 'libraryTilesSmall':
      return l10n.myMedia;
    case 'liveTv':
      return l10n.liveTv;
    case 'onNow':
    case 'liveTvOnNow':
      return l10n.onNow;
    case 'liveTvFavorites':
      return l10n.favoriteChannels;
    case 'activeRecordings':
      return l10n.activeRecordings;
    case 'radarr_calendar':
      return 'Upcoming Movies (Radarr)';
    case 'sonarr_calendar':
      return 'Upcoming TV Shows (Sonarr)';
    case 'seerr_for_you':
      return l10n.seerrForYouRow;
    case 'top10_movies':
      // With the Films/Series switch card first, the row holds either.
      // The key is HomeViewModel.top10SwitchFlag.
      final switches =
          row.items.isNotEmpty && row.items.first.rawData['Top10Switch'] == true;
      return switches ? l10n.top10Row : l10n.top10MoviesRow;
    case 'top10_series':
      return l10n.top10SeriesRow;
    case 'french_movies':
      return l10n.frenchMoviesRow;
    case 'french_series':
      return l10n.frenchSeriesRow;
    case 'french_classics':
      return l10n.frenchClassicsRow;
    case 'seerr_my_requests':
      return l10n.myRequestsRow;
    case 'seerr_sagas':
      return l10n.sagaRow;
    case 'seerr_gems':
      return l10n.gemsRow;
    case 'seerr_upcoming':
      return l10n.upcomingRow;
    case 'family_night':
      return l10n.familyNightRow;
    case 'surprise':
      return l10n.surpriseRow;
    case 'seerr_recent_requests':
      return l10n.recentRequests;
    case 'seerr_recently_added':
      return l10n.recentlyAdded;
    case 'seerr_popular_movies':
      return l10n.popularMovies;
    case 'seerr_upcoming_movies':
      return l10n.upcomingMovies;
    case 'seerr_popular_series':
      return l10n.popularSeries;
    case 'seerr_upcoming_series':
      return l10n.upcomingSeries;
    case 'seerr_shortcuts':
      return l10n.seerrShortcutsRow;
    case 'seerr_trending':
      return l10n.trending;
    case 'seerr_movie_genres':
      return l10n.movieGenres;
    case 'seerr_studios':
      return l10n.studios;
    case 'seerr_series_genres':
      return l10n.seriesGenres;
    case 'seerr_networks':
      return l10n.networks;
    case 'rewatch':
      return 'Rewatch';
  }

  if (row.id.startsWith('resume_')) return l10n.continueWatching;
  if (row.id.startsWith('nextUp_')) return l10n.nextUp;
  if (row.id.startsWith('lastPlayed_')) return l10n.lastPlayed;
  if (row.id.startsWith('albumartist_')) return l10n.albumArtists;
  if (row.id.startsWith('musicartist_')) return l10n.artists;
  if (row.id.startsWith('musicalbum_')) return l10n.albums;
  if (row.id.startsWith('latestBooks_')) return l10n.latestBooks;
  if (row.id.startsWith('latestAudiobooks_')) return l10n.latestAudiobooks;
  if (row.id.startsWith('latestComics_')) return l10n.latestComics;

  if (row.id.startsWith('latest_')) {
    return _localizeLatestRowTitle(row.title, l10n);
  }

  if (row.id.startsWith('imdb_')) {
    return row.title.replaceAll('IMDb ', '').replaceAll('IMDb', '').trim();
  }
  return row.title;
}

String _localizeLatestRowTitle(String title, AppLocalizations l10n) {
  const latestPrefix = 'Latest ';
  if (!title.startsWith(latestPrefix)) return title;
  final libraryName = title.substring(latestPrefix.length);
  return l10n.latestLibraryName(libraryName);
}
