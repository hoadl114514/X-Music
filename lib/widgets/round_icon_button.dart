import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 圆形图标按钮。[filled] 为 true 时带底色（播放键、窗口按钮之类）。
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize,
    this.filled = false,
    this.background,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double? iconSize;
  final bool filled;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: size,
      child: Material(
        type: MaterialType.circle,
        color: filled ? (background ?? context.colors.surfaceHigh) : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          hoverColor: Colors.white.withValues(alpha: 0.08),
          child: Icon(
            icon,
            size: iconSize ?? size * 0.5,
            color: color ?? (filled ? context.colors.textPrimary : context.colors.textSecondary),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
