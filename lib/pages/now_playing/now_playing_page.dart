import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../comments/comments_page.dart';
import '../music/nav.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/copy_sheet.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/flow_background.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/like_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/share.dart';
import 'lyrics_view.dart';
import 'player_controls.dart';
import 'song_menu.dart';

/// 从底部滑出的页面路由。
Route<void> slideUpRoute(Widget page) => PageRouteBuilder<void>(
  transitionDuration: const Duration(milliseconds: 380),
  reverseTransitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    ),
    child: child,
  ),
);

/// 打开播放页；[showLyrics] 为 true 时直接显示歌词。
Future<void> openNowPlaying(BuildContext context, {bool showLyrics = false}) =>
    Navigator.of(context).push(slideUpRoute(NowPlayingPage(initialLyrics: showLyrics)));

/// 全屏播放页：流光背景，中间左右滑动在「封面」和「歌词」两页间切换（歌词在右边），
/// 下方控制区两页共用。下滑收起。
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key, this.initialLyrics = false});

  final bool initialLyrics;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

/// 窗口宽度达到这个值时，封面和歌词左右并排显示。
const double _wideBreakpoint = 900;

class _NowPlayingPageState extends State<NowPlayingPage> {
  static const _hPad = EdgeInsets.symmetric(horizontal: 24);

  late final _pages = PageController(initialPage: widget.initialLyrics ? 1 : 0);

