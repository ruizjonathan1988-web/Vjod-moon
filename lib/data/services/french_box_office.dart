/// The French films France went to see most in cinemas, by admissions, as
/// TMDB ids, the most seen first.
///
/// Admissions are history, so the lists live here. Sources: the CNC for the
/// 2010s, CBO Box-Office for all time, and each year's tallies for the
/// 2020s, as of October 2026. The decade under way also follows TMDB's box
/// office live, so its new hits show up without touching these lists.
library;

/// The 2020s so far.
const frenchHits2020s = [
  1152014, // Un p'tit truc en plus (2024), 10.8 M
  1084736, // Le Comte de Monte-Cristo (2024), 9.4 M
  1145899, // Marsupilami (2026), 6.1 M by July 2026
  959604, // L'Amour ouf (2024), 4.7 M
  643215, // Astérix et Obélix : L'Empire du Milieu (2023), 4.6 M
  967585, // Alibi.com 2 (2023), 4.3 M
  796185, // Les Trois Mousquetaires : D'Artagnan (2023), 3.4 M
  1137759, // God Save the Tuche (2025), 3.0 M
  577242, // Kaamelott : Premier Volet (2021), 2.65 M
  714869, // Qu'est-ce qu'on a tous fait au Bon Dieu ? (2022), 2.4 M
  740937, // Simone, le voyage du siècle (2022), 2.4 M
  823951, // Novembre (2022), 2.4 M
  637534, // BAC Nord (2021), 2.2 M
  1259983, // Gourou (2026), 2.0 M by July 2026
  1404684, // Juste une illusion (2026), 1.9 M by July 2026
];

/// The 2010s, per the CNC.
const frenchHits2010s = [
  77338, // Intouchables (2011), 19.5 M
  262391, // Qu'est-ce qu'on a fait au Bon Dieu ? (2014), 12.4 M
  52077, // Rien à déclarer (2011), 8.1 M
  304410, // La Famille Bélier (2014), 7.7 M
  505436, // Qu'est-ce qu'on a encore fait au Bon Dieu ? (2019), 6.7 M
  424619, // Les Tuche 3 (2018), 5.7 M
  456165, // La Ch'tite Famille (2018), 5.6 M
  48034, // Les Petits Mouchoirs (2010), 5.5 M
  102207, // Sur la piste du Marsupilami (2012), 5.3 M
  248507, // Supercondriaque (2014), 5.3 M
];

/// All time, per CBO Box-Office.
const frenchHitsAllTime = [
  8265, // Bienvenue chez les Ch'tis (2008), 20.4 M
  77338, // Intouchables (2011), 19.5 M
  8290, // La Grande Vadrouille (1966), 17.3 M
  2899, // Astérix et Obélix : Mission Cléopâtre (2002), 14.4 M
  11687, // Les Visiteurs (1993), 13.7 M
  11972, // Le Petit Monde de don Camillo (1952), 12.8 M
  262391, // Qu'est-ce qu'on a fait au Bon Dieu ? (2014), 12.4 M
  25866, // Le Corniaud (1965), 11.7 M
  1152014, // Un p'tit truc en plus (2024), 10.8 M
  2332, // Taxi 2 (2000), 10.3 M
];

/// The lists by the year their decade starts.
const frenchHitsByDecade = {2020: frenchHits2020s, 2010: frenchHits2010s};

/// The year the decade of [now] starts.
int decadeOf(DateTime now) => now.year ~/ 10 * 10;
