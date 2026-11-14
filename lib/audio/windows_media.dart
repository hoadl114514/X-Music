import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../api/netease_api.dart';
import '../state/player_controller.dart';

/// Windows 的系统媒体控制（SMTC）：音量浮窗、锁屏上的正在播放卡片，
/// 以及键盘上的媒体键、蓝牙耳机按键。
///
/// 作用和 Android / iOS / macOS 上的 SystemMediaBridge 一样，
/// 只做双向同步，播放逻辑仍在 [PlayerController] 里。
class WindowsMediaBridge {
  WindowsMediaBridge._(this._player, this._smtc) {
    _buttons = _smtc.buttonPressStream.listen(_onButton);
    _player.addListener(_sync);
    _sync();
  }

  final PlayerController _player;
  final SMTCWindows _smtc;
  late final StreamSubscription<PressedButton> _buttons;

  /// 初始化 SMTC。失败（比如系统版本太老）时返回 null，不影响播放。
  static Future<WindowsMediaBridge?> register(PlayerController player) async {
    try {
      await SMTCWindows.initialize();
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: false,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
        enabled: false,
      );
      return WindowsMediaBridge._(player, smtc);
    } catch (e) {
      debugPrint('SMTC init failed: $e');
      return null;
    }
  }

  String? _songId;
  bool? _playing;
  Duration? _duration;
  Duration _lastPosition = Duration.zero;

  void _onButton(PressedButton b) {
    switch (b) {
      case PressedButton.play:
        unawaited(_player.play());
      case PressedButton.pause:
        unawaited(_player.pause());
      case PressedButton.next:
        unawaited(_player.next());
      case PressedButton.previous:
        unawaited(_player.previous());
      default:
        break;
    }
  }

  /// 控制器每 50ms 通知一次，这里只在切歌、播放状态变化、拖动进度时才推给系统。
  void _sync() {
    final song = _player.current;
    if (song == null) return;
    final calls = <Future<void>>[];
    if (song.id != _songId) {
      if (_songId == null) calls.add(_smtc.enableSmtc());
      _songId = song.id;
      calls.add(
        _smtc.updateMetadata(
          MusicMetadata(
            title: song.title,
            artist: song.artist,
            album: song.album,
            albumArtist: song.artist,
            thumbnail: song.coverUrl == null ? null : sizedImage(song.coverUrl!, 512),
          ),
        ),
      );
    }
    final playing = _player.isPlaying;
    if (playing != _playing) {
      _playing = playing;
      calls.add(_smtc.setPlaybackStatus(playing ? PlaybackStatus.playing : PlaybackStatus.paused));
    }
    final duration = _player.duration;
    final position = _player.position;
    // 进度每秒最多推一次；时长变化（试听片段加载完）立即推。
    if (duration != _duration || (position - _lastPosition).abs() > const Duration(seconds: 1)) {
      _duration = duration;
      _lastPosition = position;
      calls.add(
        _smtc.updateTimeline(
          PlaybackTimeline(
            startTimeMs: 0,
            endTimeMs: duration.inMilliseconds,
            positionMs: position.inMilliseconds,
            minSeekTimeMs: 0,
            maxSeekTimeMs: duration.inMilliseconds,
          ),
        ),
      );
    }
    for (final c in calls) {
      unawaited(c.catchError((Object e) => debugPrint('SMTC update failed: $e')));
    }
  }

  Future<void> dispose() async {
    _player.removeListener(_sync);
    await _buttons.cancel();
    await _smtc.dispose();
  }
}
