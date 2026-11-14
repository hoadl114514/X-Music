import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app.dart';
import '../pages/home_page.dart';
import '../pages/library/liked_page.dart';
import '../pages/login_page.dart';
import '../pages/music/discover_page.dart';
import '../pages/music/nav.dart';
import '../pages/music/ranking_page.dart';
import '../pages/music/recent_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../pages/social/follow_page.dart';
import '../pages/social/messages_page.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/hover_builder.dart';
import 'desktop_player_bar.dart';
import 'destinations.dart';
import 'user_avatar.dart';

/// 窗口宽度达到这个值时用电脑布局，窄于它退回手机布局。
const double desktopBreakpoint = 840;

/// 标记当前处在电脑布局里。页面据此隐藏手机端的悬浮播放条。
class DesktopShellScope extends InheritedWidget {
  const DesktopShellScope({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopShellScope>() != null;

  @override
  bool updateShouldNotify(DesktopShellScope old) => false;
}

/// 电脑布局：左侧导航栏、右侧内容区、底部常驻播放条。
///
/// 内容区有自己的导航栈：歌单、歌手这些二级页面在内容区里打开，
/// 导航栏和播放条一直留在原位。播放页仍然盖住整个窗口。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  /// 内容区的导航栈。电脑布局没显示时为 null。
  static NavigatorState? get contentNavigator => _navigatorKey.currentState;

  static final _navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'desktop-content');

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  Destination _current = Destination.forYou;
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).updates?.checkOnLaunch(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _notices ??= PlayerScope.read(context).notices.listen(AppScope.toast);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _notices?.cancel();
    super.dispose();
  }

  /// 应用内快捷键：空格播放 / 暂停。正在输入文字时不拦截。
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.space) return false;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    if (!mounted || PlayerScope.read(context).current == null) return false;
    unawaited(PlayerScope.read(context).toggle());
    return true;
  }

  Widget _page(Destination d) => switch (d) {
    Destination.forYou => HomePage(onNavigate: _go),
    Destination.liked => const LikedPage(),
    Destination.discover => const DiscoverPage(),
    Destination.recent => const RecentPage(),
    Destination.ranking => const RankingPage(),
    Destination.settings => const SettingsPage(),
    Destination.follow => const FollowPage(),
    Destination.updates => const MyEventsPage(),
  };

  Route<void> _root(Destination d) => PageRouteBuilder<void>(
    settings: RouteSettings(name: d.name),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => Material(color: AppColors.background, child: _page(d)),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );

  /// 切换一级页面：清空内容区的导航栈。
  void _go(Destination d) {
    setState(() => _current = d);
    DesktopShell._navigatorKey.currentState?.pushAndRemoveUntil(_root(d), (_) => false);
  }

  /// 在内容区里打开页面（搜索、登录、私信……）。
  void _open(Future<void> Function(BuildContext context) open) {
    final nav = DesktopShell._navigatorKey.currentState;
    if (nav != null) unawaited(open(nav.context));
  }

  /// 鼠标侧键「后退」：内容区返回上一页。
  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons & kBackMouseButton != 0) {
      unawaited(DesktopShell._navigatorKey.currentState?.maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return DesktopShellScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          onPointerDown: _onPointerDown,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _Sidebar(current: _current, onSelect: _go, onOpen: _open),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          child: ColoredBox(
                            color: AppColors.background,
                            child: HeroControllerScope.none(
                              child: Navigator(
                                key: DesktopShell._navigatorKey,
                                onGenerateInitialRoutes: (_, _) => [_root(_current)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const DesktopPlayerBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左侧导航栏：账号、搜索、各个入口。
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect, required this.onOpen});

  final Destination current;
  final ValueChanged<Destination> onSelect;
  final void Function(Future<void> Function(BuildContext context) open) onOpen;

  static const width = 232.0;

  @override
  Widget build(BuildContext context) {
    final profile = AccountScope.of(context).profile;
    Widget item(Destination d) =>
        _NavItem(icon: d.icon, label: d.label, selected: d == current, onTap: () => onSelect(d));
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NavItem(
              leading: const UserAvatar(size: 28),
              label: profile?.nickname ?? '点击登录',
              bold: true,
              onTap: () => onOpen(
                (c) => profile == null
                    ? LoginPage.open(c)
                    : openUser(c, profile.userId, name: profile.nickname),
              ),
            ),
            const SizedBox(height: 8),
            _SearchButton(onTap: () => onOpen(SearchPage.start)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final d in Destination.tabs.take(3)) item(d),
                  const _SectionLabel('我的音乐'),
                  item(Destination.liked),
                  item(Destination.recent),
                  item(Destination.ranking),
                  const _SectionLabel('社区'),
                  item(Destination.updates),
                  _NavItem(
                    icon: Icons.mail_outline_rounded,
                    label: '私信',
                    onTap: () => onOpen(MessagesPage.open),
                  ),
                ],
              ),
            ),
            item(Destination.settings),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    this.icon,
    this.leading,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.bold = false,
  });

  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: HoverBuilder(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cardHover
                : hovered
                ? AppColors.surfaceHigh
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              leading ??
                  Icon(
                    icon,
                    size: 22,
                    color: selected ? AppColors.accent : AppColors.textSecondary,
                  ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected || bold ? FontWeight.w700 : FontWeight.w500,
                    color: selected || bold || hovered
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '搜索',
      excludeSemantics: true,
      child: HoverBuilder(
        onTap: onTap,
        builder: (context, hovered) => Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered ? AppColors.cardHover : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text('搜索音乐、歌手', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
