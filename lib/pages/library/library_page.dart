import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../shell/page_visit.dart';
import '../../shell/player_bar.dart';
import '../../state/account_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/entry_card.dart';
import '../../widgets/playlist_card.dart';
import '../login_page.dart';
import '../music/nav.dart';
import '../music/ranking_page.dart';
import '../music/recent_page.dart';
import 'followed_artists_page.dart';
import 'playlist_editor.dart';
import 'playlist_page.dart';

/// 底部「音乐库」标签：我喜欢的音乐、最近播放、听歌排行和艺人入口、创建的歌单、收藏的歌单，以及歌单管理。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  /// 打开「我喜欢的音乐」歌单页，返回时完成。
  static Future<void> openLiked(BuildContext context, Playlist liked) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: liked)));

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int? _visit;
  bool _seen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 进入和切回音乐库时都在后台刷新歌单列表（歌曲数、在别处新建 / 收藏的歌单），
    // 列表先显示已有的，不清空。
    final visit = PageVisit.of(context);
    if (!_seen || visit != _visit) {
      _seen = true;
      _visit = visit;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  Future<void> _reload() async {
    final account = AccountScope.read(context);
    if (!account.isLoggedIn) return;
    try {
      await account.reloadPlaylists();
    } catch (_) {
      // 刷新失败保留原列表。
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    if (!account.isLoggedIn) return const LoginPrompt(message: '登录后查看你的音乐库');
    final liked = account.likedPlaylist;
    // 共建歌单（自己建的和加入的）单独一栏，不再出现在「创建的」「收藏的」里。
    final shared = account.sharedPlaylists;
    final created = [
      for (final p in account.ownPlaylists)
        if (!account.isShared(p)) p,
    ];
    final collected = [
      for (final p in account.playlists)
        if (!p.isLikedList && !account.isOwn(p) && !account.isShared(p)) p,
    ];
    final hPad = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, 12, 0, 32 + floatingBarsInset(context)),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: _LikedCard(playlist: liked, onReturned: _reload),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: Row(
              children: [
                for (final (i, e) in [
                  (Icons.history_rounded, '最近播放', const RecentPage()),
                  (Icons.show_chart_rounded, '听歌排行', const RankingPage()),
                  (Icons.mic_external_on_rounded, '艺人', const FollowedArtistsPage()),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: EntryCard(
                      icon: e.$1,
                      label: e.$2,
                      onTap: () => SubPage.push(context, SubPage(title: e.$2, body: e.$3)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            title: '创建的歌单',
            count: created.length,
            padding: hPad,
            // 「新建」弹出菜单：普通歌单或共建歌单。
            action: MenuAnchor(
              alignmentOffset: const Offset(-48, 0),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.queue_music_rounded),
                  onPressed: () => showCreatePlaylistDialog(context),
                  child: const Text('歌单'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.group_add_rounded),
                  onPressed: () => showCreatePlaylistDialog(context, shared: true),
                  child: const Text('共建歌单'),
                ),
              ],
              builder: (context, menu, _) => TextButton.icon(
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('新建'),
              ),
            ),
          ),
          if (created.isEmpty)
            const _Empty('还没有创建歌单')
          else
            for (final p in created)
              PlaylistTile(
                playlist: p,
                // 从歌单页回来也刷新（里面可能删了歌、改了信息）。
                onReturned: _reload,
                subtitle: '${p.trackCount} 首',
                trailing: IconButton(
                  tooltip: '管理歌单',
                  icon: Icon(Icons.more_vert_rounded, color: context.colors.textSecondary),
                  onPressed: () => showPlaylistManageSheet(context, p),
                ),
              ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '共享歌单',
            count: shared.length,
            padding: hPad,
            action: TextButton.icon(
              onPressed: () => showCreatePlaylistDialog(context, shared: true),
              icon: const Icon(Icons.group_add_rounded, size: 20),
              label: const Text('新建'),
            ),
          ),
          if (shared.isEmpty)
            const _Empty('还没有共享歌单')
          else
            for (final p in shared)
              PlaylistTile(
                playlist: p,
                onReturned: _reload,
                // 别人的共建歌单用默认的「N 首 · 创建者」。
                subtitle: account.isOwn(p) ? '${p.trackCount} 首' : null,
                // 自己建的可以管理；加入的别人的没有管理菜单。
                trailing: account.isOwn(p)
                    ? IconButton(
                        tooltip: '管理歌单',
                        icon: Icon(Icons.more_vert_rounded, color: context.colors.textSecondary),
                        onPressed: () => showPlaylistManageSheet(context, p),
                      )
                    : null,
              ),
          const SizedBox(height: 16),
          _SectionHeader(title: '收藏的歌单', count: collected.length, padding: hPad),
          if (collected.isEmpty)
            const _Empty('还没有收藏歌单')
          else
            for (final p in collected)
              PlaylistTile(
                playlist: p,
                // 从歌单页回来也刷新（里面可能删了歌、改了信息）。
                onReturned: _reload,
                trailing: IconButton(
                  tooltip: '管理歌单',
                  icon: Icon(Icons.more_vert_rounded, color: context.colors.textSecondary),
                  onPressed: () => _showCollectedSheet(context, p),
                ),
              ),
        ],
      ),
    );
  }
}

/// 收藏的歌单的「更多」菜单：分享到动态、取消收藏。
Future<void> _showCollectedSheet(BuildContext context, Playlist playlist) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surfaceHigh,
    showDragHandle: true,
    builder: (sheet) {
      void then(Future<void> Function(BuildContext context) action) {
        final nav = Navigator.of(sheet);
        nav.pop();
        action(nav.context);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.bookmark_remove_outlined, color: context.colors.negative),
              title: Text('取消收藏', style: TextStyle(color: context.colors.negative)),
              onTap: () => then((c) => _unsubscribe(c, playlist)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _unsubscribe(BuildContext context, Playlist playlist) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: context.colors.surfaceHigh,
      title: const Text('取消收藏'),
      content: Text('确定不再收藏「${playlist.name}」？'),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.colors.negative),
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('取消收藏'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await AccountScope.read(context).setSubscribed(playlist, false);
    AppScope.toast('已取消收藏「${playlist.name}」');
  } catch (e) {
    AppScope.toast('取消收藏失败：$e');
  }
}

/// 「我喜欢的音乐」大卡片，点了进歌单。
class _LikedCard extends StatelessWidget {
  const _LikedCard({required this.playlist, required this.onReturned});

  final Playlist? playlist;
  final VoidCallback onReturned;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: p == null ? null : () => LibraryPage.openLiked(context, p).then((_) => onReturned()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: CoverArt(
                  palette: const [Color(0xFFE85A9A), Color(0xFF6A4BC4), Color(0xFF1F1A3A)],
                  seed: 'liked',
                  imageUrl: p?.coverUrl,
                  fallbackImage: p == null ? null : playlistCoverFallback(context, p),
                  icon: p?.coverUrl == null ? Icons.favorite_rounded : null,
                  radius: AppRadius.card,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.favorite_rounded, size: 20, color: context.colors.accent),
                        const SizedBox(width: 8),
                        Text('我喜欢的音乐', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      p == null ? '加载中…' : '${p.trackCount} 首',
                      style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.padding,
    this.action,
  });

  final String title;
  final int count;
  final double padding;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 0, padding - 8, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(color: context.colors.textMuted)),
            const Spacer(),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(text, style: TextStyle(color: context.colors.textSecondary)),
      ),
    );
  }
}
