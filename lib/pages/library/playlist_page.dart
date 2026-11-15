import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../shell/player_bar.dart';
import '../../state/account_controller.dart';
import '../social/compose_event_page.dart';
import 'playlist_editor.dart';
import 'playlist_view.dart';

/// 歌单页。自己创建的歌单右上角可以编辑、删除；登录后都可以分享到动态。
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    // 编辑后用账号歌单列表里的最新信息。
    final p = account.latest(playlist);
    final own = account.isOwn(p) && !p.isLikedList;
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          if (own)
            IconButton(
              tooltip: '管理歌单',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => showPlaylistManageSheet(
                context,
                p,
                onDeleted: () {
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
            )
          else if (account.isLoggedIn)
            IconButton(
              tooltip: '分享到动态',
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () => ComposeEventPage.open(context, playlist: p),
            ),
        ],
      ),
      body: PlaylistView(playlist: p),
      extendBody: true,
      bottomNavigationBar: const FloatingBottomBar(),
    );
  }
}
