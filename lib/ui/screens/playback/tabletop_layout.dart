import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../layout/screen_form.dart';

/// Lays the player out for a half-folded phone: the picture on the upper
/// half, a control deck on the lower half resting on the table, the way
/// YouTube does on Samsung's Flex mode.
///
/// Builds the same tree in every posture so [child] keeps its state, focus
/// and video surface when the phone is folded or opened mid-playback.
class TabletopLayout extends StatelessWidget {
  final bool enabled;
  final Widget child;
  final WidgetBuilder panelBuilder;

  const TabletopLayout({
    super.key,
    required this.enabled,
    required this.child,
    required this.panelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Tabletop.forced,
      builder: (context, _, _) => _layout(context),
    );
  }

  Widget _layout(BuildContext context) {
    final media = MediaQuery.of(context);
    final fold = enabled ? Tabletop.foldIn(context) : null;
    final topHeight = fold?.top ?? media.size.height;
    final bottomInset = media.size.height - topHeight;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: bottomInset,
          child: MediaQuery(
            // The player sizes its overlays from MediaQuery, so tell it how
            // much screen it really has.
            data: fold == null
                ? media
                : media.copyWith(
                    size: Size(media.size.width, topHeight),
                    padding: media.padding.copyWith(bottom: 0),
                    viewPadding: media.viewPadding.copyWith(bottom: 0),
                  ),
            child: child,
          ),
        ),
        if (fold != null)
          Positioned(
            left: 0,
            right: 0,
            top: fold.bottom,
            bottom: 0,
            child: panelBuilder(context),
          ),
      ],
    );
  }
}

/// The lower half in tabletop posture, the half that rests on the table:
/// the title, then the player's own seek bar, transport and buttons, so
/// nothing is left over the picture and nothing is drawn twice.
class TabletopControlPanel extends StatelessWidget {
  final String title;
  final Widget seekbar;
  final Widget transport;
  final Widget buttons;

  /// Ends a tabletop posture turned on by hand. Null when the hinge reports
  /// the posture itself.
  final VoidCallback? onExit;

  const TabletopControlPanel({
    super.key,
    required this.title,
    required this.seekbar,
    required this.transport,
    required this.buttons,
    this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onExit = this.onExit;
    return ColoredBox(
      color: const Color(0xFF0B0B0D),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.spaceLg,
            vertical: AppSpacing.spaceMd,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onExit != null)
                    TextButton.icon(
                      onPressed: onExit,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      icon: const Icon(Icons.fullscreen_rounded),
                      label: Text(l10n.foldTabletopExit),
                    ),
                ],
              ),
              seekbar,
              transport,
              buttons,
            ],
          ),
        ),
      ),
    );
  }
}
