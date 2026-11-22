import 'package:flutter/material.dart';

import '../pages/login_page.dart';
import '../pages/music/nav.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';
import 'destinations.dart';
import 'user_avatar.dart';

/// 左侧抽屉（Material 3 导航抽屉）：个人资料卡、菜单。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onSelect, this.selected});

  final ValueChanged<Destination> onSelect;

  /// 当前所在的页面，菜单里有它时高亮。
  final Destination? selected;

  @override
  Widget build(BuildContext context) {
    final index = Destination.drawer.indexOf(selected ?? Destination.forYou);
    return NavigationDrawer(
      selectedIndex: index < 0 ? null : index,
      onDestinationSelected: (i) {
        Navigator.of(context).pop();
        onSelect(Destination.drawer[i]);
      },
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        const SizedBox(height: 12),
        const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 12), child: _AccountCard()),
        for (final d in Destination.drawer)
          NavigationDrawerDestination(
            icon: Icon(d.outlinedIcon),
            selectedIcon: Icon(d.icon),
            label: Text(d.drawerLabel),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 抽屉顶部的账号卡（M3 填充卡片）：头像、昵称、切换账号。
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    final account = AccountScope.of(context);
    final profile = account.profile;
    void login() {
      Navigator.of(context).pop();
      LoginPage.open(context);
    }

    return Card(
      color: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: profile == null
                ? login
                : () {
                    Navigator.of(context).pop();
                    openUser(context, profile.userId, name: profile.nickname);
                  },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const UserAvatar(size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.nickname ?? '未登录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(color: scheme.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile == null ? '点击登录' : '查看个人资料',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
          ListTile(
            onTap: login,
            leading: Icon(Icons.switch_account_outlined, color: scheme.onSurfaceVariant),
            title: const Text('切换账号'),
            subtitle: const Text('登录另一个账号'),
          ),
        ],
      ),
    );
  }
}
