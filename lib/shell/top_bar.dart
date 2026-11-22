import 'package:flutter/material.dart';

import '../pages/login_page.dart';
import '../pages/music/nav.dart';
import '../pages/settings_page.dart';
import '../state/account_controller.dart';
import '../theme/app_theme.dart';

/// 顶栏：左边当前页面的大标题，右边「⋮」菜单（设置、账户）。搜索放在底栏的「搜索」标签里。
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
          const _MoreMenu(),
        ],
      ),
    );
  }
}

enum _MenuItem { settings, account }

/// 右上角的圆形「⋮」按钮，点开一个圆角菜单：设置、账户。
class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  void _onSelected(BuildContext context, _MenuItem item) {
    switch (item) {
      case _MenuItem.settings:
        SubPage.push(context, const SubPage(title: '设置', body: SettingsPage()));
      case _MenuItem.account:
        final profile = AccountScope.read(context).profile;
        if (profile == null) {
          LoginPage.open(context);
        } else {
          openUser(context, profile.userId, name: profile.nickname);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurface);
    PopupMenuItem<_MenuItem> item(_MenuItem value, String label) => PopupMenuItem(
      value: value,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(label, style: style),
    );
    return PopupMenuButton<_MenuItem>(
      tooltip: '更多',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: scheme.surfaceContainerHighest,
      // 不要投影：深色下投影是一圈黑边，靠细描边和底色区分层级。
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 160),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => [item(_MenuItem.settings, '设置'), item(_MenuItem.account, '账户')],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.more_vert_rounded, color: scheme.onSurface),
      ),
    );
  }
}
