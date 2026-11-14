import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../widgets/cover_art.dart';
import '../../shell/desktop_shell.dart';
import '../../shell/player_bar.dart';
import '../user/user_page.dart';
import 'album_page.dart';

/// 二级页面统一外壳：标题栏 + 内容 + 底部迷你播放条。
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.body, this.actions});

  final String title;
  final Widget body;
  final List<Widget>? actions;

  /// 电脑布局里从播放页这类盖住整个窗口的页面打开时，放进内容区的导航栈。
  static Future<void> push(BuildContext context, Widget page) {
    final shell = DesktopShell.contentNavigator;
    final nav = shell != null && !DesktopShellScope.isActive(context)
        ? shell
        : Navigator.of(context);
    return nav.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
      extendBody: true,
      bottomNavigationBar: const FloatingBottomBar(),
    );
  }
}

/// 歌手主页（和绑定的账号合在一起的用户主页）。
Future<void> openArtist(BuildContext context, ArtistRef artist) =>
    SubPage.push(context, UserPage(artist: artist, name: artist.name));

/// 用户主页，例如点评论区的头像 / 昵称、歌单创建者。
Future<void> openUser(BuildContext context, int userId, {String? name}) =>
    SubPage.push(context, UserPage(userId: userId, name: name));

Future<void> openAlbum(BuildContext context, String albumId, {String? name}) =>
    SubPage.push(context, AlbumPage(albumId: albumId, name: name));

/// 一首歌有多位歌手时先选一位。
Future<void> openSongArtist(BuildContext context, Song song) async {
  final picked = await pickSongArtist(context, song);
  if (picked != null && context.mounted) await openArtist(context, picked);
}

/// 选一位歌手：只有一位时直接返回，多位时弹底部面板让用户选，取消返回 null。
Future<ArtistRef?> pickSongArtist(BuildContext context, Song song) async {
  final artists = song.artists;
  if (artists.isEmpty) return null;
  if (artists.length == 1) return artists.first;
  return showModalBottomSheet<ArtistRef>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('选择要查看的歌手', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          for (final a in artists)
            ListTile(
              leading: SizedBox(
                width: 40,
                child: CoverArt(
                  palette: fallbackPalette(a.id),
                  seed: a.id,
                  radius: 20,
                  icon: Icons.person_rounded,
                  // 歌曲里只有歌手名和 id，头像另外取（有缓存）。
                  fallbackImage: () => AppScope.of(context).api.artistAvatar(a.id),
                ),
              ),
              title: Text(a.name),
              onTap: () => Navigator.of(context).pop(a),
            ),
        ],
      ),
    ),
  );
}
