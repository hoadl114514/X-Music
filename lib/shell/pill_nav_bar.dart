import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 悬浮胶囊的磨砂底：圆角、半透明、背景模糊，和迷你播放条、底部导航共用。
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({super.key, required this.child, this.color, this.radius = 32});

  final Widget child;

  /// 底色，默认 surfaceContainerHigh。会叠上 85% 不透明度。
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: (color ?? scheme.surfaceContainerHigh).withValues(alpha: 0.85),
            shape: shape,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 一个底栏按钮。
class PillNavItem {
  const PillNavItem({required this.icon, required this.label, this.selectedIcon});

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

/// 悬浮胶囊底栏（参考 Apple Music）：图标 + 文字，选中项用主题色并加一块淡色底。
///
/// [selectedIndex] 为 null 时没有选中项。点 [items] 里的按钮调用 [onTap]。
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<PillNavItem> items;
  final int? selectedIndex;
  final ValueChanged<int> onTap;

  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlassCapsule(
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _Item(
                        item: items[i],
                        selected: i == selectedIndex,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.selected, required this.onTap});

  final PillNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            duration: Durations.medium2,
            curve: Easing.emphasizedDecelerate,
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: Durations.medium2,
                  curve: Easing.emphasizedDecelerate,
                  child: Icon(
                    selected ? (item.selectedIcon ?? item.icon) : item.icon,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
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
