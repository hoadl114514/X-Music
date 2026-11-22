import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/share.dart';
import '../comments/comments_page.dart';
import '../login_page.dart';
import '../music/nav.dart';
import '../now_playing/song_menu.dart';
import '../social/compose_event_page.dart';

/// 歌曲列表每行右侧「⋮」的菜单：下一首播放、喜欢、收藏到歌单、评论、分享、歌手、专辑。
/// [onRemove] 不为 null 时多一项「从歌单中删除」。
Future<void> showSongActions(BuildContext context, Song song, {VoidCallback? onRemove}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surfaceHigh,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SongActions(song: song, onRemove: onRemove),
    );

class _SongActions extends StatelessWidget {
  const _SongActions({required this.song, this.onRemove});

  final Song song;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final liked = account.isLiked(song.id);

    // 先关菜单，再在原页面上执行。
    void then(void Function(BuildContext context) action) {
      final nav = Navigator.of(context);
      nav.pop();
      action(nav.context);
    }

    Widget item(
      IconData icon,
      String title,
      VoidCallback? onTap, {
      Color? color,
      Widget? leading,
    }) => ListTile(
      leading: leading ?? Icon(icon, color: color ?? context.colors.textPrimary),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color),
      ),
      onTap: onTap,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: SizedBox(
                  width: 48,
                  child: CoverArt(
                    palette: song.palette,
                    seed: song.id,
                    imageUrl: song.coverUrl,
                    radius: 4,
                  ),
                ),
                title: Text(
                  '歌曲：${song.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Divider(),
              item(Icons.playlist_play_rounded, '下一首播放', () {
                then((_) {
                  PlayerScope.read(context).playNext(song);
                  AppScope.toast('已添加到下一首播放');
                });
              }),
              item(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                liked ? '取消喜欢' : '喜欢',
                () => then((c) async {
                  if (!account.isLoggedIn) {
                    await LoginPage.open(c);
                    return;
                  }
                  try {
                    await account.toggleLike(song.id);
                    AppScope.toast(liked ? '已取消喜欢' : '已添加到我喜欢的音乐');
                  } catch (e) {
                    AppScope.toast('操作失败：$e');
                  }
                }),
                color: liked ? context.colors.negative : null,
              ),
              item(
                Icons.playlist_add_rounded,
                '收藏到歌单',
                () => then((c) => showAddToPlaylistSheet(c, song)),
              ),
              if (onRemove case final remove?)
                item(
                  Icons.playlist_remove_rounded,
                  '从歌单中删除',
                  () => then((_) => remove()),
                  color: context.colors.negative,
                ),
              item(
                Icons.mode_comment_outlined,
                '评论',
                () => then((c) => CommentsPage.openSong(c, song)),
              ),
              item(Icons.share_outlined, '分享链接', () => then((_) => shareSong(song))),
              item(
                Icons.campaign_outlined,
                '分享到动态',
                () => then((c) => ComposeEventPage.open(c, song: song)),
              ),
              if (song.artists.isNotEmpty)
                item(
                  song.artists.length > 1
                      ? Icons.people_outline_rounded
                      : Icons.person_outline_rounded,
                  '歌手：${song.artist}',
                  () => then((c) => openSongArtist(c, song)),
                ),
              if (song.albumId != null)
                item(
                  Icons.album_outlined,
                  '专辑：${song.album}',
                  () => then((c) => openAlbum(c, song.albumId!, name: song.album)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
