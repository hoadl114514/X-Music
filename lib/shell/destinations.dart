import 'package:flutter/material.dart';

/// 应用内的固定入口。
enum Destination {
  forYou('为我推荐', '首页', Icons.home_rounded),
  discover('发现音乐', '发现', Icons.explore_rounded),
  search('搜索', '搜索', Icons.search_rounded),
  library('音乐库', '音乐库', Icons.library_music_rounded);

  const Destination(this.label, this.shortLabel, this.icon);

  /// 页面标题。
  final String label;

  /// 底部导航用的短名。
  final String shortLabel;
  final IconData icon;

  /// 未选中时的描边图标（M3：选中实心，未选中描边）。
  IconData get outlinedIcon => switch (this) {
    forYou => Icons.home_outlined,
    discover => Icons.explore_outlined,
    search => Icons.search_rounded,
    library => Icons.library_music_outlined,
  };

  /// 底部导航。
  static const tabs = [forYou, discover, search, library];

  /// 切回来时要在后台刷新的页面。
  static const refreshOnVisit = {library};
}
