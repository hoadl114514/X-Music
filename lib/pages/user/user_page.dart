import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/services.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/account_controller.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/song_tile.dart';
import 'user_status.dart';
import '../library/playlist_page.dart';
import '../library/track_list_view.dart';
import '../music/artist_page.dart';
import '../music/nav.dart';
import '../music/ranking_page.dart';
import '../social/event_card.dart';
import '../social/follow_list_page.dart';
import '../social/messages_page.dart';
import '../social/social_widgets.dart';
import '../../shell/player_bar.dart';

/// 用户主页。网易云的歌手和用户是两套 id：歌手入驻后绑定一个账号（`artist.accountId`），
/// 账号资料里也记着绑定的歌手（`profile.artistId`）。这里两边合在一起显示：
///
/// - 从歌手进入（[artist]）：先取歌手详情，有绑定账号再取账号资料和歌单；
/// - 从用户进入（[userId]，例如评论区头像）：先取账号资料，绑定了歌手再取歌手详情。
///
/// 「主页」标签放 TA 的热门作品、音乐品味、创建的歌单、收藏的歌单；
/// 有发行作品（是歌手）时再加「全部歌曲」「专辑」两个标签；有账号时加「动态」标签。
/// 头部可以关注 / 取消关注、发私信，点关注数、粉丝数进列表。
///
/// - TODO(用户主页): 搜索页的「用户」结果（点进来到这个页面）。
class UserPage extends StatefulWidget {
  const UserPage({super.key, this.userId, this.artist, this.name})
    : assert(userId != null || artist != null);

  final int? userId;
  final ArtistRef? artist;

  /// 加载完之前标题栏先显示的名字。
  final String? name;

  @override
  State<UserPage> createState() => _UserPageState();
}

/// 主页要用的全部数据。账号部分（[user] 和歌单）在歌手没有入驻时为空。
class UserPageData {
  const UserPageData({
    this.user,
    this.artist,
    this.hotSongs = const [],
    this.created = const [],
    this.subscribed = const [],
    this.liked,
    this.status,
  });

  final UserDetail? user;
  final Artist? artist;
  final List<Song> hotSongs;
  final List<Playlist> created;
  final List<Playlist> subscribed;

  /// 「TA 喜欢的音乐」歌单。
  final Playlist? liked;

  /// 账号当前的状态（需要登录才能取）；没设置或取不到为 null。
  final UserStatus? status;

  String get name => artist?.name ?? user?.nickname ?? '';
  String? get avatarUrl => artist?.avatarUrl ?? user?.avatarUrl;

  /// 有发行作品才显示「全部歌曲」「专辑」标签。
  bool get hasWorks => artist != null && (artist!.songCount > 0 || artist!.albumCount > 0);
}

/// 取用户主页数据，见 [UserPage] 的说明。账号部分取失败不影响歌手部分，反之亦然。
Future<UserPageData> loadUserPage(AppServices services, {int? userId, ArtistRef? artist}) async {
  final api = services.api;
  Artist? artistInfo;
  var hotSongs = const <Song>[];
  UserDetail? user;
  var uid = userId;

  Future<void> loadArtist(String id) async {
    final r = await api.artistDetail(id);
    artistInfo = r.artist;
    hotSongs = r.hotSongs;
  }

  if (artist != null) {
    await loadArtist(artist.id);
    uid ??= artistInfo!.accountId;
    if (uid != null) {
      try {
        user = await api.userDetail(uid);
      } catch (_) {
        // 账号资料取不到就只显示歌手部分。
      }
    }
  } else {
    final u = await api.userDetail(uid!);
    user = u;
    if (u.artistId case final aid?) {
      try {
        await loadArtist(aid);
      } catch (_) {
        // 歌手详情取不到就当普通用户显示。
      }
    }
  }

  var playlists = const <Playlist>[];
  UserStatus? status;
  if (uid != null) {
    final statusFuture = user != null && api.hasLoginCookie
        ? api.userStatus(uid).catchError((Object _) => null)
        : Future<UserStatus?>.value();
    playlists = await api.userPlaylists(uid).catchError((Object _) => const <Playlist>[]);
    status = await statusFuture;
  }
  final id = uid;
  return UserPageData(
    user: user,
    artist: artistInfo,
    hotSongs: hotSongs,
    status: status,
    liked: playlists.where((p) => p.isLikedList).firstOrNull,
    created: [
      for (final p in playlists)
        if (!p.isLikedList && p.creatorId == id) p,
    ],
    subscribed: [
      for (final p in playlists)
        if (!p.isLikedList && p.creatorId != id) p,
    ],
  );
}

