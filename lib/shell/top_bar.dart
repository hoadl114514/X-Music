import 'package:flutter/material.dart';

import '../pages/search_page.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

/// 顶栏：Material 3 搜索栏。左侧菜单键打开抽屉，右侧头像也打开抽屉（个人中心在抽屉里）。
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    void openDrawer() => Scaffold.of(context).openDrawer();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        button: true,
        label: '搜索',
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => SearchPage.start(context),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '菜单',
                    onPressed: openDrawer,
                    icon: Icon(Icons.menu_rounded, color: scheme.onSurface),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '搜索音乐、歌手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: '个人中心',
                    child: InkResponse(
                      onTap: openDrawer,
                      radius: 20,
                      child: const UserAvatar(size: 32),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
