import 'package:flutter/material.dart';

import '../app/app.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../shell/destinations.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/playlist_card.dart';
import 'library/library_page.dart';
import 'library/song_actions.dart';
import 'library/playlist_page.dart';
import 'login_page.dart';
import 'music/daily_songs_page.dart';
import 'now_playing/now_playing_page.dart';
import '../shell/player_bar.dart';

const _dailyPalette = [Color(0xFF3B2A4D), Color(0xFFB0605A), Color(0xFFE8B66B)];
const _likedPalette = [Color(0xFFE85A9A), Color(0xFF6A4BC4), Color(0xFF1F1A3A)];
const _fmPalette = [Color(0xFF1B1036), Color(0xFFE0367F), Color(0xFF29D3F0)];

/// 首页：每日推荐、我喜欢、私人 FM、根据你喜爱的歌曲推荐、推荐歌单。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  final ValueChanged<Destination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = width < 600 ? 16.0 : 24.0;
    final account = AccountScope.of(context);

    return Scrollbar(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
            sliver: SliverList.list(
              children: [
                const _Greeting(),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, c) {
                    final shortcuts = Column(
                      children: [
                        _DailyCard(key: ValueKey(account.profile?.userId)),
                        const SizedBox(height: 16),
                        _ShortcutCard(
                          title: '我喜欢的音乐',
                          subtitle: account.isLoggedIn
                              ? '${account.likedPlaylist?.trackCount ?? 0} 首'
                              : '登录后查看',
                          icon: Icons.favorite_rounded,
                          palette: _likedPalette,
                          seed: 'liked',
                          // 「我喜欢」歌单的封面就是最近喜欢的第一首歌的封面。
                          imageUrl: account.likedPlaylist?.coverUrl,
                          fallbackImage: switch (account.likedPlaylist) {
                            final p? => playlistCoverFallback(context, p),
                            null => null,
                          },
                          onTap: () => switch (account.likedPlaylist) {
                            final p? => LibraryPage.openLiked(context, p),
                            null =>
                              account.isLoggedIn
                                  ? onNavigate(Destination.library)
                                  : LoginPage.open(context),
                          },
                        ),
                      ],
                    );
                    if (c.maxWidth < 760) {
                      return Column(
                        children: [shortcuts, const SizedBox(height: 16), const _PersonalFmCard()],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: shortcuts),
                          const SizedBox(width: 20),
                          const Expanded(child: _PersonalFmCard()),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                // 登录状态变了（换号、退出）就重新拉推荐。
                _SongRcmdSection(key: ValueKey(account.profile?.userId)),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 32, hPad, 16),
            sliver: const SliverToBoxAdapter(child: _SectionTitle('推荐歌单')),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 32 + floatingBarsInset(context)),
            // 登录状态变了（换号、退出）就重新拉推荐。
            sliver: _RecommendedPlaylists(key: ValueKey(account.profile?.userId)),
          ),
        ],
      ),
    );
  }
}

class _RecommendedPlaylists extends StatefulWidget {
  const _RecommendedPlaylists({super.key});

  @override
  State<_RecommendedPlaylists> createState() => _RecommendedPlaylistsState();
}

class _RecommendedPlaylistsState extends State<_RecommendedPlaylists> {
  late Future<List<Playlist>> _future = _load();

  Future<List<Playlist>> _load() => AppScope.of(context).api.recommendPlaylists(limit: 12);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Playlist>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return SliverToBoxAdapter(
            child: TextButton(
              onPressed: () => setState(() {
                _future = _load();
              }),
              child: const Text('推荐加载失败，点击重试'),
            ),
          );
        }
        final list = snap.data;
        if (list == null) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return SliverPlaylistGrid(playlists: list);
      },
    );
  }
}

/// 清空首页记住的推荐（测试用）。
@visibleForTesting
void resetHomeCaches() {
  _SongRcmdSectionState._cache = null;
  _SongRcmdSectionState._lastPage = 0;
}

