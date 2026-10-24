import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// The big outlined rank a Top 10 card wears in its bottom-left corner.
///
/// Sized from the card itself, so it reads the same on a phone poster and
/// on a TV row. Meant for [MediaCard.imageOverlays].
class RankNumberOverlay extends StatelessWidget {
  final int rank;

  const RankNumberOverlay({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = (constraints.maxHeight * 0.42).clamp(28.0, 140.0);
            final text = '$rank';
            final base = TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: -size * 0.06,
            );
            return Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.only(left: size * 0.08, bottom: size * 0.02),
                child: Stack(
                  children: [
                    Text(
                      text,
                      style: base.copyWith(
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = (size * 0.06).clamp(2.0, 6.0)
                          ..color = Colors.white,
                      ),
                    ),
                    Text(
                      text,
                      style: base.copyWith(
                        color: Colors.black.withValues(alpha: 0.82),
                        shadows: const [
                          Shadow(blurRadius: 12, color: Colors.black54),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A small pill along the bottom of a card, like the "Recently added"
/// ribbon on Netflix. Meant for [MediaCard.imageOverlays].
class CardHighlightPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// Defaults to the accent colour.
  final Color? color;

  /// Draws a small bar under the label, from 0 to 1, for a download.
  final double? progress;

  const CardHighlightPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? AppColorScheme.accent,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(blurRadius: 6, color: Colors.black45),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 14, color: Colors.white),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  if (progress case final value?) ...[
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 72,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: value.clamp(0.0, 1.0),
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
