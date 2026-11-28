import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_cache.dart';
import 'caching_source.dart';

/// 播放器内核。抽出接口是为了测试里换成假的实现。
abstract class AudioEngine {
  /// 加载地址并停在 [start]，不自动播放。本地文件传 `file://` 地址。
  /// 给了 [cacheTo] 时边播边写进听歌缓存。
  Future<void> load(String url, {Duration start = Duration.zero, CacheSlot? cacheTo});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// 当前位置。播放中会按时间外推，可以高频读取。
  Duration get position;

  /// 当前音频的时长；未知时为 null。
  Duration? get duration;

  /// 播放到结尾。
  Stream<void> get completed;

  /// 播放过程中出错（解码失败、网络中断等）。
  Stream<Object> get errors;

  /// 内核自己改了播放 / 暂停（不是 [play] / [pause] 调的）：
  /// 被其他应用抢走音频焦点、来电、拔耳机时暂停（false），焦点回来后自动继续（true），
  /// 申请不到音频焦点时 play 没放起来（false）。
  Stream<bool> get playingChanges;

  /// 丢掉原生播放器重新建一个（输出位深、采样率改了要重建才生效）。之后要重新 [load]。
  Future<void> rebuild();

  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  /// [mixWithOthers] 为 true 时不申请音频焦点：和其他应用同时出声，互不打断。
  /// 改了之后要 [rebuild] 才生效。
  JustAudioEngine({bool Function()? mixWithOthers}) : _mix = mixWithOthers ?? (() => false) {
    _listen();
  }

  final bool Function() _mix;

  void _listen() {
    _sub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _completed.add(null);
    }, onError: (Object e, StackTrace _) => _errors.add(e));
    // 事件是异步送达的，按送达时内核的真实状态比，不按事件里的值比，
    // 否则连续 play / pause 时迟到的旧事件会被当成内核自己改的。
    _playingSub = _player.playingStream.listen((_) {
      final now = _player.playing;
      if (now == _requested) return;
      _requested = now;
      _playingChanges.add(now);
    });
  }

  /// 声明为音乐播放，交给系统处理来电、其他应用抢占等打断。
  /// [mixWithOthers] 时 iOS 上和其他应用混音（Android 靠不申请焦点实现）。
  static Future<void> configureSession({bool mixWithOthers = false}) async {
    final session = await AudioSession.instance;
    const music = AudioSessionConfiguration.music();
    await session.configure(
      mixWithOthers
          ? music.copyWith(
              avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
            )
          : music,
    );
  }

  AudioPlayer _create() {
    final mix = _mix();
    // 不接管音频焦点时也不处理打断：没有焦点就收不到打断事件。
    return AudioPlayer(handleInterruptions: !mix, handleAudioSessionActivation: !mix);
  }

  late var _player = _create();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final _playingChanges = StreamController<bool>.broadcast();
  late StreamSubscription<PlayerState> _sub;
  late StreamSubscription<bool> _playingSub;

  /// 最近一次 [play] / [pause] 要的状态。内核实际状态和它不一样，就是内核自己改的。
  bool _requested = false;

  CachingAudioSource? _caching;

  @override
  Future<void> load(String url, {Duration start = Duration.zero, CacheSlot? cacheTo}) async {
    // 不要传 headers：网易云音频 CDN 不校验 Referer，直接请求即可。
    // 边播边缓存时 just_audio 会在本机起一个明文 HTTP 代理（127.0.0.1），
    // 网络安全配置里已对 127.0.0.1 放开明文，否则会表现为 "(0) Source error"。
    _caching?.dispose();
    _caching = null;
    final uri = Uri.parse(url);
    final AudioSource source;
    if (cacheTo != null && !kIsWeb) {
      source = _caching = CachingAudioSource(uri, cacheTo);
    } else {
      source = AudioSource.uri(uri);
    }
    await _player.setAudioSource(source, initialPosition: start);
  }

  /// just_audio 的 play() 要等到暂停或播完才返回，这里不等它。
  @override
  Future<void> play() async {
    _requested = true;
    unawaited(_player.play().catchError((Object e) => _errors.add(e)));
  }

  @override
  Future<void> pause() {
    _requested = false;
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Stream<bool> get playingChanges => _playingChanges.stream;

  @override
  Future<void> rebuild() async {
    final old = _player;
    await _sub.cancel();
    await _playingSub.cancel();
    _caching?.dispose();
    _caching = null;
    final mix = _mix();
    await configureSession(mixWithOthers: mix);
    _requested = false;
    _player = _create();
    _listen();
    await old.dispose();
    // 改成同时播放：把之前拿着的音频焦点还回去，别的应用才不会被暂停。
    if (mix && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final session = await AudioSession.instance;
      await session.setActive(false).catchError((Object _) => false);
    }
  }

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await _playingSub.cancel();
    _caching?.dispose();
    await _player.dispose();
    await _completed.close();
    await _errors.close();
    await _playingChanges.close();
  }
}
