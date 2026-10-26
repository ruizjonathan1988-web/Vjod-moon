import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// The pieces VJOD's screens are drawn from, after its mock-up. They take
/// plain values and callbacks, nothing from the app's services, so a test can
/// draw them on their own and the mock-up can be compared against the result.
///
/// Sizes are the mock-up's own, in its pixels, times [scale]: the TV mock-up
/// is 1280 wide, so a 960-wide TV draws at 0.75.

/// The display face: tall condensed capitals.
const vjodDisplayFont = 'Anton';

/// Ivory for what is selected, the near-black the page sits on, and the
/// muted red kept for small marks.
Color get vjodInk => AppColorScheme.onBackground;
Color get vjodPage => AppColorScheme.background;
Color get vjodButton => AppColorScheme.buttonNormal;
Color get vjodRed => AppColorScheme.accent;

TextStyle vjodDisplay(double size, {Color? color, double height = 1.0}) =>
    TextStyle(
      fontFamily: vjodDisplayFont,
      fontSize: size,
      height: height,
      color: color ?? vjodInk,
      letterSpacing: 0.2,
    );

/// A focusable box that the remote can land on and press, and a finger can
/// tap. [builder] draws it focused or not.
class VjodFocusable extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;

  const VjodFocusable({
    super.key,
    required this.builder,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.onFocusChange,
  });

  @override
  State<VjodFocusable> createState() => _VjodFocusableState();
}

class _VjodFocusableState extends State<VjodFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
      },
      onKeyEvent: (node, event) {
        final custom = widget.onKeyEvent?.call(node, event);
        if (custom != null && custom != KeyEventResult.ignored) return custom;
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, _focused),
        ),
      ),
    );
  }
}

/// The ring the mock-up draws around whatever has focus: a gap the colour of
/// the page, then ivory.
List<BoxShadow> vjodFocusRing(double scale, {bool on = true}) => on
    ? [
        BoxShadow(color: vjodPage, spreadRadius: 3 * scale),
        BoxShadow(color: vjodInk, spreadRadius: 6 * scale),
      ]
    : const [];

// ---------------------------------------------------------------------------
// Navigation

class VjodNavItem {
  final String label;
  final IconData? icon;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const VjodNavItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.badge,
    this.focusNode,
  });
}

