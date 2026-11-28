import 'dart:async';

import 'package:flutter/painting.dart';

import '../api/cookies.dart';
import '../api/netease_api.dart';
import '../audio/audio_cache.dart';
import '../audio/audio_engine.dart';
import '../audio/audio_output.dart';
import '../audio/listen_cache.dart';
import '../audio/system_media.dart';
import '../data/track_cache.dart';
import '../lyrics/amll_lyrics.dart';
import '../lyrics/lyric_service.dart';
import '../lyrics/qq_lyrics.dart';
import '../state/account_controller.dart';
import '../state/player_controller.dart';
import '../state/listen_together.dart';
import '../state/settings.dart';
import '../widgets/image_disk_cache.dart';
import 'update_checker.dart';

/// 应用级的单例集合，在 main 里建好后整个往下传。
class AppServices {
  AppServices({
    required this.settings,
    required this.api,
    required this.account,
    required this.player,
    this.audioCache,
    PlaylistTracks? tracks,
    DataCache? data,
    this.listenCache,
    this.updates,
  }) : tracks = tracks ?? PlaylistTracks(api),
       data = data ?? DataCache();

  /// 正式环境：真实网络 + just_audio。
  static Future<AppServices> create() async {
    // 内存里多留些解码好的图（默认 100MB 只够二三十张大封面），切页面回来不用重新解码。
    PaintingBinding.instance.imageCache
      ..maximumSize = 2000
      ..maximumSizeBytes = 256 << 20;
    unawaited(ImageDiskCache.prune());
    final settings = await AppSettings.load();
    final api = NeteaseApi(cookies: parseCookie(settings.cookie), deviceId: settings.deviceId);
    // 歌单歌曲、歌词、音质、账号和各列表都存在同一个目录，都算在听歌缓存里。
    final store = FileTrackStore();
    final data = DataCache(store: store);
    final lyrics = LyricService(netease: api, qq: QqLyrics(), amll: AmllLyrics(), store: data);
    // 上限是歌曲、图片和数据加起来的；歌曲按剩下的空间清理。
    final listenCache = ListenCache(data: data);
    final audioCache = AudioCache.system(
      limit: () {
        final limit = settings.audioCacheLimit;
        return limit <= 0 ? limit : limit - listenCache.otherBytes;
      },
    );
    listenCache.audio = audioCache;
    unawaited(listenCache.refresh());
    unawaited(audioCache.init());
    await JustAudioEngine.configureSession(mixWithOthers: settings.mixWithOthers);
    final player = PlayerController(
      engine: JustAudioEngine(mixWithOthers: () => settings.mixWithOthers),
      backend: NeteaseBackend(api, lyrics),
      settings: settings,
      cache: audioCache,
      data: data,
      output: const AudioOutput(),
    );
    // 播放器建好前先把输出设置（设备、位深、采样率、USB 独占）告诉原生端。
    unawaited(player.applyOutput());
    final account = AccountController(api: api, settings: settings, data: data);
    // 注册系统媒体会话（Android 前台服务 + 通知、iOS 锁屏），保证后台持续播放。
    await SystemMediaBridge.register(player, account);
    return AppServices(
      settings: settings,
      api: api,
      account: account,
      player: player,
      audioCache: audioCache,
      tracks: PlaylistTracks(api, store: store),
      data: data,
      listenCache: listenCache,
      updates: UpdateChecker(settings: settings),
    );
  }

  final AppSettings settings;
  final NeteaseApi api;
  final AccountController account;
  final PlayerController player;

  /// 一起听。
  late final listen = ListenTogether(api: api, player: player, account: account);

  /// 听歌缓存。测试里为 null。
  final AudioCache? audioCache;

  /// 歌单歌曲（带本地缓存）。
  final PlaylistTracks tracks;

  /// 页面数据的本地缓存（最近播放、听歌排行等）。测试里只存内存。
  final DataCache data;

  /// 听歌缓存的总账（歌曲、图片、数据）。测试里为 null。
  final ListenCache? listenCache;

  /// 检查 GitHub Release 更新。测试里为 null，不访问网络。
  final UpdateChecker? updates;

  void dispose() {
    listen.dispose();
    player.dispose();
    audioCache?.dispose();
    listenCache?.dispose();
    account.dispose();
    api.close();
    updates?.dispose();
  }
}
