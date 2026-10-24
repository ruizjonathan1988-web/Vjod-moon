import 'package:flutter/material.dart';

import '../theme_spec.dart';

/// Écrin: the calm alternative to VJOD. Warm graphite, generous rounding,
/// soft shadows instead of halos, and a terracotta accent that never raises
/// its voice but still carries the white text the app sets on it.
const ecrinThemeSpec = ThemeSpec(
  id: 'ecrin',
  displayName: 'Écrin',
  semantic: ThemeSemanticTokens(
    statusAvailable: Color(0xFF8FD4A8),
    statusRequested: Color(0xFFE6C48A),
    statusPending: Color(0xFFE6C48A),
    statusDownloading: Color(0xFF9DBFEA),
    statusError: Color(0xFFE08A80),
    mediaTypeBadgeMovie: Color(0xFF9DBFEA),
    mediaTypeBadgeShow: Color(0xFFD1B3E0),
  ),
  colors: ThemeColorTokens(
    background: Color(0xFF0F0E0D),
    onBackground: Color(0xFFF5F2EE),
    surface: Color(0xFF1A1816),
    onSurface: Color(0xFFF5F2EE),
    surfaceVariant: Color(0xFF24211E),
    scrim: Color(0xD90F0E0D),
    accent: Color(0xFFB4553A),
    onAccent: Color(0xFFFFFFFF),
    buttonNormal: Color(0xFF2A2724),
    buttonFocused: Color(0xFFF5F2EE),
    buttonDisabled: Color(0xFF1E1C1A),
    buttonActive: Color(0xFF38342F),
    onButtonNormal: Color(0xFFF5F2EE),
    onButtonFocused: Color(0xFF0F0E0D),
    onButtonDisabled: Color(0x80F5F2EE),
    inputBackground: Color(0xFF24211E),
    inputFocused: Color(0xFF2E2A26),
    inputBorder: Color(0xFF3A3530),
    inputBorderFocused: Color(0xFFF5F2EE),
    rangeTrack: Color(0x40F5F2EE),
    rangeProgress: Color(0xFFF5F2EE),
    rangeThumb: Color(0xFFF5F2EE),
    seekbarBuffered: Color(0x66F5F2EE),
    badgeBackground: Color(0xFFB4553A),
    onBadge: Color(0xFFFFFFFF),
    badgeUnplayed: Color(0xFFB4553A),
    badgeWatched: Color(0xFF8FD4A8),
    recordingActive: Color(0xFFC95A4A),
    recordingScheduled: Color(0xFFE6C48A),
    error: Color(0xFFE08A80),
  ),
  borders: ThemeBorderTokens(
    cardBorder: BorderSide(color: Colors.transparent),
    chipBorder: BorderSide(color: Color(0x29F5F2EE)),
    focusBorder: BorderSide(color: Color(0xE6F5F2EE), width: 2.5),
    cardRadius: BorderRadius.all(Radius.circular(12)),
    chipRadius: BorderRadius.all(Radius.circular(999)),
    chipBackground: Color(0x1AF5F2EE),
    focusGlow: [
      BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 14)),
    ],
  ),
);