/// 根据你喜爱的歌曲推荐：横向翻页，每列 3 首。手机上露出下一列的一角，宽屏一次显示几列并带翻页按钮。
class _SongRcmdSection extends StatefulWidget {
  const _SongRcmdSection({super.key});

  @override
  State<_SongRcmdSection> createState() => _SongRcmdSectionState();
}

class _SongRcmdSectionState extends State<_SongRcmdSection> {
  static const _perColumn = 3;
  static const _rowHeight = 76.0;

  /// 上一次的推荐和翻到的列，按账号记住。离开首页再回来不重新拉（接口每次都会换一批），
  /// 只有点「换一批」、换账号或上次加载失败时才重新拉。
  static ({int? userId, Future<HomeFeed> future})? _cache;
  static var _lastPage = 0;

  late Future<HomeFeed> _future = _cached();
  PageController? _pages;

  int? get _userId => AccountScope.read(context).profile?.userId;

  Future<HomeFeed> _cached() {
    final c = _cache;
    if (c != null && c.userId == _userId) return c.future;
    _lastPage = 0;
    return _load();
  }

  Future<HomeFeed> _load() {
    final future = AppScope.of(context).api.homeFeed();
    final entry = (userId: _userId, future: future);
    _cache = entry;
    // 失败的结果不留，下次进首页重新拉。
    future.catchError((Object _) {
      if (identical(_cache, entry)) _cache = null;
      return const HomeFeed(songTitle: '', songs: []);
    });
    return future;
  }

