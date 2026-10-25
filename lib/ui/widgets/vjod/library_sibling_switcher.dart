import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/aggregated_library.dart';
import '../../../data/repositories/user_views_repository.dart';
import '../../../util/game_library.dart';
import '../../../util/platform_detection.dart';
import '../../../util/secondary_library.dart';
import 'vjod_widgets.dart';

/// Chips over a movies or series library that switch to its other language
/// copies: "Films · Films RU". Without such copies it is just [child], so most
/// accounts never see it.
class LibrarySiblingSwitcher extends StatefulWidget {
  final String libraryId;
  final Widget child;

  const LibrarySiblingSwitcher({
    super.key,
    required this.libraryId,
    required this.child,
  });

  @override
  State<LibrarySiblingSwitcher> createState() => _LibrarySiblingSwitcherState();
}

class _LibrarySiblingSwitcherState extends State<LibrarySiblingSwitcher> {
  List<AggregatedLibrary> _siblings = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LibrarySiblingSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId != widget.libraryId) _load();
  }

  Future<void> _load() async {
    if (widget.libraryId.isEmpty ||
        !GetIt.instance.isRegistered<UserViewsRepository>()) {
      return;
    }
    try {
      final views = await GetIt.instance<UserViewsRepository>().getUserViews();
      AggregatedLibrary? current;
      for (final view in views) {
        if (view.id == widget.libraryId) current = view;
      }
      if (current == null) return;
      final type = current.collectionType.toLowerCase();
      if (type != 'movies' && type != 'tvshows') return;
      final siblings = [
        for (final view in views)
          if (view.collectionType.toLowerCase() == type) view,
      ];
      // Main libraries first, the language copies after.
      siblings.sort((a, b) {
        final left = isSecondaryLibraryName(a.name) ? 1 : 0;
        final right = isSecondaryLibraryName(b.name) ? 1 : 0;
        return left.compareTo(right);
      });
      final hasCopy = siblings.any((s) => isSecondaryLibraryName(s.name));
      if (!mounted) return;
      setState(() => _siblings = hasCopy ? siblings : const []);
    } catch (_) {
      // No chips is a fine fallback: the library itself still shows.
    }
  }

  String _label(AggregatedLibrary lib) {
    final mains = _siblings
        .where((s) => !isSecondaryLibraryName(s.name))
        .length;
    if (!isSecondaryLibraryName(lib.name) && mains > 1) return lib.name;
    return libraryChipLabel(lib.name, lib.collectionType);
  }

  void _open(AggregatedLibrary lib) {
    if (lib.id == widget.libraryId) return;
    final route = libraryRoute(
      lib.id,
      lib.collectionType,
      lib.name,
      serverId: lib.serverId,
    );
    final router = GoRouter.of(context);
    if (PlatformDetection.isWeb) {
      router.go(route);
    } else {
      router.pushReplacement(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // One shape whether the chips show or not, so the page under them keeps
    // its state and focus when they arrive.
    final show = _siblings.length > 1;
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        if (show) _chips(top),
        // The chips took the status bar's room, so the page under them
        // doesn't leave it a second time.
        Expanded(
          key: const ValueKey('library-page'),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: show,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  Widget _chips(double top) {
    return Padding(
      padding: EdgeInsets.only(top: top + 10, left: 16, right: 16, bottom: 4),
      child: Center(
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final lib in _siblings)
              VjodFocusable(
                onTap: () => _open(lib),
                builder: (context, focused) {
                  final selected = lib.id == widget.libraryId;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? vjodRed : vjodButton,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: focused ? vjodInk : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      _label(lib),
                      style: TextStyle(
                        color: vjodInk,
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
