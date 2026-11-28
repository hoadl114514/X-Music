import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../music/nav.dart';
import '../../state/player_controller.dart';
import '../../theme/app_theme.dart';
import '../listen_together_page.dart';
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
import 'song_wiki_view.dart';

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
    Navigator.of(context).push(
      slideUpRoute(
        // 播放页保持原来的沉浸式暗色，不跟主界面的浅色 / 动态取色走。
        Theme(
          data: _immersive,
          child: NowPlayingPage(initialLyrics: showLyrics),
        ),
      ),
    );

final _immersive = AppTheme.immersive();

/// 全屏播放页：流光背景，中间三页左右滑动：歌词 ← 封面 → 百科（默认停在封面，
/// 右滑看歌词，左滑看百科），下方控制区三页共用。下滑收起。
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key, this.initialLyrics = false});

  final bool initialLyrics;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  static const _hPad = EdgeInsets.symmetric(horizontal: 24);

  // 从左到右：百科、封面、歌词。右滑看百科，左滑看歌词。
  static const _wikiPage = 0;
  static const _coverPage = 1;
  static const _lyricsPage = 2;

  late final _pages = PageController(initialPage: widget.initialLyrics ? _lyricsPage : _coverPage);

  /// 只在封面页显示进度条和播放按钮；百科页和歌词页收起，留更多空间给内容。
  late bool _controlsHidden = _pages.initialPage != _coverPage;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      final hidden = (_pages.page ?? _coverPage.toDouble()).round() != _coverPage;
      if (hidden != _controlsHidden) setState(() => _controlsHidden = hidden);
    });
  }

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
    if (song == null) return Scaffold(backgroundColor: context.colors.background);

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
          child: SafeArea(
            // 左右留白放在每一页里面而不是整个页面外面：PageView 占满屏宽，
            // 滑动时页面从屏幕边缘进出，不会在留白处被切出一道硬边。
            child: Column(
              children: [
                Padding(
                  padding: _hPad,
                  child: _TopBar(onWiki: () => _goTo(_wikiPage)),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    children: [
                      Padding(
                        padding: _hPad,
                        child: _WikiPane(song: song, onTapHeader: () => _goTo(_coverPage)),
                      ),
                      Padding(
                        padding: _hPad,
                        child: _CoverPane(song: song, onTapCover: () => _goTo(_lyricsPage)),
                      ),
                      Padding(
                        padding: _hPad,
                        child: _LyricsPane(song: song, onTapHeader: () => _goTo(_coverPage)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _PageDots(controller: _pages, count: 3),
                const SizedBox(height: 8),
                ClipRect(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    heightFactor: _controlsHidden ? 0 : 1,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _controlsHidden ? 0 : 1,
                      child: IgnorePointer(
                        ignoring: _controlsHidden,
                        child: const Padding(
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
                      ),
                    ),
                  ),
                ),
                // 在一起听房间里时显示一起听条。不在房间时，封面页留一段空白方便拇指按；
                // 百科页和歌词页没有播放控制，不留空白，内容一直铺到底。
                ListenTogetherBar(idleGap: _controlsHidden ? 0 : ListenTogetherBar.defaultIdleGap),
              ],
            ),
          ),
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
  const _TopBar({required this.onWiki});

  /// 「更多」里点「歌曲百科」：翻到百科页。
  final VoidCallback onWiki;

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
              onPressed: () => showSongMenu(context, onWiki: onWiki),
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
  final VoidCallback onTapCover;

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

/// 歌词页（封面左边一页）：顶部小封面和歌名，下面是歌词。点顶部或向左滑回到封面。
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

/// 百科页（封面右边一页）：顶部小封面和歌名，下面是歌曲百科。点顶部或向右滑回到封面。
class _WikiPane extends StatelessWidget {
  const _WikiPane({required this.song, required this.onTapHeader});

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
                child: CoverArt(
                  palette: song.palette,
                  seed: song.id,
                  imageUrl: song.coverUrl,
                  radius: 6,
                  shadow: AppShadows.medium,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _TitleRow(song: song, large: false)),
            ],
          ),
        ),
        Expanded(
          child: ShaderMask(
            shaderCallback: _fadeEdges,
            blendMode: BlendMode.dstIn,
            child: SongWikiView(song: song),
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
        // 封面页：喜欢、收藏到歌单。百科页和歌词页没有下面的播放控制，换成上一首、播放、下一首。
        if (large) ...[
          LikeButton(songId: song.id, size: 44, iconSize: 26, color: Colors.white),
          RoundIconButton(
            icon: Icons.playlist_add_rounded,
            tooltip: '收藏到歌单',
            color: Colors.white,
            size: 44,
            iconSize: 24,
            onPressed: () => showAddToPlaylistSheet(context, song),
          ),
        ] else ...[
          RoundIconButton(
            icon: Icons.skip_previous_rounded,
            tooltip: '上一首',
            color: Colors.white,
            size: 40,
            iconSize: 28,
            onPressed: PlayerScope.read(context).previous,
          ),
          const PlayPauseButton(size: 44),
          RoundIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: '下一首',
            color: Colors.white,
            size: 40,
            iconSize: 28,
            onPressed: PlayerScope.read(context).next,
          ),
        ],
      ],
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
