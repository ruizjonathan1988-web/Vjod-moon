/// Short language codes for a file's audio tracks, so a title says at a
/// glance which languages it can be watched in.
library;

const _shortCodes = <String, String>{
  'fre': 'FR',
  'fra': 'FR',
  'fr': 'FR',
  'eng': 'EN',
  'en': 'EN',
  'rus': 'RU',
  'ru': 'RU',
  'ukr': 'UK',
  'uk': 'UK',
  'ger': 'DE',
  'deu': 'DE',
  'de': 'DE',
  'spa': 'ES',
  'es': 'ES',
  'ita': 'IT',
  'it': 'IT',
  'jpn': 'JA',
  'ja': 'JA',
  'chi': 'ZH',
  'zho': 'ZH',
  'zh': 'ZH',
  'kor': 'KO',
  'ko': 'KO',
  'por': 'PT',
  'pt': 'PT',
};

/// The audio languages of [audioStreams] as "FR · EN · RU", in track order,
/// or null when none of the tracks says its language.
String? audioLanguagesLabel(List<Map<String, dynamic>> audioStreams) {
  final codes = <String>[];
  for (final stream in audioStreams) {
    final raw = stream['Language']?.toString().trim().toLowerCase() ?? '';
    if (raw.isEmpty || raw == 'und' || raw == 'mul' || raw == 'zxx') continue;
    final code =
        _shortCodes[raw] ??
        (raw.length >= 2 ? raw.substring(0, 2).toUpperCase() : raw.toUpperCase());
    if (!codes.contains(code)) codes.add(code);
  }
  if (codes.isEmpty) return null;
  return codes.join(' · ');
}
