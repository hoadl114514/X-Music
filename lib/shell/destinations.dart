import 'package:flutter/material.dart';

/// 应用内的固定入口。
enum Destination {
  forYou('为我推荐', '首页', Icons.home_rounded),
  discover('发现音乐', '发现', Icons.explore_rounded),
  follow('关注', '关注', Icons.people_alt_rounded),
  library('音乐库', '音乐库', Icons.library_music_rounded),
  newSongs('新歌速递', '新歌', Icons.fiber_new_rounded),
  recent('最近播放', '最近', Icons.history_rounded),
  ranking('听歌排行', '排行', Icons.show_chart_rounded),
  updates('我的动态', '动态', Icons.campaign_rounded),
  settings('设置', '设置', Icons.settings_rounded);

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
    follow => Icons.people_alt_outlined,
    library => Icons.library_music_outlined,
    newSongs => Icons.fiber_new_outlined,
    recent => Icons.history_rounded,
    ranking => Icons.show_chart_rounded,
    updates => Icons.campaign_outlined,
    settings => Icons.settings_outlined,
  };

  /// 抽屉侧栏里显示的名字：首页叫「首页」，其余用页面标题。
  String get drawerLabel => this == forYou ? shortLabel : label;

  /// 底部导航。
  static const tabs = [forYou, discover, follow, library];

  /// 切回来时要在后台刷新的页面。
  static const refreshOnVisit = {library};

  /// 抽屉侧栏里的菜单。
  static const drawer = [forYou, newSongs, ranking, recent, updates, settings];
}