class _UserPageState extends State<UserPage> {
  late Future<UserPageData> _data = _load();

  Future<UserPageData> _load() =>
      loadUserPage(AppScope.of(context), userId: widget.userId, artist: widget.artist);

  Future<void> _reload() async {
    setState(() => _data = _load());
    await _data.catchError((Object _) => const UserPageData());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserPageData>(
      future: _data,
      builder: (context, snap) {
        final d = snap.data;
        final title = (d?.name.isNotEmpty ?? false)
            ? d!.name
            : widget.name ?? widget.artist?.name ?? '用户';
        if (d == null) {
          return SubPage(
            title: title,
            body: snap.hasError
                ? ErrorState(error: snap.error!, onRetry: _reload)
                : const Center(child: CircularProgressIndicator()),
          );
        }
        final home = _HomeTab(data: d, onRefresh: _reload);
        final a = d.artist;
        final u = d.user;
        final self = u != null && u.userId == AccountScope.of(context).profile?.userId;
        final works = d.hasWorks && a != null;
        final ref = a == null ? null : ArtistRef(a.id, a.name);
        final tabs = <(String, Widget)>[
          ('主页', home),
          if (works) ('全部歌曲', ArtistAllSongs(artist: ref!)),
          if (works) ('专辑', ArtistAlbums(artist: ref!)),
          if (u != null)
            ('动态', UserEventList(userId: u.userId, empty: self ? '还没有发过动态' : 'TA 还没有发过动态')),
        ];
        if (tabs.length == 1) return SubPage(title: title, body: home);
        return DefaultTabController(
          length: tabs.length,
          child: SubPage(
            title: title,
            body: Column(
              children: [
                TabBar(tabs: [for (final t in tabs) Tab(text: t.$1)]),
                Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({required this.data, required this.onRefresh});

  final UserPageData data;
  final Future<void> Function() onRefresh;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  static const _preview = 3;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = widget.data;
    final account = AccountScope.of(context);
    final self = d.user != null && d.user!.userId == account.profile?.userId;
    final ta = self ? '我' : 'TA';
    final hot = d.hotSongs;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 16 + floatingBarsInset(context)),
        children: [
          _Header(data: d, self: self),
          if (d.artist?.description case final desc?)
            ArtistIntro(artistId: d.artist!.id, brief: desc),
          if (hot.isNotEmpty) ...[
            _SectionTitle(
              title: '$ta的热门作品',
              onMore: hot.length > _preview ? () => _openHotSongs(context, d) : null,
            ),
            for (var i = 0; i < hot.length && i < _preview; i++)
              SongTile(
                song: hot[i],
                index: i + 1,
                onTap: () =>
                    PlayerScope.read(context).playQueue(hot, start: i, title: '${d.name} 热门作品'),
              ),
          ],
          if (d.user case final u?) ...[
            const _SectionTitle(title: '音乐品味'),
            _TasteTile(
              icon: Icons.show_chart_rounded,
              title: '$ta的听歌排行',
              subtitle: !u.playRecordPublic && !self ? 'TA 没有公开听歌排行' : '累计听歌 ${u.listenSongs} 首',
              onTap: !u.playRecordPublic && !self
                  ? null
                  : () => SubPage.push(
                      context,
                      SubPage(
                        title: '${d.name} 的听歌排行',
                        body: RankingPage(userId: u.userId),
                      ),
                    ),
            ),
            if (d.liked case final liked?)
              _TasteTile(
                icon: Icons.favorite_rounded,
                title: '$ta喜欢的音乐',
                subtitle: '${liked.trackCount} 首',
                coverUrl: liked.coverUrl,
                onTap: () => SubPage.push(context, PlaylistPage(playlist: liked)),
              ),
            _PlaylistSection(
              title: '$ta创建的歌单',
              name: d.name,
              playlists: d.created,
              empty: '还没有创建歌单',
            ),
            _PlaylistSection(
              title: '$ta收藏的歌单',
              name: d.name,
              playlists: d.subscribed,
              empty: '还没有收藏歌单',
            ),
          ],
        ],
      ),
    );
  }

  void _openHotSongs(BuildContext context, UserPageData d) {
    SubPage.push(
      context,
      SubPage(
        title: '${d.name} 的热门作品',
        body: TrackListView(
          load: () async => d.hotSongs,
          queueTitle: '${d.name} 热门作品',
          header: (context, tracks, playAll) => CollectionHeader(
            title: '热门作品',
            seed: 'hot:${d.artist?.id}',
            coverUrl: d.avatarUrl,
            icon: Icons.person_rounded,
            circular: true,
            lines: [d.name, '前 ${tracks.length} 首'],
            onPlayAll: playAll,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.self});

  final UserPageData data;
  final bool self;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final u = d.user;
    final a = d.artist;
    final seed = a?.id ?? 'u${u?.userId}';
    final stats = <(String, VoidCallback?)>[
      if (u != null && u.level > 0) ('Lv.${u.level}', null),
      if (u != null)
        ('关注 ${formatPlayCount(u.follows)}', () => FollowListPage.open(context, u.userId, d.name)),
      if (u != null)
        (
          '粉丝 ${formatPlayCount(u.followeds)}',
          () => FollowListPage.open(context, u.userId, d.name, fans: true),
        ),
      if (a != null) ('单曲 ${a.songCount}', null),
      if (a != null) ('专辑 ${a.albumCount}', null),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: ViewableImage(
              url: d.avatarUrl,
              title: d.name,
              child: CoverArt(
                palette: fallbackPalette(seed),
                seed: seed,
                imageUrl: d.avatarUrl,
                icon: Icons.person_rounded,
                radius: 48,
                shadow: AppShadows.medium,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (u?.identity ?? (a != null ? '歌手' : null) case final id?) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.verified_rounded, size: 14, color: context.colors.accent),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    children: [
                      for (final (i, (label, onTap)) in stats.indexed)
                        GestureDetector(
                          onTap: onTap,
                          child: Text(
                            i == 0 ? label : ' · $label',
                            style: TextStyle(
                              fontSize: 12,
                              color: onTap == null
                                  ? context.colors.textSecondary
                                  : context.colors.textPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (u?.signature case final sig?) ...[
                  const SizedBox(height: 4),
                  Text(
                    sig,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.colors.textMuted),
                  ),
                ],
                if (u != null && (self || d.status != null)) ...[
                  const SizedBox(height: 8),
                  UserStatusChip(status: d.status, editable: self),
                ],
                if (!self && (u != null || a != null)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      // 有歌手就关注歌手：认证歌手账号的用户关注会被风控拦下。
                      FollowButton(
                        userId: u?.userId,
                        artistId: a?.id,
                        followed: a?.followed ?? u!.followed,
                        compact: true,
                      ),
                      if (u != null)
                        OutlinedButton(
                          onPressed: () => ChatPage.open(
                            context,
                            SocialUser(
                              userId: u.userId,
                              nickname: u.nickname,
                              avatarUrl: u.avatarUrl,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: context.colors.outline),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('私信'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.onMore});

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              style: TextButton.styleFrom(foregroundColor: context.colors.textSecondary),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('查看全部'), Icon(Icons.chevron_right_rounded, size: 18)],
              ),
            ),
        ],
      ),
    );
  }
}

class _TasteTile extends StatelessWidget {
  const _TasteTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.coverUrl,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      leading: SizedBox(
        width: 52,
        child: CoverArt(
          palette: fallbackPalette(title),
          seed: title,
          imageUrl: coverUrl,
          icon: icon,
          radius: 6,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: context.colors.textSecondary)),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _PlaylistSection extends StatelessWidget {
  const _PlaylistSection({
    required this.title,
    required this.name,
    required this.playlists,
    required this.empty,
  });

  static const _preview = 3;

  final String title;
  final String name;
  final List<Playlist> playlists;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final list = playlists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: list.isEmpty ? title : '$title（${list.length}）',
          onMore: list.length > _preview
              ? () => SubPage.push(
                  context,
                  SubPage(
                    title: '$name · ${title.replaceFirst(RegExp('^(TA|我)'), '')}',
                    body: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) => PlaylistTile(playlist: list[i]),
                    ),
                  ),
                )
              : null,
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(empty, style: TextStyle(color: context.colors.textMuted)),
          ),
        for (final p in list.take(_preview)) PlaylistTile(playlist: p),
      ],
    );
  }
}