  /// 换一批：重新拉并回到第一列。
  void _refresh() {
    _lastPage = 0;
    if (_pages?.hasClients ?? false) _pages!.jumpToPage(0);
    setState(() {
      _future = _load();
    });
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  /// 视口占比变了（窗口缩放）就换一个 PageController，尽量停在原来那一列。
  PageController _controllerFor(double fraction) {
    final old = _pages;
    if (old != null && old.viewportFraction == fraction) return old;
    final page = old != null && old.hasClients ? (old.page ?? 0).round() : _lastPage;
    final next = PageController(viewportFraction: fraction, initialPage: page);
    // 旧的还挂在这一帧的 PageView 上，下一帧再释放。
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    return _pages = next;
  }

  void _turn(int delta, int visible, int columns) {
    final pages = _pages;
    if (pages == null || !pages.hasClients) return;
    final current = (pages.page ?? 0).round();
    final target = (current + delta * visible).clamp(0, (columns - visible).clamp(0, columns));
    pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _body(AsyncSnapshot<HomeFeed> snap, List<SongRcmd>? items, int columns, double fraction) {
    if (snap.hasError) {
      return Center(
        child: TextButton(onPressed: _refresh, child: const Text('推荐加载失败，点击重试')),
      );
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Text('暂无推荐', style: TextStyle(color: context.colors.textSecondary)),
      );
    }
    final songs = [for (final i in items) i.song];
    return PageView.builder(
      controller: _controllerFor(fraction),
      padEnds: false,
      onPageChanged: (p) => _lastPage = p,
      itemCount: columns,
      itemBuilder: (context, col) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            for (var i = col * _perColumn; i < items.length && i < (col + 1) * _perColumn; i++)
              _SongRcmdRow(item: items[i], songs: songs, index: i, height: _rowHeight),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 600;
        // 手机：一列占 88%，露出下一列；宽屏：每列约 360 宽，至少 2 列。
        final visible = narrow ? 1 : (c.maxWidth / 360).floor().clamp(2, 5);
        final fraction = narrow ? 0.88 : 1 / visible;
        return FutureBuilder<HomeFeed>(
          future: _future,
          builder: (context, snap) {
            final items = snap.data?.songs;
            final radar = snap.data?.radar ?? const <Playlist>[];
            final columns = items == null ? 0 : (items.length / _perColumn).ceil();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(
                  snap.data?.songTitle ?? '根据你喜爱的歌曲推荐',
                  // 官方标题可能很长（如「听过的某某的人也在听」），允许折成两行。
                  maxLines: 2,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '换一批',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      if (!narrow && columns > visible) ...[
                        IconButton(
                          tooltip: '上一页',
                          onPressed: () => _turn(-1, visible, columns),
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        IconButton(
                          tooltip: '下一页',
                          onPressed: () => _turn(1, visible, columns),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: _rowHeight * _perColumn,
                  child: _body(snap, items, columns, fraction),
                ),
                if (radar.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _SectionTitle(snap.data!.radarTitle, maxLines: 2),
                  const SizedBox(height: 12),
                  _RadarPlaylists(playlists: radar, narrow: narrow),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// 雷达歌单：横向滚动的大封面卡片，左上角播放量，右下角播放键，下面两行标题。
class _RadarPlaylists extends StatelessWidget {
  const _RadarPlaylists({required this.playlists, required this.narrow});

  final List<Playlist> playlists;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final width = narrow ? 150.0 : 180.0;
    const titleHeight = 8 + 15 * 1.4 * 2 + 6;
    return SizedBox(
      height: width + titleHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: width,
          child: _RadarCard(playlist: playlists[i]),
        ),
      ),
    );
  }
}

class _RadarCard extends StatelessWidget {
  const _RadarCard({required this.playlist});

  final Playlist playlist;

  Future<void> _play(BuildContext context) async {
    final api = AppScope.of(context).api;
    final player = PlayerScope.read(context);
    try {
      final detail = await api.playlistDetail(playlist.id);
      if (detail.tracks.isEmpty) return AppScope.toast('歌单是空的');
      await player.playQueue(detail.tracks, title: playlist.name, sourceId: playlist.id);
    } catch (e) {
      AppScope.toast('歌单加载失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: p))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CoverArt(
                palette: p.palette,
                seed: p.id,
                imageUrl: p.coverUrl,
                radius: AppRadius.card,
              ),
              // 上下各垫一层渐变，保证白字可读。
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x55000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x44000000),
                      ],
                      stops: [0, 0.3, 0.7, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 6,
                child: Row(
                  children: [
                    const Icon(Icons.headphones_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      formatPlayCount(p.playCount),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: IconButton(
                  tooltip: '播放',
                  onPressed: () => _play(context),
                  icon: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, height: 1.4, color: context.colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// 推荐的一行：封面、歌名、（喜欢 / 推荐理由或音质）+ 歌手、播放按钮。
/// 点了从这首开始放整组推荐，长按打开歌曲菜单。
class _SongRcmdRow extends StatelessWidget {
  const _SongRcmdRow({
    required this.item,
    required this.songs,
    required this.index,
    required this.height,
  });

  final SongRcmd item;
  final List<Song> songs;
  final int index;
  final double height;

  @override
  Widget build(BuildContext context) {
    final song = item.song;
    final playing = PlayerScope.of(context).current?.id == song.id;
    final liked = AccountScope.of(context).isLiked(song.id);
    void play() => PlayerScope.read(context).playQueue(songs, start: index, title: '为你推荐');
    // 推荐理由优先，没有时显示音质角标，和官方一样两者只显示一个。
    final badge = item.tag ?? item.quality;
    return SizedBox(
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: play,
        onLongPress: () => showSongActions(context, song),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: CoverArt(
                palette: song.palette,
                seed: song.id,
                imageUrl: song.coverUrl,
                radius: AppRadius.card,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: playing ? context.colors.accent : context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (liked) ...[
                        Icon(Icons.favorite_rounded, size: 14, color: context.colors.negative),
                        const SizedBox(width: 4),
                      ],
                      if (badge != null) ...[
                        Flexible(flex: 0, child: _RcmdBadge(badge, filled: item.tag != null)),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '播放',
              visualDensity: VisualDensity.compact,
              onPressed: play,
              icon: Icon(Icons.play_arrow_rounded, color: context.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 小标签：推荐理由（tertiary 容器色）或音质（primary 描边）。
class _RcmdBadge extends StatelessWidget {
  const _RcmdBadge(this.text, {required this.filled});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: filled ? context.scheme.tertiaryContainer : null,
          border: Border.all(
            color: filled ? Colors.transparent : context.scheme.primary.withValues(alpha: 0.7),
          ),
          borderRadius: BorderRadius.circular(AppRadius.tag),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: filled ? context.scheme.onTertiaryContainer : context.scheme.primary,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (AccountScope.of(context).profile) {
          final p? => '${greetingFor(DateTime.now())}，${p.nickname}',
          null => greetingFor(DateTime.now()),
        }, style: text.headlineMedium?.copyWith(color: context.scheme.onSurface)),
        const SizedBox(height: 4),
        Text('由此开启好心情 ~', style: text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// 分区标题：M3 titleLarge，右侧可放按钮。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing, this.maxLines = 1});

  final String title;
  final int maxLines;

  /// 标题右侧的按钮（如「新建」）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: context.scheme.onSurface),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// M3 填充卡片：默认 surfaceContainerHighest 底，可换成别的容器色（如私人 FM 用 primaryContainer）。
class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color ?? context.scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.panel)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.palette,
    required this.seed,
    required this.onTap,
    this.imageUrl,
    this.fallbackImage,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> palette;
  final String seed;
  final VoidCallback onTap;

  /// 卡片封面；为 null 时用 [palette] 生成的占位图。
  final String? imageUrl;
  final Future<String?> Function()? fallbackImage;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    return _Panel(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: CoverArt(
              palette: palette,
              seed: seed,
              imageUrl: imageUrl,
              fallbackImage: fallbackImage,
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
                    Icon(icon, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(title, style: text.titleMedium?.copyWith(color: scheme.onSurface)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// 每日推荐卡片：登录后用今天推荐的第一首歌的封面。
class _DailyCard extends StatefulWidget {
  const _DailyCard({super.key});

  @override
  State<_DailyCard> createState() => _DailyCardState();
}

class _DailyCardState extends State<_DailyCard> {
  Song? _first;

  @override
  void initState() {
    super.initState();
    if (AccountScope.read(context).isLoggedIn) _load();
  }

  Future<void> _load() async {
    try {
      final songs = await AppScope.of(context).api.dailySongs();
      if (mounted && songs.isNotEmpty) setState(() => _first = songs.first);
    } catch (_) {
      // 取不到就保留占位封面。
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AccountScope.of(context).isLoggedIn;
    final first = _first;
    return _ShortcutCard(
      title: '每日推荐',
      subtitle: !loggedIn
          ? '登录后查看'
          : first == null
          ? '根据你的音乐口味 · 每日更新'
          : '${first.title} - ${first.artist}',
      icon: Icons.calendar_today_rounded,
      palette: _dailyPalette,
      seed: 'daily',
      imageUrl: first?.coverUrl,
      onTap: () => loggedIn ? DailySongsPage.open(context) : LoginPage.open(context),
    );
  }
}

class _PersonalFmCard extends StatelessWidget {
  const _PersonalFmCard();

  Future<void> _start(BuildContext context) async {
    if (!AccountScope.read(context).isLoggedIn) return LoginPage.open(context);
    final api = AppScope.of(context).api;
    try {
      await PlayerScope.read(context).playRadio(api.personalFm, title: '私人 FM');
    } catch (e) {
      AppScope.toast('私人 FM 加载失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final scheme = context.scheme;
    final text = Theme.of(context).textTheme;
    // 正在放私人 FM：封面换成当前这首，点击打开播放页而不是重新开始。
    final playing = player.isRadio ? player.current : null;
    final open = playing != null ? () => openNowPlaying(context) : () => _start(context);
    return _Panel(
      color: scheme.primaryContainer,
      padding: const EdgeInsets.all(16),
      onTap: open,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: CoverArt(
              palette: playing?.palette ?? _fmPalette,
              seed: playing?.id ?? 'fm',
              imageUrl: playing?.coverUrl,
              radius: AppRadius.card,
              icon: playing == null ? Icons.radio_rounded : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('私人 FM', style: text.titleLarge?.copyWith(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(
                  playing == null ? '根据你的口味连续播放' : '正在播放：${playing.title} - ${playing.artist}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: playing != null ? '打开播放页' : '开始播放',
            onPressed: open,
            icon: Icon(playing != null ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }
}
