import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Floating ink pill: tab icons either side of a prominent centre "add"
/// button, so the primary action is one tap from every tab.
class AppBottomNav extends StatelessWidget {
  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;

  const AppBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final half = items.length ~/ 2;

    Widget tab(int i) => Expanded(
      child: _NavButton(
        item: items[i],
        selected: i == selectedIndex,
        onTap: () {
          if (i != selectedIndex) {
            HapticFeedback.selectionClick();
            onSelected(i);
          }
        },
      ),
    );

    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        // Caps the pill's width on tablets/landscape so it stays a compact
        // control instead of stretching edge to edge.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            child: Container(
              height: AppSizes.navBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: p.inkSurface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: AppShadows.floating,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < half; i++) tab(i),
                  _AddButton(onTap: onAdd),
                  for (var i = half; i < items.length; i++) tab(i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Tooltip(
        message: 'Add transaction',
        child: Semantics(
          button: true,
          label: 'Add transaction',
          child: Material(
            color: p.onInk,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: SizedBox(
                width: 64,
                height: 48,
                child: Icon(Icons.add_rounded, size: 28, color: p.inkSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.onInk : p.onInk.withValues(alpha: 0.55);
    final duration = AppDurations.of(context, AppDurations.fast);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: SizedBox(
            height: AppSizes.navBarHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    key: ValueKey(selected),
                    color: fg,
                    size: 22,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AnimatedContainer(
                  duration: duration,
                  width: selected ? 16 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: fg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
