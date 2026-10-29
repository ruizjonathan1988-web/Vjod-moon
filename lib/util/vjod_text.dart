/// VJOD's own words, in the languages of the house (French, English, Russian,
/// Chinese), for the few places written for VJOD rather than translated with
/// Moonfin's catalogue.
library;

import 'package:flutter/widgets.dart';

String vjodText(
  BuildContext context, {
  required String fr,
  required String en,
  String? ru,
  String? zh,
}) {
  final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'fr';
  return switch (lang) {
    'fr' => fr,
    'ru' => ru ?? en,
    'zh' => zh ?? en,
    _ => en,
  };
}

/// When a VJOD build was published, read at a glance: « 29/10 à 13h53 ».
String vjodBuildDate(BuildContext context, DateTime at) {
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final day = '${two(t.day)}/${two(t.month)}';
  return vjodText(
    context,
    fr: '$day à ${t.hour}h${two(t.minute)}',
    en: '$day at ${t.hour}:${two(t.minute)}',
    ru: '$day в ${t.hour}:${two(t.minute)}',
    zh: '${t.month}月${t.day}日 ${t.hour}:${two(t.minute)}',
  );
}
