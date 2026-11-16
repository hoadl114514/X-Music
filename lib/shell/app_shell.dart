import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../pages/home_page.dart';
import '../pages/library/liked_page.dart';
import '../pages/music/discover_page.dart';
import '../pages/music/new_songs_page.dart';
import '../pages/music/ranking_page.dart';
import '../pages/music/recent_page.dart';
import '../pages/settings_page.dart';
import '../pages/social/follow_page.dart';
import '../state/player_controller.dart';
import 'app_drawer.dart';
import 'destinations.dart';
import 'page_visit.dart';
import 'player_bar.dart';
import 'top_bar.dart';

/// 主框架（手机端）：顶栏 + 内容 + 迷你播放条 + 底部导航，点头像从左侧滑出抽屉。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Destination _current = Destination.forYou;

  /// 进过的页面。切走后不销毁，回来时数据、图片和滚动位置都还在，不用重新加载。
  final _visited = <Destination>{Destination.forYou};

  /// 每个页面被切回来的次数，见 [PageVisit]。
  final _visits = <Destination, int>{};

  /// 最近一次所在的底部标签。从抽屉进入的页面不属于任何标签，此时保持原高亮。
  int _tab = 0;
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    // 启动后查一次新版本，有就弹窗。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).updates?.checkOnLaunch(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 播放器的提示（无版权、试听、音质降级……）统一弹 SnackBar。
    _notices ??= PlayerScope.read(context).notices.listen(AppScope.toast);
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  Widget _page(Destination d) => switch (d) {
    Destination.forYou => HomePage(onNavigate: _go),
    Destination.liked => const LikedPage(),
    Destination.discover => const DiscoverPage(),
    Destination.newSongs => const NewSongsPage(),
    Destination.recent => const RecentPage(),
    Destination.ranking => const RankingPage(),
    Destination.settings => const SettingsPage(),
    Destination.follow => const FollowPage(),
    Destination.updates => const MyEventsPage(),
  };

  void _go(Destination d) => setState(() {
    // 从别的页面切回已经建过的页面：通知它刷新。
    if (d != _current && !_visited.add(d)) _visits[d] = (_visits[d] ?? 0) + 1;
    _current = d;
    final i = Destination.tabs.indexOf(d);
    if (i >= 0) _tab = i;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(onSelect: _go),
      // 抽屉打开时主界面压暗，和参考图一致。
      drawerScrimColor: Colors.black54,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const TopBar(),
            Expanded(
              // 没显示的页面留在后台（动画暂停），只建进过的。
              child: IndexedStack(
                index: _current.index,
                children: [
                  for (final d in Destination.values)
                    _visited.contains(d)
                        ? KeyedSubtree(
                            key: ValueKey(d),
                            child: Destination.refreshOnVisit.contains(d)
                                ? PageVisit(count: _visits[d] ?? 0, child: _page(d))
                                : _page(d),
                          )
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
      // 内容延伸到播放条和底栏下面，两者悬浮在内容上方。
      extendBody: true,
      bottomNavigationBar: FloatingBottomBar(
        navigation: NavigationBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          selectedIndex: _tab,
          onDestinationSelected: (i) => _go(Destination.tabs[i]),
          destinations: [
            for (final d in Destination.tabs)
              NavigationDestination(icon: Icon(d.icon), label: d.shortLabel),
          ],
        ),
      ),
    );
  }
}
