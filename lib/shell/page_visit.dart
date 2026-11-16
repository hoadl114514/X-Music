import 'package:flutter/widgets.dart';

/// 主框架里某个页面被切回来的次数。页面切走后不销毁（见 AppShell），需要回来时刷新的页面
/// （最近播放、我喜欢、听歌排行）放在它下面，次数一变就在后台刷新，列表不清空。
class PageVisit extends InheritedWidget {
  const PageVisit({super.key, required this.count, required super.child});

  final int count;

  /// 最近的 [PageVisit] 的次数；不在主框架的这类页面里（例如推进来的子页面）时为 null。
  static int? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageVisit>()?.count;

  @override
  bool updateShouldNotify(PageVisit old) => old.count != count;
}