  void _goTo(int page) => _pages.animateToPage(
    page,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final song = player.current;
    if (song == null) return const Scaffold(backgroundColor: AppColors.background);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // 歌词列表、进度条自己的拖动优先；这里只接空白处的快速下滑。
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 700) Navigator.of(context).maybePop();
        },
        child: FlowBackground(
          palette: player.palette,
          imageUrl: song.coverUrl,
          child: MediaQuery.sizeOf(context).width >= _wideBreakpoint
              ? _WideLayout(song: song)
              : SafeArea(
                  // 左右留白放在每一页里面而不是整个页面外面：PageView 占满屏宽，
                  // 滑动时页面从屏幕边缘进出，不会在留白处被切出一道硬边。
                  child: Column(
                    children: [
                      const Padding(padding: _hPad, child: _TopBar()),
                      Expanded(
                        child: PageView(
                          controller: _pages,
                          children: [
                            Padding(
                              padding: _hPad,
                              child: _CoverPane(song: song, onTapCover: () => _goTo(1)),
                            ),
                            Padding(
                              padding: _hPad,
                              child: _LyricsPane(song: song, onTapHeader: () => _goTo(0)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PageDots(controller: _pages, count: 2),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: _hPad,
                        child: Column(
                          children: [
                            SeekBar(),
                            SizedBox(height: 4),
                            _QualityPill(),
                            SizedBox(height: 12),
                            _Controls(),
                          ],
                        ),
                      ),
                      // 控制区离底部留够距离，单手拇指更好按。
                      const SizedBox(height: 56),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// 宽屏播放页（电脑、平板横屏）：左边封面和歌名，右边歌词，底部控制区居中。
class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
        child: Column(
          children: [
            const _TopBar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: _CoverPane(song: song, onTapCover: null),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  const Expanded(
                    flex: 6,
                    child: ShaderMask(
                      shaderCallback: _fadeEdges,
                      blendMode: BlendMode.dstIn,
                      child: LyricsView(fontSize: 30, anchor: 0.38, depth: true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: const Column(
                children: [
                  SeekBar(),
                  SizedBox(height: 4),
                  _QualityPill(),
                  SizedBox(height: 8),
                  _Controls(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面 / 歌词两页的位置指示。
class _PageDots extends StatelessWidget {
  const _PageDots({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 6 + 8 * (1 - (page - i).abs()).clamp(0.0, 1.0),
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    Colors.white24,
                    Colors.white70,
                    (1 - (page - i).abs()).clamp(0.0, 1.0),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        // 下拉提示条。
        Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(3)),
        ),
        Row(
          children: [
            RoundIconButton(
              icon: Icons.keyboard_arrow_down_rounded,
              onPressed: Navigator.of(context).maybePop,
              tooltip: '收起',
              color: Colors.white70,
              iconSize: 28,
            ),
            Expanded(
              child: Text(
                PlayerScope.of(context).queueTitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
            RoundIconButton(
              icon: Icons.share_outlined,
              onPressed: () {
                final song = PlayerScope.read(context).current;
                if (song != null) shareSong(song);
              },
              tooltip: '分享',
              color: Colors.white70,
              iconSize: 22,
            ),
            RoundIconButton(
              icon: Icons.more_horiz_rounded,
              onPressed: () => showSongMenu(context),
              tooltip: '更多',
              color: Colors.white70,
              iconSize: 24,
            ),
          ],
        ),
      ],
    );
  }
}

/// 封面页：大封面 + 歌名歌手。点封面或向左滑切到歌词。
class _CoverPane extends StatelessWidget {
  const _CoverPane({required this.song, required this.onTapCover});

  final Song song;

  /// 点封面切到歌词。宽屏下歌词一直显示，为 null。
  final VoidCallback? onTapCover;

  @override
  Widget build(BuildContext context) {
    final playing = PlayerScope.of(context).isPlaying;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: onTapCover,
              onLongPress: song.coverUrl == null
                  ? null
                  : () => ImageViewerPage.open(context, song.coverUrl!, title: song.title),
              child: Hero(
                tag: 'now-playing-cover',
                child: AnimatedScale(
                  // 暂停时封面缩小一点，播放时弹回。
                  scale: playing ? 1 : 0.86,
                  duration: const Duration(milliseconds: 500),
                  curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: playing ? 0.45 : 0.25),
                          offset: Offset(0, playing ? 18 : 8),
                          blurRadius: playing ? 40 : 20,
                        ),
                      ],
                    ),
                    child: CoverArt(
                      palette: song.palette,
                      seed: song.id,
                      imageUrl: song.coverUrl,
                      radius: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _TitleRow(song: song, large: true),
      ],
    );
  }
}

/// 歌词页：顶部小封面和歌名，下面是歌词。点顶部或向右滑回到封面。
class _LyricsPane extends StatelessWidget {
  const _LyricsPane({required this.song, required this.onTapHeader});

  final Song song;
  final VoidCallback onTapHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTapHeader,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              SizedBox.square(
                dimension: 52,
                child: ViewableImage(
                  url: song.coverUrl,
                  title: song.title,
                  child: CoverArt(
                    palette: song.palette,
                    seed: song.id,
                    imageUrl: song.coverUrl,
                    radius: 6,
                    shadow: AppShadows.medium,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _TitleRow(song: song, large: false)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Expanded(
          child: ShaderMask(
            // 上下边缘淡出。
            shaderCallback: _fadeEdges,
            blendMode: BlendMode.dstIn,
            child: LyricsView(fontSize: 28, anchor: 0.25, depth: true),
          ),
        ),
      ],
    );
  }
}

Shader _fadeEdges(Rect r) => const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
  stops: [0, 0.08, 0.88, 1],
).createShader(r);

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.song, required this.large});

  final Song song;
  final bool large;

  /// 点歌手名：先选歌手（多位时），再收起播放页、打开歌手主页。
  Future<void> _openArtist(BuildContext context) async {
    final nav = Navigator.of(context);
    final artist = await pickSongArtist(context, song);
    if (artist == null || !nav.mounted) return;
    nav.pop();
    await openArtist(nav.context, artist);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          // 长按歌名 / 歌手选择复制哪个。
          child: GestureDetector(
            onLongPress: () => showCopySongSheet(context, song),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: large ? 22 : 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: song.artists.isEmpty ? null : () => _openArtist(context),
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: large ? 16 : 14, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
        ),
        LikeButton(
          songId: song.id,
          size: large ? 44 : 40,
          iconSize: large ? 26 : 24,
          color: Colors.white,
        ),
        _CommentButton(song: song, size: large ? 44 : 40, iconSize: large ? 24 : 22),
      ],
    );
  }
}

/// 评论按钮，右上角带评论数（超过 999 显示 999+）。
class _CommentButton extends StatefulWidget {
  const _CommentButton({required this.song, required this.size, required this.iconSize});

  final Song song;
  final double size;
  final double iconSize;

  @override
  State<_CommentButton> createState() => _CommentButtonState();
}

class _CommentButtonState extends State<_CommentButton> {
  /// 每首歌只取一次评论数，封面 / 歌词两页和反复打开播放页共用。
  static final _counts = <String, int>{};
  static final _pending = <String, Future<int>>{};

  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CommentButton old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) _load();
  }

  void _load() {
    final id = widget.song.id;
    _count = _counts[id];
    if (_count != null) return;
    final api = AppScope.of(context).api;
    _pending
        .putIfAbsent(
          id,
          () => api
              .comments(CommentTarget.song.threadId(id), pageSize: 1)
              .then((p) => _counts[id] = p.total)
              // 注意不能写成 `=> _pending.remove(id)`：remove 返回的就是这个 future 本身，
              // whenComplete 会等它完成，自己等自己，后面的 setState 永远不会执行。
              .whenComplete(() {
                _pending.remove(id);
              }),
        )
        .then((n) {
          if (mounted && widget.song.id == id) setState(() => _count = n);
        })
        .catchError((Object _) {}); // 取不到就不显示数字。
  }

  @override
  Widget build(BuildContext context) {
    final n = _count;
    // 右边多留一点宽度给评论数，免得「999+」伸出屏幕边缘。
    return SizedBox(
      width: widget.size + 16,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          RoundIconButton(
            icon: Icons.mode_comment_outlined,
            onPressed: () => CommentsPage.openSong(context, widget.song),
            tooltip: '评论',
            color: Colors.white,
            size: widget.size,
            iconSize: widget.iconSize,
          ),
          if (n != null && n > 0)
            Positioned(
              left: widget.size * 0.62,
              top: widget.size * 0.08,
              child: IgnorePointer(
                child: Text(
                  n > 999 ? '999+' : '$n',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 进度条下方居中的音质标签，点开选择。只列出这首歌提供的档位。
class _QualityPill extends StatelessWidget {
  const _QualityPill();

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final q = player.quality;
    final label = [
      if (q != null) q.label else if (player.isLoading) '加载中' else '音质',
      if (player.trial != null) '试听',
    ].join(' · ');
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: player.qualities.isEmpty ? null : () => showQualitySheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final mode = player.playMode;
    final radio = player.isRadio;
    final (IconData icon, String label) = switch (mode) {
      PlayMode.list when radio => (Icons.all_inclusive_rounded, '无限播放'),
      PlayMode.list => (Icons.repeat_rounded, mode.label),
      PlayMode.shuffle => (Icons.shuffle_rounded, mode.label),
      PlayMode.one => (Icons.repeat_one_rounded, mode.label),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RoundIconButton(
          icon: icon,
          onPressed: () {
            player.cyclePlayMode();
            final next = player.playMode;
            AppScope.toast(next == PlayMode.list && radio ? '无限播放' : next.label);
          },
          tooltip: label,
          color: Colors.white70,
          size: 44,
          iconSize: 24,
        ),
        RoundIconButton(
          icon: Icons.skip_previous_rounded,
          onPressed: player.previous,
          tooltip: '上一首',
          color: Colors.white,
          size: 60,
          iconSize: 40,
        ),
        const PlayPauseButton(size: 76),
        RoundIconButton(
          icon: Icons.skip_next_rounded,
          onPressed: player.next,
          tooltip: '下一首',
          color: Colors.white,
          size: 60,
          iconSize: 40,
        ),
        RoundIconButton(
          icon: Icons.queue_music_rounded,
          onPressed: () => showQueueSheet(context),
          tooltip: '播放列表',
          color: Colors.white70,
          size: 44,
          iconSize: 24,
        ),
      ],
    );
  }
}
