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

  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  JustAudioEngine() {
    _sub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _completed.add(null);
    }, onError: (Object e, StackTrace _) => _errors.add(e));
  }

  /// 声明为音乐播放，交给系统处理来电、其他应用抢占等打断。
  static Future<void> configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  final _player = AudioPlayer();
  final _completed = StreamController<void>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<PlayerState> _sub;

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
  Future<void> play() async => unawaited(_player.play().catchError((Object e) => _errors.add(e)));

  @override
  Future<void> pause() => _player.pause();

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
  Future<void> dispose() async {
    await _sub.cancel();
    _caching?.dispose();
    await _player.dispose();
    await _completed.close();
    await _errors.close();
  }
}
