import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../music/nav.dart';
import '../social/social_widgets.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/share.dart';
import 'track_list_view.dart';

/// 歌单内容：头部信息 + 播放全部 + 歌曲列表。歌单页和「我喜欢」共用。
/// 别人的歌单在头部多一个「收藏」按钮。
class PlaylistView extends StatefulWidget {
  const PlaylistView({super.key, required this.playlist});

  final Playlist playlist;

  @override
  State<PlaylistView> createState() => _PlaylistViewState();
}

class _PlaylistViewState extends State<PlaylistView> {
  /// 共建歌单的成员和每首歌的添加人；普通歌单或还没取到时为 null。
  SharedPlaylistInfo? _shared;
  bool _sharedRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sharedRequested && AccountScope.read(context).isShared(widget.playlist)) {
      _sharedRequested = true;
      _loadShared();
    }
  }

  Future<void> _loadShared() async {
    try {
      final info = await AppScope.of(context).api.sharedPlaylistInfo(widget.playlist.id);
      if (mounted) setState(() => _shared = info);
    } catch (_) {
      // 取不到就不显示添加人，成员头像用列表里的。
    }
  }

  /// 歌曲下面的「某某 添加」。
  Widget? _adderLine(Song song) {
    final u = _shared?.adders[song.id];
    if (u == null) return null;
    return Row(
      children: [
        _MemberAvatar(name: u.nickname, url: u.avatarUrl, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${u.nickname} 添加',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.colors.textMuted),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.playlist;
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
      footerFor: _shared == null ? null : _adderLine,
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
        extra: account.isShared(p) ? _InviteRow(playlist: p, info: _shared) : null,
        onPlayAll: playAll,
        actions: [_SubscribeButton(playlist: p)],
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
    // 自己的歌单、「我喜欢」、共建歌单和未登录时不显示。
    if (!account.isLoggedIn || p.isLikedList || account.isOwn(p) || account.isShared(p)) {
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

/// 共建歌单标题下的成员条：成员头像叠在一起，后面一个「管理」，点了打开成员管理面板。
class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.playlist, this.info});

  final Playlist playlist;

  /// 歌单详情里的成员（带昵称和头像）。歌单列表里的成员只有 userId，取到详情前先用列表的。
  final SharedPlaylistInfo? info;

  static const _size = 28.0;
  static const _step = 18.0;

  void _invite() {
    final p = playlist;
    shareText(
      '我建了一个共建歌单「${p.name}」，来和我一起加歌吧：https://music.163.com/playlist?id=${p.id}',
      subject: '共建歌单',
      title: '邀请好友一起编辑歌单',
      copied: '已复制邀请链接',
    );
  }

  /// 成员管理面板：全部成员（创建者在最前），点成员进主页；底部邀请好友。
  Future<void> _showMembers(BuildContext context) {
    final account = AccountScope.read(context);
    final me = account.profile;
    final members = info?.members ?? const <SocialUser>[];
    final creatorId = info?.creator?.userId ?? playlist.creatorId;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  members.isEmpty ? '共享歌单成员' : '共享歌单成员 · ${members.length} 人',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: members.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('成员加载中，稍后再试')),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final u in members)
                            ListTile(
                              leading: SocialAvatar(userId: u.userId, url: u.avatarUrl, size: 40),
                              title: Text(
                                u.userId == me?.userId ? '${u.nickname}（我）' : u.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(u.userId == creatorId ? '创建者' : '成员'),
                              onTap: () {
                                Navigator.of(context).pop();
                                openUser(context, u.userId, name: u.nickname);
                              },
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _invite();
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('邀请好友'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final account = AccountScope.of(context);
    final me = account.profile;
    // 创建者在最前：自己的歌单用自己的头像，其他成员跟在后面。
    final members = [
      if (info case final i? when i.members.isNotEmpty)
        for (final u in i.members) (name: u.nickname, url: u.avatarUrl)
      else ...[
        if (me != null && account.isOwn(playlist))
          (name: me.nickname, url: me.avatarUrl)
        else if (playlist.creator case final c?)
          (name: c, url: null),
        for (final u in playlist.sharedUsers)
          if (u.userId != me?.userId) (name: u.nickname, url: u.avatarUrl),
      ],
    ].take(4).toList();
    Widget circle(Widget child, {Color? color}) => Container(
      width: _size,
      height: _size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
      child: CircleAvatar(backgroundColor: color ?? scheme.secondaryContainer, child: child),
    );
    final count = members.length + 1;
    return InkWell(
      onTap: () => _showMembers(context),
      borderRadius: BorderRadius.circular(_size),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _size + _step * (count - 1),
              height: _size,
              child: Stack(
                children: [
                  for (final (i, m) in members.indexed)
                    Positioned(
                      left: _step * i,
                      child: Container(
                        width: _size,
                        height: _size,
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                        child: _MemberAvatar(name: m.name, url: m.url, size: _size - 3),
                      ),
                    ),
                  Positioned(
                    left: _step * members.length,
                    child: circle(
                      Icon(Icons.manage_accounts_rounded, size: 16, color: scheme.onSurfaceVariant),
                      color: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '管理',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// 小圆头像：有图显示图，没有显示昵称首字。
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, required this.url, required this.size});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final u = url;
    if (u == null) {
      return SizedBox.square(
        dimension: size,
        child: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Text(
            name.isEmpty ? '?' : name.characters.first,
            style: TextStyle(fontSize: size * 0.45, color: scheme.onSecondaryContainer),
          ),
        ),
      );
    }
    // 和其他用户头像一样用 CoverArt：带重试，失败时显示占位图。
    return SizedBox.square(
      dimension: size,
      child: CoverArt(
        palette: fallbackPalette(name),
        seed: name,
        imageUrl: u,
        icon: Icons.person_rounded,
        radius: size / 2,
      ),
    );
  }
}
