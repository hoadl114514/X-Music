import 'package:flutter/material.dart';

import '../../data/format.dart';
import '../../state/player_controller.dart';

/// 白色细进度条，时间显示在下方两端。拖动时不跟随播放进度，松手再跳转。
class SeekBar extends StatefulWidget {
  const SeekBar({super.key});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.ticking(context);
    final total = player.duration;
    final value = _dragging ?? player.progress;
    const timeStyle = TextStyle(
      fontSize: 12,
      color: Colors.white70,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: _dragging == null ? 3 : 6,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbColor: Colors.white,
            overlayColor: Colors.white12,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: _dragging == null ? 0 : 7,
              elevation: 0,
            ),
            // 让轨道和下面的时间左右对齐。
            padding: EdgeInsets.zero,
          ),
          child: SizedBox(
            height: 24,
            child: Slider(
              value: value,
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: (v) {
                player.seek(total * v);
                setState(() => _dragging = null);
              },
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatDuration(total * value), style: timeStyle),
            Text('-${formatDuration(total * (1 - value))}', style: timeStyle),
          ],
        ),
      ],
    );
  }
}

/// 无底色的大播放键，图标切换时带一点缩放。
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final playing = player.isPlaying;
    return Tooltip(
      message: playing ? '暂停' : '播放',
      child: SizedBox.square(
        dimension: size,
        child: Material(
          type: MaterialType.circle,
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: player.toggle,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(playing),
                size: size * 0.7,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