/// A narrow screen, like a closed foldable: the tabs move to a bar at the
/// bottom that spans the width, as in the mock-up.
class VjodBottomBar extends StatelessWidget {
  final List<VjodNavItem> tabs;
  const VjodBottomBar({super.key, required this.tabs});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(top: 6, bottom: bottom + 6),
      decoration: BoxDecoration(
        color: vjodPage,
        border: Border(top: BorderSide(color: vjodButton)),
      ),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: VjodFocusable(
                focusNode: tab.focusNode,
                onTap: tab.onTap,
                builder: (context, focused) {
                  final color = tab.selected || focused
                      ? vjodInk
                      : vjodInk.withValues(alpha: 0.55);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              tab.icon ?? Icons.circle_outlined,
                              color: color,
                              size: 24,
                            ),
                            if (tab.badge case final badge? when badge > 0)
                              Positioned(
                                right: -10,
                                top: -6,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                  ),
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: vjodRed,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$badge',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: tab.selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The logo as the user drew it, on its own black, never cut out.
class VjodLogo extends StatelessWidget {
  final double scale;
  const VjodLogo({super.key, this.scale = 1});

  @override
  Widget build(BuildContext context) => Container(
    height: 46 * scale,
    width: 104 * scale,
    decoration: BoxDecoration(
      color: const Color(0xFF040404),
      borderRadius: BorderRadius.circular(10 * scale),
    ),
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    child: Image.asset(
      'assets/images/logo_and_text.png',
      height: 58 * scale,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Text(
        'VJOD',
        style: vjodDisplay(24 * scale, color: const Color(0xFFD3352F)),
      ),
    ),
  );
}

class VjodNavTab extends StatelessWidget {
  final VjodNavItem item;
  final double scale;
  const VjodNavTab({super.key, required this.item, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    return VjodFocusable(
      focusNode: item.focusNode,
      onTap: item.onTap,
      builder: (context, focused) {
        final color = focused
            ? vjodPage
            : item.selected
            ? vjodInk
            : vjodInk.withValues(alpha: 0.7);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 6 * scale,
          ),
          decoration: BoxDecoration(
            color: focused ? vjodInk : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 19 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.badge case final badge? when badge > 0) ...[
                    SizedBox(width: 8 * scale),
                    Container(
                      constraints: BoxConstraints(minWidth: 22 * scale),
                      height: 22 * scale,
                      padding: EdgeInsets.symmetric(horizontal: 5 * scale),
                      decoration: BoxDecoration(
                        color: vjodRed,
                        borderRadius: BorderRadius.circular(11 * scale),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 5 * scale),
              Container(
                height: 3 * scale,
                width: 28 * scale,
                decoration: BoxDecoration(
                  color: item.selected && !focused
                      ? vjodRed
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A round button, the search one and the avatar alike.
class VjodRoundButton extends StatelessWidget {
  final double size;
  final Color background;
  final Widget child;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final double scale;
  final String? semanticLabel;

  const VjodRoundButton({
    super.key,
    required this.size,
    required this.background,
    required this.child,
    required this.onTap,
    this.focusNode,
    this.scale = 1,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: VjodFocusable(
      focusNode: focusNode,
      onTap: onTap,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          boxShadow: vjodFocusRing(scale, on: focused),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    ),
  );
}

/// The top of every VJOD screen: the logo, the five tabs, search and the
/// avatar that opens everything else.
class VjodNavBar extends StatelessWidget {
  final List<VjodNavItem> tabs;
  final VoidCallback onSearch;
  final VoidCallback onAvatar;
  final String avatarInitial;
  final FocusNode? searchFocusNode;
  final FocusNode? avatarFocusNode;
  final Widget? leading;
  final double scale;

  const VjodNavBar({
    super.key,
    required this.tabs,
    required this.onSearch,
    required this.onAvatar,
    required this.avatarInitial,
    this.searchFocusNode,
    this.avatarFocusNode,
    this.leading,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    // A veil of the page colour behind the bar, so the tabs stay readable
    // when posters scroll up underneath them.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14 * scale),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            vjodPage.withValues(alpha: 0.88),
            vjodPage.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: SizedBox(
      height: 60 * scale,
      child: Row(
        children: [
          ?leading,
          if (leading != null) SizedBox(width: 12 * scale),
          VjodLogo(scale: scale),
          SizedBox(width: 18 * scale),
          // The tabs take all the room the logo and buttons leave; a Flexible
          // beside a Spacer gave them half of it.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tab in tabs)
                    Padding(
                      padding: EdgeInsets.only(right: 4 * scale),
                      child: VjodNavTab(item: tab, scale: scale),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          VjodRoundButton(
            size: 48 * scale,
            background: vjodButton,
            focusNode: searchFocusNode,
            onTap: onSearch,
            scale: scale,
            semanticLabel: 'search',
            child: Icon(Icons.search_rounded, color: vjodInk, size: 24 * scale),
          ),
          SizedBox(width: 16 * scale),
          VjodRoundButton(
            size: 44 * scale,
            background: vjodRed,
            focusNode: avatarFocusNode,
            onTap: onAvatar,
            scale: scale,
            semanticLabel: 'profile',
            child: Text(
              avatarInitial,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18 * scale,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar menu

class VjodMenuEntry {
  final IconData icon;
  final String label;
  final String? subtitle;
  final int? badge;
  final VoidCallback onTap;

  const VjodMenuEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.badge,
  });
}

/// What opens behind the avatar: the profile, what isn't a tab, settings.
class VjodMenuPanel extends StatelessWidget {
  final String name;
  final String initial;
  final String? nowWatching;
  final String changeLabel;
  final VoidCallback onChange;
  final String sectionLabel;
  final List<VjodMenuEntry> entries;
  final VjodMenuEntry settings;
  final double scale;

  const VjodMenuPanel({
    super.key,
    required this.name,
    required this.initial,
    required this.changeLabel,
    required this.onChange,
    required this.sectionLabel,
    required this.entries,
    required this.settings,
    this.nowWatching,
    this.scale = 1,
  });

  Widget _row(BuildContext context, VjodMenuEntry e, {bool autofocus = false}) {
    return VjodFocusable(
      autofocus: autofocus,
      onTap: e.onTap,
      builder: (context, focused) {
        final fg = focused ? vjodPage : vjodInk;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: 14 * scale,
            vertical: 10 * scale,
          ),
          decoration: BoxDecoration(
            color: focused ? vjodInk : Colors.transparent,
            borderRadius: BorderRadius.circular(8 * scale),
          ),
          child: Row(
            children: [
              Icon(e.icon, color: fg, size: 22 * scale),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (e.subtitle != null)
                      Text(
                        e.subtitle!,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.6),
                          fontSize: 14 * scale,
                        ),
                      ),
                  ],
                ),
              ),
              if (e.badge case final badge? when badge > 0)
                Container(
                  constraints: BoxConstraints(minWidth: 22 * scale),
                  height: 22 * scale,
                  decoration: BoxDecoration(
                    color: vjodRed,
                    borderRadius: BorderRadius.circular(11 * scale),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final divider = Container(
      height: 1,
      margin: EdgeInsets.symmetric(vertical: 10 * scale),
      color: vjodButton,
    );
    return Container(
      width: 400 * scale,
      padding: EdgeInsets.all(18 * scale),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(14 * scale),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52 * scale,
                height: 52 * scale,
                decoration: BoxDecoration(
                  color: vjodRed,
                  borderRadius: BorderRadius.circular(12 * scale),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: vjodDisplay(26 * scale, color: Colors.white),
                ),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: vjodInk,
                        fontSize: 19 * scale,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (nowWatching != null)
                      Text(
                        nowWatching!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: vjodInk.withValues(alpha: 0.55),
                          fontSize: 14 * scale,
                        ),
                      ),
                  ],
                ),
              ),
              VjodFocusable(
                onTap: onChange,
                builder: (context, focused) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12 * scale,
                    vertical: 8 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: focused ? vjodInk : vjodButton,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 16 * scale,
                        color: focused ? vjodPage : vjodInk,
                      ),
                      SizedBox(width: 6 * scale),
                      Text(
                        changeLabel,
                        style: TextStyle(
                          color: focused ? vjodPage : vjodInk,
                          fontSize: 15 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          divider,
          Padding(
            padding: EdgeInsets.fromLTRB(14 * scale, 0, 14 * scale, 6 * scale),
            child: Text(
              sectionLabel.toUpperCase(),
              style: TextStyle(
                color: vjodInk.withValues(alpha: 0.5),
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          for (final (i, e) in entries.indexed) _row(context, e, autofocus: i == 0),
          divider,
          _row(context, settings),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tonight hero

class VjodHeroAction {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const VjodHeroAction({required this.label, required this.onTap, this.icon});
}

/// The text side of the Tonight banner, as in the mock-up: the evening's
/// answers with Change, why this pick, the title in big capitals, where it
/// stands and when it would end, then the buttons.
class VjodHeroContent extends StatelessWidget {
  final String tonightLabel;
  final List<String> answers;
  final String changeLabel;
  final VoidCallback? onChange;
  final bool changeFocused;
  final String? kicker;
  final String title;
  final String? statusLabel;
  final Color? statusColor;
  final IconData? statusIcon;
  final List<String> meta;
  final String? endsAt;
  final List<VjodHeroAction> actions;

  /// Which button the remote is on, or null while the banner has no focus,
  /// when the first button leads.
  final int? activeAction;
  final double scale;
  final bool compact;

  const VjodHeroContent({
    super.key,
    required this.tonightLabel,
    required this.answers,
    required this.changeLabel,
    required this.title,
    required this.actions,
    this.onChange,
    this.changeFocused = false,
    this.kicker,
    this.statusLabel,
    this.statusColor,
    this.statusIcon,
    this.meta = const [],
    this.endsAt,
    this.activeAction,
    this.scale = 1,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final chipStyle = TextStyle(
      color: vjodInk,
      fontSize: (compact ? 15 : 17) * s,
      fontWeight: FontWeight.w600,
    );
    Widget chip(String text, {bool outlined = false, bool focused = false}) =>
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: (compact ? 11 : 14) * s,
            vertical: 7 * s,
          ),
          decoration: BoxDecoration(
            color: focused
                ? vjodInk
                : outlined
                ? Colors.transparent
                : vjodInk.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: outlined && !focused
                ? Border.all(color: vjodInk.withValues(alpha: 0.4), width: 1.5)
                : null,
          ),
          child: Text(
            text,
            style: focused ? chipStyle.copyWith(color: vjodPage) : chipStyle,
          ),
        );

    final metaStyle = TextStyle(
      color: vjodInk.withValues(alpha: 0.85),
      fontSize: 19 * s,
      fontWeight: FontWeight.w500,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8 * s,
          runSpacing: 8 * s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(right: 4 * s),
              child: Text(
                tonightLabel,
                style: TextStyle(
                  color: vjodInk.withValues(alpha: 0.75),
                  fontSize: 17 * s,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            for (final a in answers) chip(a),
            if (onChange != null)
              GestureDetector(
                onTap: onChange,
                child: chip(changeLabel, outlined: true, focused: changeFocused),
              ),
          ],
        ),
        SizedBox(height: 18 * s),
        if (kicker != null && kicker!.isNotEmpty) ...[
          Text(
            kicker!.toUpperCase(),
            style: TextStyle(
              color: vjodInk.withValues(alpha: 0.85),
              fontSize: 15 * s,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          SizedBox(height: 6 * s),
        ],
        // Always one line: a long title shrinks instead of wrapping, so it
        // never pushes the buttons under the row of cards below.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            style: vjodDisplay(
              (compact ? 44 : 76) * s,
              height: 1.02,
            ).copyWith(
              shadows: const [Shadow(color: Color(0x99000000), blurRadius: 18)],
            ),
          ),
        ),
        SizedBox(height: 10 * s),
        Wrap(
          spacing: 14 * s,
          runSpacing: 4 * s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (statusLabel != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    statusIcon ?? Icons.play_arrow_rounded,
                    size: 16 * s,
                    color: statusColor ?? AppColorScheme.statusAvailable,
                  ),
                  SizedBox(width: 6 * s),
                  Text(
                    statusLabel!,
                    style: metaStyle.copyWith(
                      color: statusColor ?? AppColorScheme.statusAvailable,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            for (final m in meta) Text(m, style: metaStyle),
            if (endsAt != null)
              Text(
                endsAt!,
                style: metaStyle.copyWith(
                  color: vjodInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        SizedBox(height: 20 * s),
        Wrap(
          spacing: 10 * s,
          runSpacing: 10 * s,
          children: [
            for (final (i, a) in actions.indexed)
              VjodButton(
                label: a.label,
                icon: a.icon,
                light: i == (activeAction ?? 0),
                ringed: activeAction != null && i == activeAction,
                onTap: a.onTap,
                scale: s,
                compact: compact,
              ),
          ],
        ),
      ],
    );
  }
}

/// The mock-up's buttons: ivory with dark text for the one that leads or has
/// focus, a dark grey block otherwise.
class VjodButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool light;
  final bool ringed;
  final VoidCallback onTap;
  final double scale;
  final bool compact;

  const VjodButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.light = false,
    this.ringed = false,
    this.scale = 1,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final fg = light ? vjodPage : vjodInk;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: (compact ? 48 : 56) * s,
        padding: EdgeInsets.symmetric(horizontal: (compact ? 16 : 26) * s),
        decoration: BoxDecoration(
          color: light ? vjodInk : vjodButton,
          borderRadius: BorderRadius.circular(6 * s),
          boxShadow: vjodFocusRing(s, on: ringed),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 22 * s),
              SizedBox(width: 8 * s),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: (compact ? 18 : 21) * s,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the three ideas under the banner: what it is above it, the title
/// across it, and a line under it.
class VjodPickCard extends StatelessWidget {
  final String label;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? image;
  final Color placeholder;
  final double? progress;
  final bool selected;
  final bool raised;
  final VoidCallback? onTap;
  final double scale;

  const VjodPickCard({
    super.key,
    required this.label,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.image,
    this.placeholder = const Color(0xFF262B36),
    this.progress,
    this.selected = false,
    this.raised = false,
    this.onTap,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 302 * s,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: vjodInk.withValues(alpha: selected ? 0.95 : 0.7),
                fontSize: 15 * s,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            SizedBox(height: 10 * s),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 170 * s,
              decoration: BoxDecoration(
                color: placeholder,
                borderRadius: BorderRadius.circular(6 * s),
                boxShadow: vjodFocusRing(s, on: selected),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ?image,
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xCC000000), Color(0x00000000)],
                        stops: [0, 0.6],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12 * s,
                    right: 12 * s,
                    bottom: (progress != null ? 16 : 12) * s,
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: vjodDisplay(24 * s),
                    ),
                  ),
                  if (progress case final p?)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 4 * s,
                        color: vjodInk.withValues(alpha: 0.25),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: p.clamp(0.0, 1.0),
                          child: Container(color: vjodInk),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: 10 * s),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: subtitleColor ?? vjodInk.withValues(alpha: 0.65),
                  fontSize: 17 * s,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows

/// A row's title, its grey subtitle beside it, and anything that belongs to
/// the row's head, like the Top 10's Films and Series switch.
class VjodRowHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double scale;

  const VjodRowHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: vjodInk,
                    fontSize: 28 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  TextSpan(
                    text: '   $subtitle',
                    style: TextStyle(
                      color: vjodInk.withValues(alpha: 0.55),
                      fontSize: 18 * s,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[SizedBox(width: 16 * s), trailing!],
      ],
    );
  }
}

/// Two or more choices in one pill, the chosen one ivory.
class VjodSegmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<FocusNode?>? focusNodes;
  final double scale;

  const VjodSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.focusNodes,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.all(4 * s),
      decoration: BoxDecoration(
        color: AppColorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, o) in options.indexed)
            VjodFocusable(
              focusNode: focusNodes?.elementAtOrNull(i),
              onTap: () => onSelect(i),
              builder: (context, focused) {
                final on = i == selected;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * s,
                    vertical: 7 * s,
                  ),
                  decoration: BoxDecoration(
                    color: on ? vjodInk : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: vjodFocusRing(s * 0.6, on: focused),
                  ),
                  child: Text(
                    o,
                    style: TextStyle(
                      color: on ? vjodPage : vjodInk,
                      fontSize: 18 * s,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// The big outlined rank the Top 10 sets beside each poster.
class VjodRankNumeral extends StatelessWidget {
  final int rank;
  final double height;
  const VjodRankNumeral({super.key, required this.rank, required this.height});

  @override
  Widget build(BuildContext context) {
    final base = vjodDisplay(height, height: 1.0);
    return Stack(
      children: [
        Text(
          '$rank',
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = height / 40
              ..color = vjodInk.withValues(alpha: 0.55),
          ),
        ),
        Text('$rank', style: base.copyWith(color: vjodPage)),
      ],
    );
  }
}
