import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../comments/comments_page.dart';
import '../music/nav.dart';
import '../../theme/app_theme.dart';
import '../../widgets/playlist_card.dart';
import 'track_list_view.dart';

/// 歌单内容：头部信息 + 播放全部 + 歌曲列表。歌单页和「我喜欢」共用。
/// 别人的歌单在头部多一个「收藏」按钮。
class PlaylistView extends StatelessWidget {
  const PlaylistView({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    final tracks = AppScope.of(context).tracks;
    // 自己的歌单（含「我喜欢」）和收藏的歌单存本地缓存：先显示缓存，后台比对增删。
    final account = AccountScope.read(context);
    final cache = account.playlists.any((x) => x.id == p.id);
    return TrackListView(
      reloadKey: p.id,
      watch: (force) => tracks.watch(p.id, cache: cache, force: force),
      queueTitle: p.name,
      sourceId: p.id,
      emptyText: '歌单是空的',
      // 自己的歌单和「我喜欢」可以删歌。
      onRemoveSongs: account.canEditTracks(p)
          ? (songs) async {
              await account.removeFromPlaylist(p, songs);
              await tracks.removeCached(p.id, {for (final s in songs) s.id});
            }
          : null,
      header: (context, tracks, playAll) => CollectionHeader(
        title: p.name,
        seed: p.id,
        // 歌单没有封面时用第一首歌的封面。
        coverUrl: p.coverUrl ?? tracks.where((t) => t.coverUrl != null).firstOrNull?.coverUrl,
        fallbackCover: playlistCoverFallback(context, p),
        palette: p.palette,
        // 有创建者 id 时创建者单独一行，点了进 TA 的主页。
        link: p.creator != null && (p.creatorId ?? 0) > 0
            ? (text: p.creator!, onTap: () => openUser(context, p.creatorId!, name: p.creator))
            : null,
        lines: [
          [
            if ((p.creatorId ?? 0) <= 0) ?p.creator,
            '${p.trackCount} 首',
            '播放 ${formatPlayCount(p.playCount)}',
          ].join(' · '),
          ?p.description,
        ],
        onPlayAll: playAll,
        actions: [
          _SubscribeButton(playlist: p),
          IconButton(
            tooltip: '评论',
            onPressed: () => CommentsPage.open(
              context,
              target: CommentTarget.playlist,
              id: p.id,
              title: p.name,
              subtitle: p.creator,
              coverUrl: p.coverUrl ?? tracks.where((t) => t.coverUrl != null).firstOrNull?.coverUrl,
            ),
            icon: const Icon(Icons.mode_comment_outlined),
          ),
        ],
      ),
    );
  }
}

class _SubscribeButton extends StatefulWidget {
  const _SubscribeButton({required this.playlist});

  final Playlist playlist;

  @override
  State<_SubscribeButton> createState() => _SubscribeButtonState();
}

class _SubscribeButtonState extends State<_SubscribeButton> {
  bool _busy = false;

  Future<void> _toggle(AccountController account, bool subscribed) async {
    setState(() => _busy = true);
    try {
      await account.setSubscribed(widget.playlist, !subscribed);
      AppScope.toast(subscribed ? '已取消收藏' : '已收藏歌单');
    } catch (e) {
      AppScope.toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final p = widget.playlist;
    // 自己的歌单、「我喜欢」和未登录时不显示。
    if (!account.isLoggedIn || p.isLikedList || account.isOwn(p)) {
      return const SizedBox.shrink();
    }
    final subscribed = account.isSubscribed(p.id);
    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _toggle(account, subscribed),
      icon: Icon(subscribed ? Icons.check_rounded : Icons.add_rounded, size: 18),
      label: Text(subscribed ? '已收藏' : '收藏'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: context.colors.outline),
      ),
    );
  }
}
