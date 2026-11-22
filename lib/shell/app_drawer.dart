import 'package:flutter/material.dart';

import '../app/app.dart';
import '../data/models.dart';
import '../pages/login_page.dart';
import '../pages/music/nav.dart';
import '../pages/social/messages_page.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';
import 'destinations.dart';
import 'user_avatar.dart';

/// 左侧抽屉（Material 3 导航抽屉）：个人资料卡、菜单、私信。
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
        const Padding(padding: EdgeInsets.fromLTRB(28, 16, 28, 8), child: Divider()),
        const _Messages(),
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

/// 抽屉底部的私信：最近几个会话，点标题进完整列表，右上角写新私信。
class _Messages extends StatefulWidget {
  const _Messages();

  @override
  State<_Messages> createState() => _MessagesState();
}

class _MessagesState extends State<_Messages> {
  static const _preview = 4;
  Future<List<Conversation>>? _recent;
  int? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AccountScope.of(context).profile?.userId;
    if (uid != _userId) {
      _userId = uid;
      _recent = uid == null
          ? null
          : AppScope.of(context).api
                .conversations(limit: _preview)
                .then((p) => p.items.take(_preview).toList());
    }
  }

  /// 先关抽屉，再在主界面上打开页面。
  void _go(Future<void> Function(BuildContext context) open) {
    final nav = Navigator.of(context);
    nav.pop();
    open(nav.context);
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => _go(MessagesPage.open),
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '私信',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: context.scheme.onSurfaceVariant),
                      ),
                      Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _go((context) async {
                  final user = await pickFollowedUser(context);
                  if (user != null && context.mounted) await ChatPage.open(context, user);
                }),
                tooltip: '写私信',
                icon: Icon(Icons.edit_square, color: context.colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (recent == null)
            Text('登录后查看私信。', style: TextStyle(fontSize: 14, color: context.colors.textSecondary))
          else
            FutureBuilder<List<Conversation>>(
              future: recent,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = snap.data;
                if (items == null || items.isEmpty) {
                  return Text(
                    snap.hasError ? '私信加载失败，点「私信」重试。' : '还没有私信。',
                    style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
                  );
                }
                return Column(
                  children: [
                    for (final c in items)
                      ConversationTile(
                        conversation: c,
                        onTap: () => _go((context) => ChatPage.open(context, c.user)),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
