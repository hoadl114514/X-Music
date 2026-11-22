import 'package:flutter/material.dart';

import '../app/app.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../pages/library/playlist_page.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';
import 'hover_builder.dart';
import 'motion.dart';
import 'round_icon_button.dart';
import 'image_viewer.dart';

final _firstCovers = <String, Future<String?>>{};

/// 歌单封面的备用图：歌单第一首歌的封面。每个歌单只查一次，失败了下次再查。
Future<String?> Function() playlistCoverFallback(BuildContext context, Playlist playlist) {
  final api = AppScope.of(context).api;
  final id = playlist.id;
  return () => _firstCovers.putIfAbsent(
    id,
    () => api.playlistFirstCover(id).catchError((Object _) {
      _firstCovers.remove(id);
      return null;
    }),
  );
}

/// 按宽度自适应列数的歌单网格（sliver）。封面正方形 + 两行标题。
class SliverPlaylistGrid extends StatelessWidget {
  const SliverPlaylistGrid({super.key, required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        // 按宽度算列数和格子高度：封面正方形 + 间距 + 两行标题，避免固定宽高比导致溢出。
        const spacing = 16.0;
        const titleHeight = 10 + 14 * 1.4 * 2 + 4;
        final columns = ((c.crossAxisExtent + spacing) / (140 + spacing)).floor().clamp(2, 6);
        final cell = (c.crossAxisExtent - spacing * (columns - 1)) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: cell + titleHeight,
          ),
          itemCount: playlists.length,
          itemBuilder: (context, i) => PlaylistCard(playlist: playlists[i]),
        );
      },
    );
  }
}

/// 歌单卡片：封面（右上角播放量）+ 标题，点击进歌单页。
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    void open() =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: playlist)));
    return PressScale(
      child: HoverBuilder(
        onTap: open,
        builder: (context, hovered) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSlide(
              offset: hovered ? const Offset(0, -0.02) : Offset.zero,
              duration: const Duration(milliseconds: 180),
              child: Stack(
                children: [
                  ViewableImage(
                    url: playlist.coverUrl,
                    title: playlist.name,
                    child: CoverArt(
                      palette: playlist.palette,
                      seed: playlist.id,
                      imageUrl: playlist.coverUrl,
                      fallbackImage: playlistCoverFallback(context, playlist),
                      radius: AppRadius.panel,
                      shadow: hovered ? AppShadows.heavy : null,
                    ),
                  ),
                  // 右上角播放量，下面垫一层渐变保证可读。
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 10, 16),
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0x00000000)],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                          Text(
                            formatPlayCount(playlist.playCount),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: AnimatedOpacity(
                      opacity: hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: RoundIconButton(
                        icon: Icons.play_arrow_rounded,
                        onPressed: hovered ? open : null,
                        size: 44,
                        iconSize: 26,
                        filled: true,
                        background: context.scheme.primaryContainer,
                        color: context.scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: hovered ? context.colors.textPrimary : context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌单列表的一行（搜索结果、用户主页等）。
class PlaylistTile extends StatelessWidget {
  const PlaylistTile({
    super.key,
    required this.playlist,
    this.trailing,
    this.subtitle,
    this.onReturned,
  });

  /// 从歌单页返回时调用（音乐库用来刷新歌曲数）。
  final VoidCallback? onReturned;

  final Playlist playlist;

  /// 右侧的按钮（如音乐库里的「管理」）。
  final Widget? trailing;

  /// 替代默认的「N 首 · 创建者」。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return ListTile(
      leading: SizedBox(
        width: 52,
        child: ViewableImage(
          url: p.coverUrl,
          title: p.name,
          child: CoverArt(
            palette: p.palette,
            seed: p.id,
            imageUrl: p.coverUrl,
            fallbackImage: playlistCoverFallback(context, p),
            radius: AppRadius.small,
          ),
        ),
      ),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle ?? ['${p.trackCount} 首', ?p.creator].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary),
      ),
      trailing: trailing,
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: p)))
              .then((_) => onReturned?.call()),
    );
  }
}
