import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../library/track_list_view.dart';
import '../login_page.dart';

/// 最近播放（账号的云端记录，最多 300 首）。
class RecentPage extends StatelessWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    if (!account.isLoggedIn) return const LoginPrompt(message: '登录后查看最近播放');
    final services = AppScope.of(context);
    final uid = account.profile!.userId;
    return TrackListView(
      reloadKey: uid,
      // 先显示上次的记录，后台再取最新的。
      watch: (force) => services.data.watch(
        'recent_$uid',
        fetch: services.api.recentSongs,
        encode: (songs) => [for (final s in songs) s.toJson()],
        decode: (j) => j is List ? [for (final s in j) ?Song.fromJson(s)] : null,
        force: force,
      ),
      queueTitle: '最近播放',
      emptyText: '还没有播放记录',
      header: (context, tracks, playAll) => CollectionHeader(
        title: '最近播放',
        seed: 'recent',
        icon: Icons.history_rounded,
        lines: [if (tracks.isNotEmpty) '${tracks.length} 首'],
        onPlayAll: playAll,
      ),
    );
  }
}
