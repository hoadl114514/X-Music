import 'package:flutter/material.dart';

import '../app/app.dart';
import '../data/format.dart';
import '../pages/now_playing/now_playing_page.dart';
import '../pages/now_playing/song_menu.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/hover_builder.dart';
import '../widgets/like_button.dart';
import '../widgets/round_icon_button.dart';

/// 电脑布局底部常驻的播放条：左边歌曲信息，中间播放控制和进度，右边歌词、列表、音量。
///
/// 还没有播放过歌曲时也占位显示，只是按钮不可用。
class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({super.key});

  static const double height = 88;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final song = player.current;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: song == null
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        HoverBuilder(
                          onTap: () => openNowPlaying(context),
                          builder: (context, hovered) => SizedBox.square(
                            dimension: 56,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Hero(
                                  tag: 'now-playing-cover',
                                  child: CoverArt(
                                    palette: song.palette,
                                    seed: song.id,
                                    imageUrl: song.coverUrl,
                                    radius: 6,
                                  ),
                                ),
                                if (hovered)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        LikeButton(songId: song.id, size: 36, iconSize: 20),
                      ],
                    ),
            ),
            const Expanded(flex: 4, child: _Center()),
            Expanded(flex: 3, child: _Right(enabled: song != null)),
          ],
        ),
      ),
    );
  }
}

class _Center extends StatelessWidget {
  const _Center();

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final enabled = player.current != null;
    final mode = player.playMode;
    final (IconData modeIcon, String modeLabel) = switch (mode) {
      PlayMode.list when player.isRadio => (Icons.all_inclusive_rounded, '无限播放'),
      PlayMode.list => (Icons.repeat_rounded, mode.label),
      PlayMode.shuffle => (Icons.shuffle_rounded, mode.label),
      PlayMode.one => (Icons.repeat_one_rounded, mode.label),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RoundIconButton(
                icon: modeIcon,
                tooltip: modeLabel,
                size: 36,
                iconSize: 20,
                color: AppColors.textSecondary,
                onPressed: enabled
                    ? () {
                        player.cyclePlayMode();
                        AppScope.toast(
                          player.playMode == PlayMode.list && player.isRadio
                              ? '无限播放'
                              : player.playMode.label,
                        );
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                icon: Icons.skip_previous_rounded,
                tooltip: '上一首',
                size: 40,
                iconSize: 28,
                color: Colors.white,
                onPressed: enabled ? player.previous : null,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                tooltip: player.isPlaying ? '暂停' : '播放',
                size: 40,
                iconSize: 28,
                filled: true,
                background: Colors.white,
                color: Colors.black,
                onPressed: enabled ? player.toggle : null,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                icon: Icons.skip_next_rounded,
                tooltip: '下一首',
                size: 40,
                iconSize: 28,
                color: Colors.white,
                onPressed: enabled ? player.next : null,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                icon: Icons.lyrics_outlined,
                tooltip: '歌词',
                size: 36,
                iconSize: 20,
                color: AppColors.textSecondary,
                onPressed: enabled ? () => openNowPlaying(context, showLyrics: true) : null,
              ),
            ],
          ),
          const SizedBox(height: 2),
          const _SeekRow(),
        ],
      ),
    );
  }
}

/// 进度条，两端是时间。悬停时变粗并显示拖动点。
class _SeekRow extends StatefulWidget {
  const _SeekRow();

  @override
  State<_SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends State<_SeekRow> {
  double? _dragging;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final total = player.duration;
    final enabled = player.current != null && total > Duration.zero;
    final value = (_dragging ?? player.progress).clamp(0.0, 1.0);
    const timeStyle = TextStyle(
      fontSize: 11.5,
      color: AppColors.textSecondary,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final active = _hovered || _dragging != null;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            formatDuration(total * value),
            textAlign: TextAlign.right,
            softWrap: false,
            style: timeStyle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: active ? AppColors.accent : Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: active ? 6 : 0,
                  disabledThumbRadius: 0,
                  elevation: 0,
                ),
                padding: EdgeInsets.zero,
              ),
              child: SizedBox(
                height: 16,
                child: Slider(
                  value: value,
                  onChanged: enabled ? (v) => setState(() => _dragging = v) : null,
                  onChangeEnd: enabled
                      ? (v) {
                          player.seek(total * v);
                          setState(() => _dragging = null);
                        }
                      : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 52, child: Text(formatDuration(total), softWrap: false, style: timeStyle)),
      ],
    );
  }
}

class _Right extends StatelessWidget {
  const _Right({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final v = player.volume;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        RoundIconButton(
          icon: Icons.queue_music_rounded,
          tooltip: '播放列表',
          size: 36,
          iconSize: 20,
          color: AppColors.textSecondary,
          onPressed: enabled ? () => showQueueSheet(context) : null,
        ),
        RoundIconButton(
          icon: v == 0
              ? Icons.volume_off_rounded
              : v < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          tooltip: v == 0 ? '取消静音' : '静音',
          size: 36,
          iconSize: 20,
          color: AppColors.textSecondary,
          onPressed: () => player.setVolume(v == 0 ? 1 : 0),
        ),
        SizedBox(
          width: 110,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Tooltip(
              message: '音量 ${(v * 100).round()}%',
              child: Slider(value: v, onChanged: player.setVolume),
            ),
          ),
        ),
      ],
    );
  }
}
