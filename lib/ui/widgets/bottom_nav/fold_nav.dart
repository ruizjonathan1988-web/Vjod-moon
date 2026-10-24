import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../layout/screen_form.dart';
import '../../screens/tonight/tonight_screen.dart';
import 'bottom_nav_controller.dart';
import 'bottom_nav_destinations.dart';
import 'bottom_nav_metrics.dart';
import 'bottom_nav_model.dart';
import 'bottom_nav_tab.dart';
import 'bottom_nav_theme.dart';
import 'bottom_navbar.dart';

/// Sizes of the navigation drawn on an opened foldable.
abstract final class FoldNavMetrics {
  /// Room the rail takes along the left edge, before the system inset.
  static const double railWidth = 84;
  static const double railCellHeight = 62;
  static const double railRadius = 24;

  static const double panelTileHeight = 76;
}

/// The bottom navbar's controller, items and taps, shared by the rail and the
/// tabletop panel so both behave exactly like the bar they replace.
mixin _BarHost<T extends StatefulWidget> on State<T> {
  final controller = BottomNavController();

  String? get activeRoute;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  List<BottomNavItemView> viewsFor(
    List<BottomNavBarItem> items,
    BottomNavTheme theme,
    AppLocalizations l10n,
  ) => [
    for (final item in items)
      bottomNavItemView(
        item,
        l10n,
        badge: controller.hubBadge,
        avatar: (active, size, color) => BottomNavAvatar(
          imageUrl: controller.userImageUrl,
          name: controller.userName,
          size: BottomNavMetrics.avatarSize,
          ring: active ? color : theme.onBar.withValues(alpha: 0.18),
          fallbackColor: theme.onBar,
        ),
      ),
  ];

  // The sheets open from the bottom like they do over Dock: a rail has no
  // bottom edge of its own to anchor them to.
  void tap(BottomNavBarItem item, BottomNavTheme theme) => openBottomNavItem(
    context,
    item: item,
    controller: controller,
    theme: theme,
    style: BottomNavbarStyle.dock,
    barHeight: MediaQuery.paddingOf(context).bottom,
    activeRoute: activeRoute,
  );

  void openTonight() {
    HapticFeedback.selectionClick();
    showTonight(context);
  }
}

/// The navigation of an opened foldable or a tablet: the bottom navbar's
/// tabs down the left edge, where the thumb rests when the phone is held
/// open, with Tonight under them and You at the foot.
class NavRail extends StatefulWidget {
  final String? activeRoute;

  const NavRail({super.key, this.activeRoute});

  /// Room the rail takes, the system inset on its side included.
  static double widthFor(BuildContext context) =>
      FoldNavMetrics.railWidth + MediaQuery.paddingOf(context).left;

  @override
  State<NavRail> createState() => _NavRailState();
}

class _NavRailState extends State<NavRail> with _BarHost<NavRail> {
  @override
  String? get activeRoute => widget.activeRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = BottomNavTheme.resolve(context);
    final items = controller.barItems();
    final views = viewsFor(items, theme, l10n);
    final active = activeBarIndex(
      items,
      widget.activeRoute,
      hubOpen: controller.hubOpen,
    );
    final padding = MediaQuery.paddingOf(context);
    final canPose = Tabletop.canForce(MediaQuery.sizeOf(context));
    // You always closes the list.
    final you = items.length - 1;

    Widget cell(int i) => _RailCell(
      view: views[i],
      active: i == active,
      theme: theme,
      onTap: () => tap(items[i], theme),
    );

    return SizedBox(
      width: NavRail.widthFor(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          padding.left + 10,
          padding.top + 10,
          6,
          BottomNavMetrics.floatingBottomGap(padding.bottom),
        ),
        child: BottomNavSurface(
          theme: theme,
          radius: FoldNavMetrics.railRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < you; i++) cell(i),
                        _RailCell(
                          view: BottomNavItemView(
                            id: 'tonight',
                            label: l10n.tonightButton,
                            slot: 0,
                            icon: (_, size, _) => Icon(
                              Icons.nights_stay_rounded,
                              size: size,
                              color: theme.accent,
                            ),
                          ),
                          active: false,
                          theme: theme,
                          color: theme.accent,
                          onTap: openTonight,
                        ),
                      ],
                    ),
                  ),
                ),
                if (canPose)
                  _RailCell(
                    view: BottomNavItemView(
                      id: 'tabletop',
                      label: l10n.foldTabletopShort,
                      slot: 0,
                      icon: (_, size, color) => Icon(
                        Icons.laptop_rounded,
                        size: size,
                        color: color,
                      ),
                    ),
                    active: false,
                    theme: theme,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Tabletop.forced.value = true;
                    },
                  ),
                if (you >= 0) cell(you),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailCell extends StatelessWidget {
  final BottomNavItemView view;
  final bool active;
  final BottomNavTheme theme;
  final VoidCallback onTap;

  /// Overrides the slot colours, for Tonight's accent.
  final Color? color;

  const _RailCell({
    required this.view,
    required this.active,
    required this.theme,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint =
        color ??
        (active
            ? theme.activeColor(view.slot)
            : theme.inactiveColor(view.slot));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: FoldNavMetrics.railCellHeight,
        decoration: BoxDecoration(
          color: active
              ? theme.indicatorColor(view.slot).withValues(alpha: 0.24)
              : Colors.transparent,
          borderRadius: AppRadius.circular(BottomNavMetrics.indicatorRadius),
        ),
        child: BottomNavTabCell(
          item: view,
          active: active,
          color: tint,
          labelStyle: theme.label(active: active, color: tint),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// The lower half of the screen in tabletop posture, the half that rests on
/// the table: big targets for every tab, Tonight, and the way back to a flat
/// screen when the posture was turned on by hand.
class TabletopNavPanel extends StatefulWidget {
  final String? activeRoute;

  /// Ends a tabletop posture turned on by hand. Null when the hinge reports
  /// the posture itself, which only unfolding the phone ends.
  final VoidCallback? onExit;

  const TabletopNavPanel({super.key, this.activeRoute, this.onExit});

  @override
  State<TabletopNavPanel> createState() => _TabletopNavPanelState();
}

class _TabletopNavPanelState extends State<TabletopNavPanel>
    with _BarHost<TabletopNavPanel> {
  @override
  String? get activeRoute => widget.activeRoute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = BottomNavTheme.resolve(context);
    final items = controller.barItems();
    final views = viewsFor(items, theme, l10n);
    final active = activeBarIndex(
      items,
      widget.activeRoute,
      hubOpen: controller.hubOpen,
    );
    final onExit = widget.onExit;

    return ColoredBox(
      color: theme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: FoldNavMetrics.panelTileHeight,
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _RailCell(
                          view: views[i],
                          active: i == active,
                          theme: theme,
                          onTap: () => tap(items[i], theme),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _PanelButton(
                      icon: Icons.nights_stay_rounded,
                      label: l10n.tonightButton,
                      background: AppColorScheme.accent,
                      foreground: AppColorScheme.onAccent,
                      onTap: openTonight,
                    ),
                  ),
                  if (onExit != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PanelButton(
                        icon: Icons.fullscreen_rounded,
                        label: l10n.foldTabletopExit,
                        background: theme.onBar.withValues(alpha: 0.1),
                        foreground: theme.onBar,
                        onTap: onExit,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _PanelButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: AppRadius.circular(30),
      child: InkWell(
        borderRadius: AppRadius.circular(30),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 24),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
