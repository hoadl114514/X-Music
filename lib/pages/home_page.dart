import 'package:flutter/material.dart';

import '../app/app.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../shell/destinations.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/hover_builder.dart';
import '../widgets/playlist_card.dart';
import 'library/playlist_editor.dart';
import 'library/song_actions.dart';
import 'login_page.dart';
import 'music/daily_songs_page.dart';
import 'now_playing/now_playing_page.dart';
import '../shell/player_bar.dart';

const _dailyPalette = [Color(0xFF3B2A4D), Color(0xFFB0605A), Color(0xFFE8B66B)];
const _likedPalette = [Color(0xFFE85A9A), Color(0xFF6A4BC4), Color(0xFF1F1A3A)];
const _fmPalette = [Color(0xFF1B1036), Color(0xFFE0367F), Color(0xFF29D3F0)];

/// 首页：每日推荐、我喜欢、私人 FM、根据你喜爱的歌曲推荐、我的歌单、推荐歌单。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  final ValueChanged<Destination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = width < 600 ? 16.0 : 24.0;
    final account = AccountScope.of(context);
    final playlists = account.playlists;

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
                          onTap: () => onNavigate(Destination.liked),
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
                const SizedBox(height: 32),
                _SectionTitle(
                  '我的歌单',
                  trailing: account.isLoggedIn
                      ? TextButton.icon(
                          onPressed: () => showCreatePlaylistDialog(context),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('新建'),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                if (!account.isLoggedIn)
                  const SizedBox(height: 220, child: LoginPrompt(message: '登录后查看你的歌单'))
                else if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('还没有歌单', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
            sliver: SliverPlaylistGrid(playlists: playlists),
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
  static ({int? userId, Future<SongRcmdBlock> future})? _cache;
  static var _lastPage = 0;

  late Future<SongRcmdBlock> _future = _cached();
  PageController? _pages;

  int? get _userId => AccountScope.read(context).profile?.userId;

  Future<SongRcmdBlock> _cached() {
    final c = _cache;
    if (c != null && c.userId == _userId) return c.future;
    _lastPage = 0;
    return _load();
  }

  Future<SongRcmdBlock> _load() {
    final future = AppScope.of(context).api.songRcmd();
    final entry = (userId: _userId, future: future);
    _cache = entry;
    // 失败的结果不留，下次进首页重新拉。
    future.catchError((Object _) {
      if (identical(_cache, entry)) _cache = null;
      return const SongRcmdBlock(title: '', items: []);
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

  Widget _body(
    AsyncSnapshot<SongRcmdBlock> snap,
    List<SongRcmd>? items,
    int columns,
    double fraction,
  ) {
    if (snap.hasError) {
      return Center(
        child: TextButton(onPressed: _refresh, child: const Text('推荐加载失败，点击重试')),
      );
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return const Center(
        child: Text('暂无推荐', style: TextStyle(color: AppColors.textSecondary)),
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
        return FutureBuilder<SongRcmdBlock>(
          future: _future,
          builder: (context, snap) {
            final items = snap.data?.items;
            final columns = items == null ? 0 : (items.length / _perColumn).ceil();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(
                  snap.data?.title ?? '根据你喜爱的歌曲推荐',
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
              ],
            );
          },
        );
      },
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
                      fontWeight: FontWeight.w600,
                      color: playing ? AppColors.accent : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (liked) ...[
                        const Icon(Icons.favorite_rounded, size: 14, color: AppColors.negative),
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
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
              icon: const Icon(Icons.play_arrow_rounded, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 红色小标签：推荐理由（浅底）或音质（描边）。
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
          color: filled ? AppColors.negative.withValues(alpha: 0.15) : null,
          border: Border.all(color: AppColors.negative.withValues(alpha: filled ? 0.25 : 0.8)),
          borderRadius: BorderRadius.circular(AppRadius.tag),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.negative,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (AccountScope.of(context).profile) {
          final p? => '${greetingFor(DateTime.now())}，${p.nickname}',
          null => greetingFor(DateTime.now()),
        }, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        const Text('由此开启好心情 ~', style: TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}

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
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 卡片底：圆角深色面板，悬停变亮。
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: padding,
        decoration: BoxDecoration(
          color: hovered && onTap != null ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
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
    return _Panel(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: CoverArt(
              palette: palette,
              seed: seed,
              imageUrl: imageUrl,
              fallbackImage: fallbackImage,
              radius: AppRadius.card,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
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
    // 正在放私人 FM：封面换成当前这首，点击打开播放页而不是重新开始。
    final playing = player.isRadio ? player.current : null;
    return _Panel(
      padding: const EdgeInsets.all(20),
      onTap: () => playing != null ? openNowPlaying(context) : _start(context),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: CoverArt(
              palette: playing?.palette ?? _fmPalette,
              seed: playing?.id ?? 'fm',
              imageUrl: playing?.coverUrl,
              radius: AppRadius.card,
              icon: playing == null ? Icons.radio_rounded : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Text('私人 FM', style: Theme.of(context).textTheme.titleLarge)]),
                const SizedBox(height: 6),
                Text(
                  playing == null ? '根据你的口味连续播放' : '正在播放：${playing.title} - ${playing.artist}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
