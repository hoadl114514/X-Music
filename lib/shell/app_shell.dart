import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../pages/home_page.dart';
import '../pages/library/library_page.dart';
import '../pages/music/discover_page.dart';
import '../pages/create_sheet.dart';
import '../pages/search_page.dart';
import '../state/player_controller.dart';
import '../widgets/motion.dart';
import 'destinations.dart';
import 'page_visit.dart';
import 'pill_nav_bar.dart';
import 'player_bar.dart';
import 'top_bar.dart';

/// 主框架（手机端）：顶栏 + 内容 + 迷你播放条 + 底部导航。顶栏右上角的「⋮」菜单进设置和账户。
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

  /// 当前所在的底部标签。
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
    Destination.library => const LibraryPage(),
    Destination.discover => const DiscoverPage(),
    Destination.search => const SearchPage(embedded: true),
  };

  void _go(Destination d) => setState(() {
    // 从别的页面切回已经建过的页面：通知它刷新。
    if (d != _current && !_visited.add(d)) _visits[d] = (_visits[d] ?? 0) + 1;
    _current = d;
    _tab = Destination.tabs.indexOf(d);
  });

  @override
  Widget build(BuildContext context) {
    // 不在首页标签时，返回手势先回首页，再按一次才退出。
    return PopScope(
      canPop: _current == Destination.forYou,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(Destination.forYou);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 搜索页自带搜索栏，不再显示大标题。
              if (_current != Destination.search) TopBar(title: _current.shortLabel),
              Expanded(
                // 没显示的页面留在后台（动画暂停），只建进过的。
                // 切标签时新页面淡入并轻微放大（M3 fade through）。
                child: FadeThrough(
                  trigger: _current,
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
              ),
            ],
          ),
        ),
        // 内容延伸到播放条和底栏下面，两者悬浮在内容上方。
        extendBody: true,
        bottomNavigationBar: FloatingBottomBar(
          navigation: PillNavBar(
            selectedIndex: _tab,
            // 最后一个是「创建」：不切页面，弹出创建面板。
            onTap: (i) =>
                i < Destination.tabs.length ? _go(Destination.tabs[i]) : showCreateSheet(context),
            items: [
              for (final d in Destination.tabs)
                PillNavItem(icon: d.outlinedIcon, selectedIcon: d.icon, label: d.shortLabel),
              const PillNavItem(icon: Icons.add_circle_outline_rounded, label: '创建'),
            ],
          ),
        ),
      ),
    );
  }
}
