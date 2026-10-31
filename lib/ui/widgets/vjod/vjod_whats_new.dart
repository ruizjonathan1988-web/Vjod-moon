// Once after VJOD updates itself: « VJOD 4.1 : ce qui change », from the
// list kept in vjod_changes.dart. The update installs on its own, so this is
// where the household learns what it brought.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../util/vjod_build.dart';
import '../../../util/vjod_changes.dart';
import '../../../util/vjod_text.dart';
import '../track_selector_dialog.dart';

const _seenKey = 'vjod_seen_version';

/// Shows the new version's changes once, the first time home opens on it.
Future<void> maybeShowVjodWhatsNew(BuildContext context) async {
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    return;
  }
  const current = VjodBuild.version;
  if (prefs.getString(_seenKey) == current) return;
  await prefs.setString(_seenKey, current);
  final release = vjodReleases.where((r) => r.version == current).firstOrNull;
  if (release == null || release.changes.isEmpty || !context.mounted) return;
  await showStyledPlayerDialog<void>(
    context,
    title: vjodText(
      context,
      fr: 'VJOD $current : ce qui change',
      en: 'VJOD $current: what’s new',
      ru: 'VJOD $current: что нового',
      zh: 'VJOD $current 新功能',
    ),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final change in release.changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $change', style: Theme.of(ctx).textTheme.bodyMedium),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  );
}
