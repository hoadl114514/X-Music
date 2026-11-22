import 'package:flutter/material.dart';

/// Material 3 动效的几个小部件。曲线和时长用 M3 规范里的 [Easing] 和 [Durations]。

/// 淡入切换（M3 fade through）：[trigger] 变化时，新内容从 92% 放大到 100% 并淡入。
///
/// 用在底部标签切换上：子树不重建，[IndexedStack] 里的页面状态都保留。
class FadeThrough extends StatefulWidget {
  const FadeThrough({super.key, required this.trigger, required this.child});

  final Object trigger;
  final Widget child;

  @override
  State<FadeThrough> createState() => _FadeThroughState();
}

class _FadeThroughState extends State<FadeThrough> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Durations.medium2, value: 1);
  late final _curve = CurvedAnimation(parent: _c, curve: Easing.emphasizedDecelerate);
  late final _scale = Tween(begin: 0.92, end: 1.0).animate(_curve);

  @override
  void didUpdateWidget(FadeThrough old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

/// 入场动画：第一次出现时从下方 24 像素滑上来并淡入。[index] 越大越晚开始，做成逐块入场。
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  /// 相邻两块的间隔。
  static const stagger = Duration(milliseconds: 60);

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Durations.long2 + Entrance.stagger * widget.index,
  )..forward();

  late final _curve = CurvedAnimation(
    parent: _c,
    curve: Interval(
      (Entrance.stagger * widget.index).inMilliseconds / _c.duration!.inMilliseconds,
      1,
      curve: Easing.emphasizedDecelerate,
    ),
  );

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, 24 * (1 - _curve.value)), child: child),
      ),
    );
  }
}

/// 按下时轻微缩小到 97%，松手弹回。只改视觉，不拦截手势。
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? Durations.short2 : Durations.medium1,
        curve: _down ? Easing.standardAccelerate : Easing.emphasizedDecelerate,
        child: widget.child,
      ),
    );
  }
}
