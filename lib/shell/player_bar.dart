import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/now_playing/now_playing_page.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/backdrop_color.dart';
import '../widgets/cover_art.dart';
import '../widgets/like_button.dart';
import '../widgets/round_icon_button.dart';
import 'desktop_shell.dart';

/// 底部迷你播放条，参考 Spotify：悬浮圆角卡片，底色取自封面，底边是一条细进度线。
///
/// 点歌曲信息进入播放页。在歌曲信息上左滑切上一首，右滑切下一首。
/// 队列为空时不显示。
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  /// 卡片高度。
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final song = player.current;
    if (song == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: height,
        decoration: BoxDecoration(
          color: backdropColorFor(player.palette),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          // 撑满卡片高度，歌曲信息和按钮在卡片里垂直居中。
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _SwipeToSkip(
                      onPrevious: player.previous,
                      onNext: player.next,
                      child: InkWell(
                        onTap: () => openNowPlaying(context),
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: 40,
                              child: Hero(
                                tag: 'now-playing-cover',
                                child: CoverArt(
                                  palette: song.palette,
                                  seed: song.id,
                                  imageUrl: song.coverUrl,
                                  radius: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  RoundIconButton(
                    icon: Icons.lyrics_outlined,
                    onPressed: () => openNowPlaying(context, showLyrics: true),
                    tooltip: '歌词',
                    size: 40,
                    iconSize: 22,
                    color: Colors.white,
                  ),
                  LikeButton(songId: song.id, color: Colors.white),
                  RoundIconButton(
                    icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    onPressed: player.toggle,
                    tooltip: player.isPlaying ? '暂停' : '播放',
                    size: 44,
                    iconSize: 30,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: _ProgressLine(fraction: player.progress),
            ),
          ],
        ),
      ),
    );
  }
}

/// 悬浮在页面内容上方的底部区域：迷你播放条，以及可选的底部导航。
///
/// 背景是从透明到页面底色的渐变，内容可以滚到它下面。
/// 搭配 `Scaffold(extendBody: true)` 使用，滚动内容底部用 [floatingBarsInset] 留白。
class FloatingBottomBar extends StatelessWidget {
  const FloatingBottomBar({super.key, this.navigation});

  /// 播放条下方的导航栏。为空时只有播放条，并自己处理底部安全区。
  final Widget? navigation;

  @override
  Widget build(BuildContext context) {
    // 电脑布局底部有常驻播放条，二级页面里不再重复显示。
    if (DesktopShellScope.isActive(context)) return const SizedBox.shrink();
    final nav = navigation;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background.withValues(alpha: nav == null ? 0.6 : 0.85),
            AppColors.background.withValues(alpha: 0.95),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nav == null)
            const SafeArea(top: false, child: PlayerBar())
          else ...[
            const PlayerBar(),
            nav,
          ],
        ],
      ),
    );
  }
}

/// 页面延伸到 [FloatingBottomBar] 下方时，滚动内容底部要留出的高度。
///
/// `Scaffold(extendBody: true)` 会把底栏高度算进 body 的 MediaQuery 底部 padding。
/// 不传 padding 的 ListView 会自动留出这段距离，其他滚动视图要手动加上。
double floatingBarsInset(BuildContext context) => MediaQuery.paddingOf(context).bottom;

/// 卡片底边的细进度线，只显示不响应手势（拖动进度到播放页里操作）。
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(1),
      child: SizedBox(
        height: 2,
        child: ColoredBox(
          color: Colors.white.withValues(alpha: 0.2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// 水平滑动切歌：内容跟手移动，松手时滑够距离或速度够快就切歌，然后回弹。
///
/// 左滑（手指向左）切上一首，右滑（手指向右）切下一首。
class _SwipeToSkip extends StatefulWidget {
  const _SwipeToSkip({required this.onPrevious, required this.onNext, required this.child});

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Widget child;

  @override
  State<_SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<_SwipeToSkip> with SingleTickerProviderStateMixin {
  /// 触发切歌的最小滑动距离（逻辑像素）。
  static const _distance = 56.0;

  /// 触发切歌的最小甩动速度（逻辑像素/秒）。
  static const _velocity = 600.0;

  late final _offset = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _onEnd(DragEndDetails d) {
    final dx = _offset.value;
    final v = d.primaryVelocity ?? 0;
    if (dx <= -_distance || v <= -_velocity) {
      HapticFeedback.selectionClick();
      widget.onPrevious();
    } else if (dx >= _distance || v >= _velocity) {
      HapticFeedback.selectionClick();
      widget.onNext();
    }
    _offset.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _offset.stop(),
        onHorizontalDragUpdate: (d) => _offset.value += d.primaryDelta ?? 0,
        onHorizontalDragEnd: _onEnd,
        onHorizontalDragCancel: () =>
            _offset.animateTo(0, duration: const Duration(milliseconds: 220)),
        child: AnimatedBuilder(
          animation: _offset,
          child: widget.child,
          builder: (context, child) {
            final dx = _offset.value;
            final fade = (1 - dx.abs() / c.maxWidth).clamp(0.3, 1.0);
            return Opacity(
              opacity: fade,
              child: Transform.translate(offset: Offset(dx, 0), child: child),
            );
          },
        ),
      ),
    );
  }
}
