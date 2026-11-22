import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// 入口卡片（M3 填充卡片）：图标 + 名字，点了打开一个页面。音乐库、发现页顶部的快捷入口用它。
class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return PressScale(
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
