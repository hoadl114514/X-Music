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

/// 左侧抽屉：个人资料卡、菜单、私信。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onSelect});

  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    void pick(Destination d) {
      Navigator.of(context).pop();
      onSelect(d);
    }

    return Drawer(
      width: (width * 0.9).clamp(280.0, 400.0),
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            const _AccountCard(),
            const SizedBox(height: 8),
            for (final d in Destination.drawer) _MenuItem(destination: d, onTap: () => pick(d)),
            const SizedBox(height: 28),
            const _Messages(),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final profile = account.profile;
    void login() {
      Navigator.of(context).pop();
      LoginPage.open(context);
    }

    return Material(
      color: AppColors.cardHover,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      clipBehavior: Clip.antiAlias,
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
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const UserAvatar(size: 60),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.nickname ?? '未登录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profile == null ? '点击登录' : '查看个人资料',
                          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderStrong),
          InkWell(
            onTap: login,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceHigh,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_rounded, size: 20),
                  ),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('切换账号', style: TextStyle(fontSize: 16)),
                        Text(
                          '登录另一个账号',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.destination, required this.onTap});

  final Destination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(destination.icon, size: 28, color: AppColors.textPrimary),
            const SizedBox(width: 18),
            Text(destination.drawerLabel, style: const TextStyle(fontSize: 17)),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => _go(MessagesPage.open),
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: const Row(
                  children: [
                    Text('私信', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _go((context) async {
                  final user = await pickFollowedUser(context);
                  if (user != null && context.mounted) await ChatPage.open(context, user);
                }),
                tooltip: '写私信',
                icon: const Icon(Icons.edit_square, color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (recent == null)
            const Text('登录后查看私信。', style: TextStyle(fontSize: 14, color: AppColors.textSecondary))
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
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
