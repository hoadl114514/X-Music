import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// 入口卡片（M3 填充卡片）：上面图标、下面名字，点了打开一个页面。音乐库顶部的快捷入口用它。
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.onSecondaryContainer),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
