import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'user_avatar.dart';

/// 顶栏：左边当前页面的大标题，右边头像（点开抽屉）。搜索放在底栏的「搜索」标签里。
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: Durations.medium1,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
              child: Text(
                title,
                key: ValueKey(title),
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: context.scheme.onSurface),
              ),
            ),
          ),
          Tooltip(
            message: '个人中心',
            child: InkResponse(
              onTap: () => Scaffold.of(context).openDrawer(),
              radius: 24,
              child: const Padding(padding: EdgeInsets.all(4), child: UserAvatar(size: 36)),
            ),
          ),
        ],
      ),
    );
  }
}
